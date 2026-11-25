//
//  SFDaemonListener.m
//  Sevenfold
//
//  BY: T4MAG0
//
//  Everything here runs on the main queue; calls arriving from XPC or system
//  notifications hop over first (SF_ON_MAIN).
//
//  Schedule:   times and days come from the app's settings. The next run is stored as
//              "nextFireDate", armed as a timer, and backed by a hardware wake 3 s later
//              so a sleeping phone still runs on time.
//  Launching:  Sevenfold is opened in the background and told what to do over XPC.
//              Until it connects, requests wait in a queue; the launch is retried
//              (1, 2, 4, 8, 8 s) and after that left for the next unlock.
//  Staying up: while signing, a process assertion keeps the app from being suspended
//              and a power assertion keeps the phone from sleeping, both for at most 5 min.
//

#import "SFDaemonListener.h"
#import "SFApplicationProtocol.h"
#import <mach/mach_error.h>
#import <notify.h>
#import "Headers/IOKit/IOMessage.h"
#import "Headers/IOKit/ps/IOPowerSources.h"
#import "Headers/IOKit/ps/IOPSKeys.h"
#import "Headers/IOKit/pwr_mgt/IOPMLibPrivate.h"

#define SF_APP_ID      "com.t4mag0.sevenfold"
#define SF_SERVICE_ID  "com.t4mag0.sevenfoldd"
#define SF_ON_MAIN(call) if (![NSThread isMainThread]) { dispatch_async(dispatch_get_main_queue(), ^{ call; }); return; }

static const NSUInteger SFLaunchRetryLimit = 5;
static const NSTimeInterval SFKeepAwakeLimit = 300;   // seconds

#pragma mark - Private system API

BOOL SBSProcessIDForDisplayIdentifier(CFStringRef identifier, pid_t *pid);
int SBSLaunchApplicationWithIdentifier(CFStringRef identifier, BOOL suspended);
int SBSLaunchApplicationWithIdentifierAndLaunchOptions(CFStringRef identifier, CFDictionaryRef options, BOOL suspended);
CFStringRef SBSApplicationLaunchingErrorString(int error);
extern NSString *BKSActivateForEventOptionTypeBackgroundContentFetching;
extern NSString *BKSOpenApplicationOptionKeyActivateForEvent;

enum { SFAssertionPreventSuspend = 1 << 0, SFAssertionAllowIdleSleep = 1 << 2 };
enum { SFAssertionReasonFinishTask = 4 };

@interface BKSProcessAssertion : NSObject
- (id)initWithPID:(pid_t)pid flags:(unsigned int)flags reason:(unsigned int)reason name:(NSString *)name withHandler:(void (^)(BOOL success))handler;
- (void)invalidate;
@end

typedef NS_ENUM(NSUInteger, SFAppRequest) {
    SFAppRequestSign,
    SFAppRequestSignPlugIn,
    SFAppRequestCheckSignIn,
    SFAppRequestShowQueued,
};

#pragma mark - Log (shown in Settings › Diagnostics)

static void SFServiceLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void SFServiceLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[[NSString alloc] initWithFormat:format arguments:args] stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    va_end(args);
    NSLog(@"[sevenfoldd] %@", message);

    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("com.t4mag0.sevenfoldd.log", DISPATCH_QUEUE_SERIAL); });
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    dispatch_async(queue, ^{
        NSString *folder = @"/var/mobile/Library/Application Support/Sevenfold";
        NSString *path = [folder stringByAppendingPathComponent:@"daemon.log"];
        NSFileManager *fm = [NSFileManager defaultManager];
        NSData *line = [[NSString stringWithFormat:@"%.0f\t%@\n", now, message] dataUsingEncoding:NSUTF8StringEncoding];
        if (![fm fileExistsAtPath:folder])
            [fm createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:@{ NSFileOwnerAccountName: @"mobile", NSFileGroupOwnerAccountName: @"mobile" } error:nil];
        if (![fm fileExistsAtPath:path]) {
            [fm createFileAtPath:path contents:line attributes:@{ NSFilePosixPermissions: @0644 }];
            return;
        }
        // Past 128 KB, keep the newer half.
        if ([[fm attributesOfItemAtPath:path error:nil] fileSize] > 128 * 1024) {
            NSData *old = [NSData dataWithContentsOfFile:path];
            NSMutableData *kept = [[old subdataWithRange:NSMakeRange(old.length / 2, old.length - old.length / 2)] mutableCopy];
            [kept appendData:line];
            [kept writeToFile:path atomically:YES];
            [fm setAttributes:@{ NSFilePosixPermissions: @0644 } ofItemAtPath:path error:nil];
            return;
        }
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
        [handle seekToEndOfFile];
        [handle writeData:line];
        [handle closeFile];
    });
}

static NSTimer *SFTimer(NSTimeInterval seconds, id target, SEL action) {
    NSTimer *timer = [NSTimer timerWithTimeInterval:seconds target:target selector:action userInfo:nil repeats:NO];
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    return timer;
}

@interface SFDaemonListener ()
@property (nonatomic, copy) NSDictionary *settings;

// Schedule
@property (nonatomic, strong) NSTimer *runTimer;
/// Wall-clock twin of runTimer. NSTimer counts only awake time, so after the phone
/// sleeps through the planned time it would still think the run is minutes away.
@property (nonatomic, strong) dispatch_source_t runWallTimer;
@property (nonatomic, strong) NSDate *lastRunAt;
@property (nonatomic) BOOL onExternalPower;
@property (nonatomic, strong) NSDate *lastPlugInRun;

// Talking to the app
@property (nonatomic, strong) NSXPCConnection *connection;
@property (nonatomic) NSUInteger connectionGeneration;
@property (nonatomic, strong) NSMutableOrderedSet<NSNumber *> *waitingRequests;
@property (nonatomic, strong) NSTimer *launchRetryTimer;
@property (nonatomic) NSUInteger launchAttempts;
@property (nonatomic) BOOL retryAtUnlock;

// Keeping the app awake
@property (nonatomic, strong) BKSProcessAssertion *appAssertion;
@property (nonatomic) pid_t appAssertionPID;
@property (nonatomic) NSUInteger appAssertionGeneration;
@property (nonatomic, strong) NSTimer *keepAwakeLimitTimer;
@property (nonatomic) IOPMAssertionID powerAssertion;
@property (nonatomic, copy) NSString *activeRun;

// Phone state
@property (nonatomic) BOOL sawSpringBoardStart;
@property (nonatomic, strong) NSDate *lastPrewarm;
@end

@implementation SFDaemonListener {
    int _lockToken, _springBoardToken, _backlightToken, _settingsToken;
}

- (void)initialiseListener {
    SF_ON_MAIN([self initialiseListener]);
    self.waitingRequests = [NSMutableOrderedSet orderedSet];
    NSString *binary = [NSProcessInfo processInfo].arguments.firstObject;
    NSDate *built = [[NSFileManager defaultManager] attributesOfItemAtPath:binary error:nil].fileModificationDate;
    SFServiceLog(@"Background service started (installed %@)", built);
    [self listenForSystemEvents];
    [self listenForSleepAndWake];
    [self listenForPowerSource];
    [self reloadSettings];
    [self armFromStoredDate];
}

#pragma mark - Settings (the app's preferences, read as mobile)

- (void)reloadSettings {
    SFServiceLog(@"Reloading settings");
    CFPreferencesSynchronize(CFSTR(SF_APP_ID), CFSTR("mobile"), kCFPreferencesCurrentHost);
    CFArrayRef keys = CFPreferencesCopyKeyList(CFSTR(SF_APP_ID), CFSTR("mobile"), kCFPreferencesCurrentHost);
    if (!keys) { self.settings = @{}; return; }
    CFDictionaryRef values = CFPreferencesCopyMultiple(keys, CFSTR(SF_APP_ID), CFSTR("mobile"), kCFPreferencesCurrentHost);
    self.settings = values ? (__bridge NSDictionary *)values : @{};
    if (values) CFRelease(values);
    CFRelease(keys);
}

- (void)saveSetting:(NSString *)key value:(id)value {
    if (!key || !value) return;
    NSMutableDictionary *settings = [self.settings mutableCopy] ?: [NSMutableDictionary dictionary];
    settings[key] = value;
    self.settings = settings;
    CFPreferencesSetValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, CFSTR(SF_APP_ID), CFSTR("mobile"), kCFPreferencesCurrentHost);
    CFPreferencesSynchronize(CFSTR(SF_APP_ID), CFSTR("mobile"), kCFPreferencesCurrentHost);
}

- (NSInteger)integerSetting:(NSString *)key fallback:(NSInteger)fallback {
    id value = self.settings[key];
    return [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : fallback;
}

- (BOOL)boolSetting:(NSString *)key fallback:(BOOL)fallback {
    id value = self.settings[key];
    return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : fallback;
}

- (BOOL)autoSigningOn       { return [self boolSetting:@"sfAutoSign" fallback:YES]; }
- (BOOL)wakeForRunsOn       { return [self boolSetting:@"sfWakeForRuns" fallback:YES]; }
- (BOOL)signInLowPowerMode  { return [self boolSetting:@"sfSignInLowPower" fallback:NO]; }

#pragma mark - Schedule

/// Run times as minutes after midnight, sorted. Defaults to 3:00 AM.
- (NSArray<NSNumber *> *)runTimes {
    NSMutableOrderedSet *times = [NSMutableOrderedSet orderedSet];
    id stored = self.settings[@"sfScheduleTimes"];
    if ([stored isKindOfClass:[NSArray class]]) {
        for (id value in stored) {
            if (![value respondsToSelector:@selector(integerValue)]) continue;
            NSInteger minutes = [value integerValue];
            if (minutes >= 0 && minutes < 24 * 60) [times addObject:@(minutes)];
        }
    }
    if (times.count == 0) {
        NSInteger hour = MIN(MAX([self integerSetting:@"sfScheduleHour" fallback:3], 0), 23);
        NSInteger minute = MIN(MAX([self integerSetting:@"sfScheduleMinute" fallback:0], 0), 59);
        [times addObject:@(hour * 60 + minute)];
    }
    return [times.array sortedArrayUsingSelector:@selector(compare:)];
}

/// Weekday bits: bit 0 = Sunday … bit 6 = Saturday. 0 means every day.
- (NSInteger)runDays {
    NSInteger days = [self integerSetting:@"sfScheduleDays" fallback:127] & 127;
    return days ?: 127;
}

/// Identifies the current schedule, so a plan made for an older one can be spotted.
- (NSString *)scheduleSignature {
    return [NSString stringWithFormat:@"%@:%ld", [[self runTimes] componentsJoinedByString:@","], (long)[self integerSetting:@"sfScheduleDays" fallback:127]];
}

- (NSDate *)nextRunAfter:(NSDate *)date {
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDate *today = [calendar startOfDayForDate:date];
    NSInteger days = [self runDays];
    for (NSInteger offset = 0; offset <= 7; offset++) {
        NSDate *day = [calendar dateByAddingUnit:NSCalendarUnitDay value:offset toDate:today options:0];
        NSInteger weekday = [calendar component:NSCalendarUnitWeekday fromDate:day] - 1;
        if (!(days & (1 << weekday))) continue;
        for (NSNumber *time in [self runTimes]) {
            NSDate *candidate = [calendar dateBySettingHour:time.integerValue / 60 minute:time.integerValue % 60 second:0 ofDate:day options:0];
            if ([candidate timeIntervalSinceDate:date] > 30) return candidate;
        }
    }
    return [date dateByAddingTimeInterval:24 * 3600];
}

- (NSTimeInterval)secondsToNextRun {
    return MAX([[self nextRunAfter:[NSDate date]] timeIntervalSinceNow], 60);
}

/// At start: continue the stored plan if it's for the current schedule, otherwise plan anew.
- (void)armFromStoredDate {
    NSDate *stored = self.settings[@"nextFireDate"];
    NSString *plannedFor = self.settings[@"sfPlannedSchedule"];
    SFServiceLog(@"Got stored fire date: %@", stored);
    NSTimeInterval wait = [self secondsToNextRun];
    if ([stored isKindOfClass:[NSDate class]]) {
        if (plannedFor && ![plannedFor isEqualToString:[self scheduleSignature]]) {
            SFServiceLog(@"Schedule changed while the service was stopped; re-planning");
        } else {
            wait = stored.timeIntervalSinceNow;
            if (wait < 0) { SFServiceLog(@"The planned time passed while the service wasn't running"); wait = 5; }
        }
    }
    SFServiceLog(@"Starting signing timer, next fire in: %f minutes", wait / 60.0);
    [self armRunIn:wait];
}

- (void)rearmIn:(NSTimeInterval)seconds {
    SF_ON_MAIN([self rearmIn:seconds]);
    SFServiceLog(@"Restarting signing timer, next fire in: %f minutes", seconds / 60.0);
    [self armRunIn:seconds];
}

- (void)armRunIn:(NSTimeInterval)seconds {
    [self.runTimer invalidate];
    self.runTimer = SFTimer(MAX(seconds, 1), self, @selector(runTimerFired:));
    NSDate *when = self.runTimer.fireDate;
    [self armWallTimerIn:MAX(seconds, 1)];
    [self saveSetting:@"nextFireDate" value:when];
    [self saveSetting:@"sfPlannedSchedule" value:[self scheduleSignature]];

    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateFormat = @"EEE d MMM HH:mm";
    formatter.timeZone = [NSTimeZone localTimeZone];
    SFServiceLog(@"Next automatic run: %@", [formatter stringFromDate:when]);
    [self scheduleWakeFor:when];
}

- (void)armWallTimerIn:(NSTimeInterval)seconds {
    if (self.runWallTimer) dispatch_source_cancel(self.runWallTimer);
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, dispatch_walltime(NULL, (int64_t)(seconds * NSEC_PER_SEC)), DISPATCH_TIME_FOREVER, NSEC_PER_SEC);
    __weak SFDaemonListener *weakSelf = self;
    dispatch_source_set_event_handler(timer, ^{
        SFServiceLog(@"Wall-clock timer reached the planned time");
        [weakSelf runTimerFired:weakSelf.runTimer ?: (id)@"wall"];
    });
    dispatch_resume(timer);
    self.runWallTimer = timer;
}

- (void)disarm {
    [self.runTimer invalidate];
    self.runTimer = nil;
    if (self.runWallTimer) { dispatch_source_cancel(self.runWallTimer); self.runWallTimer = nil; }
    [self cancelWakes];
}

#pragma mark - Hardware wake

- (void)scheduleWakeFor:(NSDate *)runDate {
    [self cancelWakes];
    if (!runDate || ![self autoSigningOn] || ![self wakeForRunsOn]) return;

    // Wake just after the run time: woken earlier, the phone could fall asleep again
    // before the timer fires; woken after, the overdue timer fires at once.
    NSDate *wake = [runDate dateByAddingTimeInterval:3];
    if (wake.timeIntervalSinceNow < 1) wake = [NSDate dateWithTimeIntervalSinceNow:1];

    IOReturn result = IOPMSchedulePowerEvent((__bridge CFDateRef)wake, CFSTR(SF_SERVICE_ID), CFSTR(kIOPMAutoWakeOrPowerOn));
    if (result == kIOReturnSuccess) SFServiceLog(@"Successfully scheduled background wake for %@", wake);
    else SFServiceLog(@"Failed to schedule background wake: %s", mach_error_string(result));

    NSDictionary *request = @{
        @kIOPMPowerEventTimeKey: [wake dateByAddingTimeInterval:5],
        @kIOPMPowerEventAppNameKey: @SF_SERVICE_ID,
        @kIOPMPowerEventUserVisible: @YES,
    };
    result = IOPMRequestSysWake((__bridge CFDictionaryRef)request);
    if (result == kIOReturnSuccess) SFServiceLog(@"Successfully requested system wake for %@", wake);
    else SFServiceLog(@"Failed to request system wake: %s", mach_error_string(result));
}

- (void)cancelWakes {
    CFArrayRef events = IOPMCopyScheduledPowerEvents();
    if (!events) return;
    for (CFIndex i = 0; i < CFArrayGetCount(events); i++) {
        NSDictionary *event = (__bridge NSDictionary *)CFArrayGetValueAtIndex(events, i);
        if (![event[@kIOPMPowerEventAppNameKey] isEqual:@SF_SERVICE_ID]) continue;
        IOReturn result = IOPMCancelScheduledPowerEvent((__bridge CFDateRef)event[@kIOPMPowerEventTimeKey], CFSTR(SF_SERVICE_ID), (__bridge CFStringRef)event[@kIOPMPowerEventTypeKey]);
        if (result == kIOReturnSuccess) SFServiceLog(@"Success cancel scheduled power event(s)");
        else SFServiceLog(@"Error: %s", mach_error_string(result));
    }
    CFRelease(events);
}

#pragma mark - Run time

/// sender is nil when called because the screen came on after the planned time.
- (void)runTimerFired:(id)sender {
    SF_ON_MAIN([self runTimerFired:sender]);

    // The user may have moved the time since this run was planned: if so, re-plan instead.
    NSString *planned = [self scheduleSignature];
    [self reloadSettings];
    if (sender && ![planned isEqualToString:[self scheduleSignature]]) {
        NSDate *next = [self nextRunAfter:[NSDate dateWithTimeIntervalSinceNow:-120]];
        if (next.timeIntervalSinceNow > 60) {
            SFServiceLog(@"Schedule changed since this run was planned; re-planning");
            [self rearmIn:next.timeIntervalSinceNow];
            return;
        }
    }
    // The NSTimer, the wall-clock timer and a system wake can all notice the same run.
    if (self.lastRunAt && -self.lastRunAt.timeIntervalSinceNow < 90) { SFServiceLog(@"Run already started"); return; }
    self.lastRunAt = [NSDate date];
    SFServiceLog(@"Scheduled time reached");

    if ([NSProcessInfo processInfo].isLowPowerModeEnabled && ![self signInLowPowerMode]) {
        SFServiceLog(@"Signing skipped: Low Power Mode is on");
        [self rearmIn:[self secondsToNextRun]];
        return;
    }
    if (![self autoSigningOn]) {
        SFServiceLog(@"Signing skipped: automatic signing is off");
        [self disarm];
        return;
    }
    SFServiceLog(@"Signing timer fired: update now");
    [self askApp:SFAppRequestSign];
    [self rearmIn:[self secondsToNextRun]];
}

#pragma mark - Opening the app

- (void)askApp:(SFAppRequest)request {
    SF_ON_MAIN([self askApp:request]);
    NSArray *names = @[@"Starting new background signing routine.", @"Requesting application to check login credentials.", @"Requesting application to notify users of a queued update."];
    SFServiceLog(@"%@", names[request]);

    if (request == SFAppRequestSign || request == SFAppRequestSignPlugIn) [self keepPhoneAwake];   // a scheduled wake must not fall back asleep before the app connects
    int result = [self openAppInBackground];
    SFServiceLog(@"Opening Sevenfold in the background (%@)%@", result ? @"failed" : @"ok", self.connection ? @" · already connected" : @" · waiting for it to connect");
    if (result) SFServiceLog(@"Error launching application: %@", SBSApplicationLaunchingErrorString(result));

    if (!self.connection) { [self queueRequest:request]; return; }
    [self deliver:request toProxy:[self.connection remoteObjectProxyWithErrorHandler:^(NSError *error) { [self queueRequest:request]; }]];
}

- (void)deliver:(SFAppRequest)request toProxy:(id<SFApplicationProtocol>)app {
    switch (request) {
        case SFAppRequestSign:        [app daemonDidRequestNewBackgroundSigning]; break;
        case SFAppRequestSignPlugIn:  [app daemonDidRequestPlugInSigning]; break;
        case SFAppRequestCheckSignIn: [app daemonDidRequestCredentialsCheck]; break;
        case SFAppRequestShowQueued:  [app daemonDidRequestQueuedNotification]; break;
    }
}

- (void)queueRequest:(SFAppRequest)request {
    SF_ON_MAIN([self queueRequest:request]);
    SFServiceLog(@"Queuing notification %lu until connection is established", (unsigned long)request);
    [self.waitingRequests addObject:@(request)];
    [self scheduleLaunchRetry];
}

- (void)scheduleLaunchRetry {
    if (self.connection || self.launchRetryTimer) return;
    if (self.launchAttempts >= SFLaunchRetryLimit) {
        SFServiceLog(@"Background launch did not connect after %lu attempts; waiting for the next unlock", (unsigned long)self.launchAttempts);
        self.retryAtUnlock = YES;
        return;
    }
    NSTimeInterval delay = (NSTimeInterval)(1u << MIN(self.launchAttempts, (NSUInteger)3));
    self.launchAttempts++;
    self.launchRetryTimer = SFTimer(delay, self, @selector(launchRetryFired:));
    SFServiceLog(@"Retrying background application launch in %.0f second(s)", delay);
}

- (void)launchRetryFired:(NSTimer *)timer {
    self.launchRetryTimer = nil;
    if (self.connection) {
        self.launchAttempts = 0;
        [self applicationDidLaunch];
        return;
    }
    int result = [self openAppInBackground];
    if (result) SFServiceLog(@"Background application retry failed: %@", SBSApplicationLaunchingErrorString(result));
    if (!self.connection) [self scheduleLaunchRetry];
}

/// Opens Sevenfold without showing it (as a background fetch). 0 means success.
- (int)openAppInBackground {
    pid_t pid = [self appPID];
    if (pid) [self keepAppAwake];

    NSDictionary *options = @{ BKSOpenApplicationOptionKeyActivateForEvent: @{ BKSActivateForEventOptionTypeBackgroundContentFetching: @"" } };
    int result = SBSLaunchApplicationWithIdentifierAndLaunchOptions(CFSTR(SF_APP_ID), (__bridge CFDictionaryRef)options, YES);
    if (result != 0) result = SBSLaunchApplicationWithIdentifier(CFSTR(SF_APP_ID), YES);   // plain suspended launch
    SFServiceLog(@"Launched application with result: %d", result);
    if (result == 0 && !pid) [self keepAppAwake];
    return result;
}

- (pid_t)appPID {
    pid_t pid = 0;
    SBSProcessIDForDisplayIdentifier(CFSTR(SF_APP_ID), &pid);
    return pid;
}

#pragma mark - Keeping the app and phone awake

- (void)restartKeepAwakeLimit {
    [self.keepAwakeLimitTimer invalidate];
    self.keepAwakeLimitTimer = SFTimer(SFKeepAwakeLimit, self, @selector(keepAwakeLimitReached:));
}

- (void)keepAppAwake {
    pid_t pid = [self appPID];
    if (self.appAssertion && self.appAssertionPID != pid) [self letAppSleep];
    if (self.appAssertion) { [self restartKeepAwakeLimit]; return; }
    if (!pid) { SFServiceLog(@"Could not find application's PID, might be first launch."); return; }

    SFServiceLog(@"Aquiring background assertion");
    NSUInteger generation = ++self.appAssertionGeneration;
    self.appAssertionPID = pid;
    __weak SFDaemonListener *weakSelf = self;
    self.appAssertion = [[BKSProcessAssertion alloc] initWithPID:pid flags:(SFAssertionPreventSuspend | SFAssertionAllowIdleSleep) reason:SFAssertionReasonFinishTask name:@SF_APP_ID withHandler:^(BOOL success) {
        // The handler can run before the assignment above finishes, so look at it on the next turn.
        dispatch_async(dispatch_get_main_queue(), ^{
            SFDaemonListener *strongSelf = weakSelf;
            if (!strongSelf || strongSelf.appAssertionGeneration != generation) return;
            if (success) {
                SFServiceLog(@"Did aquire background assertion");
                [strongSelf restartKeepAwakeLimit];
            } else {
                SFServiceLog(@"Failed to aquire background assertion");
                [strongSelf letAppSleep];
            }
        });
    }];
}

- (void)keepPhoneAwake {
    if (self.powerAssertion != kIOPMNullAssertionID) return;
    // Stops idle sleep during a run without turning the screen on.
    NSDictionary *properties = @{
        (__bridge NSString *)kIOPMAssertionTypeKey: (__bridge NSString *)kIOPMAssertionTypePreventUserIdleSystemSleep,
        (__bridge NSString *)kIOPMAssertionNameKey: @"Sevenfold active signing",
        (__bridge NSString *)kIOPMAssertionLevelKey: @(kIOPMAssertionLevelOn),
        (__bridge NSString *)kIOPMAssertionTimeoutKey: @(SFKeepAwakeLimit),
        (__bridge NSString *)kIOPMAssertionTimeoutActionKey: (__bridge NSString *)kIOPMAssertionTimeoutActionTurnOff,
    };
    IOPMAssertionID assertion = kIOPMNullAssertionID;
    IOReturn result = IOPMAssertionCreateWithProperties((__bridge CFDictionaryRef)properties, &assertion);
    if (result == kIOReturnSuccess) self.powerAssertion = assertion;
    SFServiceLog(@"Signing power assertion result: %d", result);
}

- (void)keepAwakeLimitReached:(NSTimer *)timer {
    SFServiceLog(@"Background assertion fallback did fire.");
    self.activeRun = nil;
    [self letAppSleep];
}

- (void)letAppSleep {
    SFServiceLog(@"Releasing background assertion");
    self.appAssertionGeneration++;
    self.appAssertionPID = 0;
    if (self.powerAssertion != kIOPMNullAssertionID) {
        IOPMAssertionRelease(self.powerAssertion);
        self.powerAssertion = kIOPMNullAssertionID;
    }
    [self.keepAwakeLimitTimer invalidate];
    self.keepAwakeLimitTimer = nil;
    [self.appAssertion invalidate];
    self.appAssertion = nil;
}

#pragma mark - System events

- (void)listenForSystemEvents {
    __weak SFDaemonListener *weakSelf = self;
    dispatch_queue_t main = dispatch_get_main_queue();

    notify_register_dispatch("com.apple.springboard.lockstate", &_lockToken, main, ^(int token) {
        uint64_t locked = UINT64_MAX;
        notify_get_state(token, &locked);
        if (locked == 0) [weakSelf phoneUnlocked];
        else [weakSelf prewarmAppBecause:@"locked"];
    });
    notify_register_dispatch("SBSpringBoardDidLaunchNotification", &_springBoardToken, main, ^(int token) {
        [weakSelf springBoardStarted];
    });
    notify_register_dispatch("com.apple.backboardd.backlight.changed", &_backlightToken, main, ^(int token) {
        uint64_t level = UINT64_MAX;
        notify_get_state(token, &level);
        [weakSelf screenChanged:(int)level > 0];
    });
    // The app posts this after saving settings (works without an XPC connection).
    notify_register_dispatch("com.t4mag0.sevenfold.preferences-changed", &_settingsToken, main, ^(int token) {
        SFServiceLog(@"Settings changed in the app");
        [weakSelf applicationRequestsPreferencesUpdate];
    });
}

#pragma mark - System sleep and wake

static io_connect_t SFRootPort = MACH_PORT_NULL;
void IONotificationPortSetDispatchQueue(IONotificationPortRef notify, dispatch_queue_t queue);

static void SFPowerCallback(void *refcon, io_service_t service, natural_t messageType, void *messageArgument) {
    SFDaemonListener *listener = (__bridge SFDaemonListener *)refcon;
    switch (messageType) {
        case kIOMessageCanSystemSleep:
        case kIOMessageSystemWillSleep:
            IOAllowPowerChange(SFRootPort, (long)messageArgument);
            break;
        case kIOMessageSystemHasPoweredOn: {
            dispatch_async(dispatch_get_main_queue(), ^{ [listener systemWoke]; });
            break;
        }
        default: break;
    }
}

- (void)listenForSleepAndWake {
    IONotificationPortRef port = NULL;
    io_object_t notifier = 0;
    SFRootPort = IORegisterForSystemPower((__bridge void *)self, &port, SFPowerCallback, &notifier);
    if (SFRootPort == MACH_PORT_NULL) { SFServiceLog(@"Could not listen for system wake"); return; }
    IONotificationPortSetDispatchQueue(port, dispatch_get_main_queue());
}

/// Woken from sleep (by our scheduled wake or anything else): if the planned
/// time has passed, run now instead of waiting for the screen to turn on.
- (void)systemWoke {
    NSDate *planned = self.settings[@"nextFireDate"];
    if (![planned isKindOfClass:[NSDate class]]) return;
    NSTimeInterval left = planned.timeIntervalSinceNow;
    if (left <= 5) {
        SFServiceLog(@"System woke and the planned run is due (%.0f s), running now", left);
        [self runTimerFired:nil];
    } else if (left < 15 * 60) {
        [self armWallTimerIn:left];   // re-anchor to the wall clock
    }
}

#pragma mark - Plugged in

static BOOL SFIsOnExternalPower(void) {
    CFTypeRef info = IOPSCopyPowerSourcesInfo();
    if (!info) return NO;
    CFStringRef type = IOPSGetProvidingPowerSourceType(info);
    BOOL ac = type && CFStringCompare(type, CFSTR(kIOPSACPowerValue), 0) == kCFCompareEqualTo;
    CFRelease(info);
    return ac;
}

- (void)listenForPowerSource {
    self.onExternalPower = SFIsOnExternalPower();
    int token;
    __weak SFDaemonListener *weakSelf = self;
    notify_register_dispatch("com.apple.system.powersources.source", &token, dispatch_get_main_queue(), ^(int t) {
        [weakSelf powerSourceChanged];
    });
}

/// "Sign when plugged in": an extra chance to sign apps that are about to expire.
/// The app decides whether anything needs signing; at most once every 6 hours.
- (void)powerSourceChanged {
    BOOL ac = SFIsOnExternalPower();
    BOOL pluggedIn = ac && !self.onExternalPower;
    self.onExternalPower = ac;
    if (!pluggedIn) return;
    id setting = self.settings[@"sfSignOnPlugIn"];
    BOOL enabled = setting ? [setting boolValue] : YES;
    if (!enabled || ![self autoSigningOn]) return;
    if (self.lastPlugInRun && -self.lastPlugInRun.timeIntervalSinceNow < 6 * 3600) { SFServiceLog(@"Plugged in · checked less than 6 hours ago"); return; }
    if (self.activeRun) return;
    self.lastPlugInRun = [NSDate date];
    SFServiceLog(@"Plugged in · asking Sevenfold to sign apps that are about to expire");
    [self askApp:SFAppRequestSignPlugIn];
}

- (void)springBoardStarted {
    SFServiceLog(@"SpringBoard did start launching.");
    self.sawSpringBoardStart = YES;
}

/// Keeps Sevenfold resident (suspended, no assertion) so a run while the phone is
/// locked can resume it. Newer iOS refuses a cold background launch while locked,
/// but resuming an app that's already in memory works.
- (void)prewarmAppBecause:(NSString *)reason {
    if (![self autoSigningOn] || ![self wakeForRunsOn]) return;
    if (self.connection || [self appPID]) return;                       // already resident
    if (self.lastPrewarm && -self.lastPrewarm.timeIntervalSinceNow < 600) return;
    NSDate *planned = self.settings[@"nextFireDate"];
    if ([planned isKindOfClass:[NSDate class]] && planned.timeIntervalSinceNow > 36 * 3600) return;
    self.lastPrewarm = [NSDate date];
    int result = SBSLaunchApplicationWithIdentifier(CFSTR(SF_APP_ID), YES);   // suspended, invisible
    SFServiceLog(@"Keeping Sevenfold ready for the next run (%@): %@", reason, result ? (__bridge NSString *)SBSApplicationLaunchingErrorString(result) : @"ok");
}

- (void)phoneUnlocked {
    SFServiceLog(@"Device was unlocked.");
    [self prewarmAppBecause:@"unlocked"];

    // A run that couldn't reach the app while locked goes now.
    if (self.retryAtUnlock) {
        self.retryAtUnlock = NO;
        self.launchAttempts = 0;
        if (self.waitingRequests.count) {
            int result = [self openAppInBackground];
            if (result) SFServiceLog(@"Unlock retry failed to launch application: %@", SBSApplicationLaunchingErrorString(result));
            if (!self.connection) [self scheduleLaunchRetry];
        } else {
            [self askApp:SFAppRequestSign];
        }
        [self rearmIn:[self secondsToNextRun]];
    }

    // First unlock after a restart or respring: have the app check the saved sign-in.
    if (self.sawSpringBoardStart) {
        self.sawSpringBoardStart = NO;
        SFServiceLog(@"Checking credentials after reaching a sane point since SpringBoard launched.");
        [self askApp:SFAppRequestCheckSignIn];
    }
}

- (void)screenChanged:(BOOL)on {
    if (!on) {
        // The service stays alive while the screen is off, so the timer keeps running.
        SFServiceLog(@"Display turned off");
        [self prewarmAppBecause:@"display off"];
        SFServiceLog(@"Keeping signing timer armed while display is off");
        return;
    }
    SFServiceLog(@"Display turned on");
    // Timers can run late while the phone sleeps: check the plan against the clock.
    NSDate *planned = self.settings[@"nextFireDate"];
    NSTimeInterval left = [planned isKindOfClass:[NSDate class]] ? planned.timeIntervalSinceNow : 0;
    if (left <= 5) {
        SFServiceLog(@"Planned run is due (in %.0f s), running now", left);
        [self runTimerFired:nil];
    } else {
        SFServiceLog(@"Restarting signing timer due to wake, with interval: %f minutes", left / 60.0);
        [self rearmIn:left];
    }
}

#pragma mark - XPC

- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)connection {
    SFServiceLog(@"shouldAcceptNewConnection recieved.");
    connection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SFDaemonProtocol)];
    connection.exportedObject = self;
    connection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SFApplicationProtocol)];

    // Only the newest connection counts; handlers of older ones are ignored.
    __block NSUInteger generation = 0;
    dispatch_block_t adopt = ^{
        NSXPCConnection *previous = self.connection;
        self.connection = nil;
        self.connectionGeneration++;
        [previous invalidate];
        self.connection = connection;
        generation = ++self.connectionGeneration;
    };
    if ([NSThread isMainThread]) adopt(); else dispatch_sync(dispatch_get_main_queue(), adopt);

    __weak SFDaemonListener *weakSelf = self;
    connection.interruptionHandler = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            SFDaemonListener *strongSelf = weakSelf;
            if (!strongSelf || strongSelf.connectionGeneration != generation) return;
            SFServiceLog(@"XPC interruption handler called");
            NSXPCConnection *lost = strongSelf.connection;
            strongSelf.connection = nil;
            [lost invalidate];
        });
    };
    connection.invalidationHandler = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            SFDaemonListener *strongSelf = weakSelf;
            if (!strongSelf || strongSelf.connectionGeneration != generation) return;
            SFServiceLog(@"XPC invalidation handler called");
            strongSelf.connection = nil;
        });
    };
    [connection resume];
    return YES;
}

#pragma mark - Calls from the app

- (void)applicationDidLaunch {
    SF_ON_MAIN([self applicationDidLaunch]);
    [self.launchRetryTimer invalidate];
    self.launchRetryTimer = nil;
    self.launchAttempts = 0;

    if (self.waitingRequests.count == 0) {
        SFServiceLog(@"No pending notifications");
        if (!self.activeRun) [self letAppSleep];
        return;
    }
    SFServiceLog(@"Forwarding pending notifications");
    [self keepAppAwake];   // the app is registered now, so its PID is known
    for (NSNumber *request in self.waitingRequests) [self deliver:request.unsignedIntegerValue toProxy:self.connection.remoteObjectProxy];
    [self.waitingRequests removeAllObjects];
}

- (void)applicationDidFinishTask {
    SF_ON_MAIN([self applicationDidFinishTask]);
    SFServiceLog(@"applicationDidFinishTask recieved.");
    if (self.activeRun) { SFServiceLog(@"Keeping execution lease: signing is still active"); return; }
    [self letAppSleep];
}

- (void)applicationRequestsSigningAssertion {
    SF_ON_MAIN([self applicationRequestsSigningAssertion]);
    SFServiceLog(@"applicationRequestsSigningAssertion received.");
    [self keepAppAwake];
}

- (void)applicationRequestsSigningAssertionWithIdentifier:(NSString *)identifier {
    SF_ON_MAIN([self applicationRequestsSigningAssertionWithIdentifier:identifier]);
    if (![identifier isKindOfClass:[NSString class]] || identifier.length == 0 || identifier.length > 128) return;
    self.activeRun = identifier;
    [self keepAppAwake];
    if (self.appAssertion) [self keepPhoneAwake];
}

- (void)applicationDidFinishSigningWithIdentifier:(NSString *)identifier {
    SF_ON_MAIN([self applicationDidFinishSigningWithIdentifier:identifier]);
    if (!identifier || ![self.activeRun isEqual:identifier]) return;
    self.activeRun = nil;
    [self letAppSleep];
}

- (void)applicationRequestsDebuggingBackgroundSigning {
    SFServiceLog(@"applicationRequestsDebuggingBackgroundSigning recieved.");
    [self askApp:SFAppRequestSign];
}

- (void)applicationRequestsRetryAfter:(double)seconds {
    SF_ON_MAIN([self applicationRequestsRetryAfter:seconds]);
    NSTimeInterval wait = MIN(MAX(seconds, 60), 6 * 3600);
    SFServiceLog(@"Retry requested in %.0f minutes", wait / 60);
    [self rearmIn:wait];
}

- (void)applicationRequestsPreferencesUpdate {
    SF_ON_MAIN([self applicationRequestsPreferencesUpdate]);
    SFServiceLog(@"applicationRequestsPreferencesUpdate recieved.");

    NSString *oldSchedule = [self scheduleSignature];
    BOOL oldAuto = [self autoSigningOn], oldWake = [self wakeForRunsOn];
    [self reloadSettings];

    if (![self autoSigningOn]) { [self disarm]; return; }

    BOOL scheduleChanged = ![oldSchedule isEqualToString:[self scheduleSignature]];
    if (scheduleChanged || oldAuto != [self autoSigningOn] || oldWake != [self wakeForRunsOn]) {
        NSDate *stored = self.settings[@"nextFireDate"];
        NSTimeInterval left = [stored isKindOfClass:[NSDate class]] ? stored.timeIntervalSinceNow : 0;
        [self rearmIn:(scheduleChanged || left < 1) ? [self secondsToNextRun] : left];
    } else if (!self.runTimer) {
        [self rearmIn:[self secondsToNextRun]];
    }
}

@end
