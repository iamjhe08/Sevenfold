//
//  SFSigningSession.m
//  Sevenfold
//

#import "SFSigningSession.h"
#import "SFLocalization.h"
#import "SFSettings.h"
#import "SFLog.h"
#import "SFCertificateStore.h"
#import "SFHistory.h"
#import "SFPopup.h"
#import "SFTheme.h"
#import "SFSigningViewController.h"
#import "SFApplication.h"
#import "SFApplicationDatabase.h"
#import "SFNotificationManager.h"
#import "SFResources.h"
#import "SFErrors.h"
#import "AppDelegate.h"

NSString *const SFSigningSessionDidChangeNotification = @"com.t4mag0.sevenfold/signingChanged";

@implementation SFSigningItem

- (NSString *)stepText {
    switch (self.state) {
        case SFSigningItemWaiting: return SFL(@"Next in line");
        case SFSigningItemDone: return SFL(@"Installed · valid 7 days");
        case SFSigningItemFailed: return self.errorMessage.length > 0 ? self.errorMessage : SFL(@"Failed");
        case SFSigningItemActive:
            if (self.progress < 30) return SFL(@"Preparing…");
            if (self.progress < 50) return SFL(@"Getting profile and signing…");
            if (self.progress < 60) return SFL(@"Packaging…");
            return SFL(@"Installing…");
    }
    return @"";
}

@end

@interface SFSigningSession ()
@property (nonatomic, readwrite) BOOL running;
@property (nonatomic, readwrite) BOOL finished;
@property (nonatomic, readwrite) BOOL automatic;
@property (nonatomic, readwrite) BOOL nextRunAutomatic;
@property (nonatomic, readwrite, nullable) NSDate *startDate;
@property (nonatomic, readwrite, nullable) NSDate *endDate;
@property (nonatomic, strong) NSMutableArray<SFSigningItem *> *mutableItems;
@property (nonatomic, readwrite, nullable) NSString *runError;
@property (nonatomic, readwrite) BOOL stopRequested;
@end

@implementation SFSigningSession

+ (instancetype)shared {
    static SFSigningSession *session;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        session = [SFSigningSession new];
        [[SFApplicationSigning sharedInstance] addSigningUpdatesObserver:session];
    });
    return session;
}

- (instancetype)init {
    self = [super init];
    if (self) _mutableItems = [NSMutableArray array];
    return self;
}

- (NSArray<SFSigningItem *> *)items {
    @synchronized (self) { return [self.mutableItems copy]; }
}

- (void)post {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SFSigningSessionDidChangeNotification object:self];
    });
}

- (SFSigningItem *)itemFor:(NSString *)bundleIdentifier create:(BOOL)create {
    @synchronized (self) {
        for (SFSigningItem *item in self.mutableItems)
            if ([item.bundleIdentifier isEqualToString:bundleIdentifier]) return item;
        // Signed apps get ".TEAMID" added; match on prefix too.
        for (SFSigningItem *item in self.mutableItems)
            if ([bundleIdentifier hasPrefix:[item.bundleIdentifier stringByAppendingString:@"."]] ||
                [item.bundleIdentifier hasPrefix:[bundleIdentifier stringByAppendingString:@"."]]) return item;
        if (!create || bundleIdentifier.length == 0) return nil;
        SFSigningItem *item = [SFSigningItem new];
        item.bundleIdentifier = bundleIdentifier;
        SFApplication *app = [[SFApplicationDatabase sharedInstance] getApplicationContainsBundleIdentifier:bundleIdentifier];
        item.name = app.applicationName ?: bundleIdentifier;
        item.icon = app.applicationIcon;
        [self.mutableItems addObject:item];
        return item;
    }
}

- (void)prepareWithApplications:(NSArray *)applications automatic:(BOOL)automatic {
    @synchronized (self) {
        [self.mutableItems removeAllObjects];
        for (SFApplication *app in applications) {
            SFSigningItem *item = [SFSigningItem new];
            item.bundleIdentifier = app.bundleIdentifier ?: @"";
            item.name = app.applicationName ?: item.bundleIdentifier;
            item.icon = app.applicationIcon;
            [self.mutableItems addObject:item];
        }
    }
    self.automatic = automatic;
    self.finished = NO;
    self.runError = nil;
    self.endDate = nil;
    self.stopRequested = NO;
    [self post];
}

- (void)markNextRunAutomatic {
    self.nextRunAutomatic = YES;
}

- (void)requestStopAfterCurrent {
    self.stopRequested = YES;
    [[SFApplicationSigning sharedInstance] requestStopAfterCurrentApplication];
    SFLogEvent(SFLogLevelInfo, @"stop requested after current app");
    [self post];
}

- (float)overallProgress {
    NSArray *items = self.items;
    if (items.count == 0) return self.finished ? 1.0 : 0.0;
    float total = 0;
    for (SFSigningItem *item in items)
        total += (item.state == SFSigningItemDone || item.state == SFSigningItemFailed) ? 100 : item.progress;
    return total / (100.0 * items.count);
}

- (NSUInteger)doneCount {
    NSUInteger count = 0;
    for (SFSigningItem *item in self.items) if (item.state == SFSigningItemDone) count++;
    return count;
}

- (NSUInteger)failedCount {
    NSUInteger count = 0;
    for (SFSigningItem *item in self.items) if (item.state == SFSigningItemFailed) count++;
    return count;
}

- (SFSigningItem *)activeItem {
    for (SFSigningItem *item in self.items) if (item.state == SFSigningItemActive) return item;
    return nil;
}

- (BOOL)signAllNow {
    NSString *teamID = [SFResources getTeamID];
    NSArray *apps = [[SFApplicationDatabase sharedInstance] getAllApplicationsForTeamID:teamID];
    return [self signApplications:apps];
}

- (BOOL)signApplications:(NSArray *)applications {
    if (self.running || ![SFSettings isSignedIn] || applications.count == 0) return NO;
    [self prepareWithApplications:applications automatic:NO];
    [[SFApplicationSigning sharedInstance] signSpecificApplications:applications
                                                            withTeamID:[SFResources getTeamID]
                                                              username:[SFResources getUsername]
                                                              password:[SFResources getPassword]];
    return YES;
}

// MARK: - SFApplicationSigningProtocol

- (void)applicationSigningDidStart {
    if (self.running) return;
    self.running = YES;
    self.finished = NO;
    self.startDate = [NSDate date];
    self.endDate = nil;
    self.runError = nil;
    if (self.nextRunAutomatic) {
        self.automatic = YES;
        self.nextRunAutomatic = NO;
    }
    SFLogEvent(SFLogLevelInfo, @"%@ run started", self.automatic ? @"automatic" : @"manual");
    [self post];
}

- (void)applicationSigningUpdateProgress:(int)progress forBundleIdentifier:(NSString *)bundleIdentifier {
    SFSigningItem *item = [self itemFor:bundleIdentifier create:YES];
    if (!item) return;
    item.progress = progress;
    if (progress >= 100) {
        item.state = SFSigningItemDone;
        NSTimeInterval seconds = self.startDate ? -[self.startDate timeIntervalSinceNow] : 0;
        SFLogEvent(SFLogLevelOK, @"signed %@ · %.1fs into run", item.name, seconds);
    } else if (progress > 0 || item.state == SFSigningItemWaiting) {
        if (progress > 0) item.state = SFSigningItemActive;
    }
    [self post];
}

- (void)applicationSigningDidEncounterError:(NSError *)error forBundleIdentifier:(NSString *)bundleIdentifier {
    SFSigningItem *item = [self itemFor:bundleIdentifier create:YES];
    item.state = SFSigningItemFailed;
    item.progress = 100;
    item.errorMessage = [self shortReason:error];
    item.fullError = error.localizedDescription;
    SFLogEvent(SFLogLevelError, @"failed %@ · %@", item.name ?: bundleIdentifier, error.localizedDescription ?: @"unknown error");
    [self post];
}

- (void)applicationSigningCompleteWithError:(NSError *)error {
    if (error.code == SFErrorAlreadyUndertakingPipeline) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self finishWithError:error];
    });
}

// MARK: - End of run

- (NSString *)shortReason:(NSError *)error {
    NSString *text = error.localizedDescription ?: SFL(@"Unknown error");
    NSString *lower = text.lowercaseString;
    if ([lower containsString:@"anisette"]) return @"Couldn't reach a sign-in server";
    if ([lower containsString:@"internet"] || [lower containsString:@"offline"] || [lower containsString:@"network"]) return @"No internet connection";
    if ([lower containsString:@"maximum number"] || [lower containsString:@"app id"]) return @"App ID limit reached (10 per week)";
    if ([lower containsString:@"entitlement"]) return @"Unsupported app capability";
    if (([lower containsString:@"certificate"] && ([lower containsString:@"maximum"] || [lower containsString:@"limit"] || [lower containsString:@"already have"] || [lower containsString:@"pending"])))
        return SFL(@"Certificate limit reached · tap for details");
    if ([lower containsString:@"certificate"]) return @"Certificate problem · tap for details";
    if ([lower containsString:@"password"] || [lower containsString:@"credential"] || [lower containsString:@"session"]) return @"Apple ID sign-in needed";
    NSString *firstLine = [[text componentsSeparatedByString:@"\n"] firstObject];
    return firstLine.length > 80 ? [[firstLine substringToIndex:77] stringByAppendingString:@"…"] : firstLine;
}

- (void)finishWithError:(NSError *)error {
    BOOL nothingToDo = error.code == SFErrorNoSigningRequired;
    self.running = NO;
    self.finished = YES;
    self.endDate = [NSDate date];
    NSTimeInterval seconds = self.startDate ? [self.endDate timeIntervalSinceDate:self.startDate] : 0;

    // Anything still marked active/waiting with no error was stopped early.
    for (SFSigningItem *item in self.items) {
        if (item.state == SFSigningItemActive || item.state == SFSigningItemWaiting) {
            if (self.stopRequested) {
                item.state = SFSigningItemFailed;
                item.errorMessage = SFL(@"Skipped (stopped)");
            } else if (error && !nothingToDo) {
                item.state = SFSigningItemFailed;
                item.errorMessage = [self shortReason:error];
                item.fullError = error.localizedDescription;
            }
        }
    }

    NSUInteger signedCount = self.doneCount;
    NSUInteger failed = self.failedCount;
    if (error && !nothingToDo && signedCount == 0) self.runError = [self shortReason:error];

    NSMutableArray *failedNames = [NSMutableArray array];
    for (SFSigningItem *item in self.items) if (item.state == SFSigningItemFailed) [failedNames addObject:item.name ?: item.bundleIdentifier];

    [SFSettings setLastRun:@{
        @"date": self.endDate,
        @"signed": @(signedCount),
        @"failed": @(failed),
        @"automatic": @(self.automatic),
        @"seconds": @(seconds),
        @"message": nothingToDo ? SFL(@"No apps needed signing") : (self.runError ?: (failed ? [NSString stringWithFormat:SFL(@"%lu failed"), (unsigned long)failed] : SFL(@"OK"))),
    }];
    SFLogEvent(failed || self.runError ? SFLogLevelWarning : SFLogLevelOK, @"run finished · %lu signed · %lu failed · %.1fs%@",
               (unsigned long)signedCount, (unsigned long)failed, seconds, nothingToDo ? @" · nothing due" : @"");

    // Save to History.
    NSMutableArray *appRecords = [NSMutableArray array];
    for (SFSigningItem *item in self.items) {
        BOOL ok = item.state == SFSigningItemDone;
        NSMutableDictionary *record = [@{ @"name": item.name ?: item.bundleIdentifier ?: @"App",
                                          @"bundleIdentifier": item.bundleIdentifier ?: @"",
                                          @"ok": @(ok) } mutableCopy];
        if (!ok && item.errorMessage) record[@"reason"] = item.errorMessage;
        if (!ok && item.fullError) record[@"error"] = item.fullError;
        [appRecords addObject:record];
    }
    NSMutableDictionary *run = [@{ @"date": self.endDate, @"automatic": @(self.automatic), @"seconds": @(seconds),
                                   @"signed": @(signedCount), @"failed": @(failed), @"nothingToDo": @(nothingToDo),
                                   @"apps": appRecords } mutableCopy];
    if (self.runError) run[@"reason"] = self.runError;
    if (error && !nothingToDo && error.localizedDescription) run[@"error"] = error.localizedDescription;
    [SFHistory addRun:run];

    if (signedCount > 0) [SFCertificateStore recordThisDeviceUsesActiveCertificate];

    [self sendNotificationsSignedCount:signedCount failedNames:failedNames nothingToDo:nothingToDo];
    [self handleRetryWithFailure:(failed > 0 || self.runError != nil) && !nothingToDo];

    self.stopRequested = NO;
    [self post];
}

- (void)sendNotificationsSignedCount:(NSUInteger)signedCount failedNames:(NSArray *)failedNames nothingToDo:(BOOL)nothingToDo {
    // While the app is open the progress screen already shows the result.
    BOOL appVisible = [UIApplication sharedApplication].applicationState == UIApplicationStateActive;
    SFNotificationManager *notifier = [SFNotificationManager sharedInstance];

    if (appVisible && [SFSettings showInAppPopups] && ![self signingScreenVisible]) {
        if (nothingToDo) {
            [SFPopup showWithTitle:SFL(@"Nothing to sign") subtitle:SFL(@"All your apps are up to date.") style:SFPopupStyleInfo];
        } else if (signedCount > 0 && failedNames.count == 0) {
            NSArray<SFSigningItem *> *items = self.items;
            NSString *title = signedCount == 1 && items.count == 1 ? [NSString stringWithFormat:SFL(@"Signed %@"), items.firstObject.name]
                                                                   : [NSString stringWithFormat:SFL(@"Signed %lu apps"), (unsigned long)signedCount];
            NSString *subtitle = SFL(@"Signed just now");
            if (items.count == 1) {
                SFApplication *app = [[SFApplicationDatabase sharedInstance] getApplicationWithBundleIdentifier:items.firstObject.bundleIdentifier];
                // A fresh profile reads 6 days 23 hrs; show it as the full 7 days.
                NSTimeInterval left = [app.applicationExpiryDate timeIntervalSinceNow];
                if (app && left > 6 * 24 * 3600) subtitle = SFL(@"Valid for 7 days");
                else if (app) subtitle = [NSString stringWithFormat:SFL(@"%@ left"), [SFTheme relativeExpiry:app.applicationExpiryDate]];
            }
            UIImage *icon = items.count == 1 ? items.firstObject.icon : nil;
            [SFPopup showWithTitle:title subtitle:subtitle style:SFPopupStyleSuccess icon:icon retry:nil];
        } else {
            NSString *title = failedNames.count == 1 ? [NSString stringWithFormat:SFL(@"Couldn't sign %@"), failedNames.firstObject]
                                                     : [NSString stringWithFormat:SFL(@"%lu apps failed"), (unsigned long)MAX(failedNames.count, (NSUInteger)1)];
            SFSigningItem *firstFailed = nil;
            for (SFSigningItem *item in self.items) if (item.state == SFSigningItemFailed) { firstFailed = item; break; }
            // Retry signs the apps that failed.
            NSMutableArray *retryApps = [NSMutableArray array];
            for (SFSigningItem *item in self.items) {
                if (item.state != SFSigningItemFailed) continue;
                SFApplication *app = [[SFApplicationDatabase sharedInstance] getApplicationWithBundleIdentifier:item.bundleIdentifier];
                if (app) [retryApps addObject:app];
            }
            [SFPopup showWithTitle:title subtitle:firstFailed.errorMessage ?: self.runError style:SFPopupStyleFailure
                              icon:failedNames.count == 1 ? firstFailed.icon : nil
                             retry:^{ if (retryApps.count) [self signApplications:retryApps]; else [self signAllNow]; }];
        }
    }

    if (!appVisible && signedCount > 0 && [SFSettings notifyOnSuccess]) {
        NSDateFormatter *formatter = [NSDateFormatter new];
        formatter.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"MMM d" options:0 locale:[NSLocale currentLocale]];
        NSString *until = [formatter stringFromDate:[NSDate dateWithTimeIntervalSinceNow:7 * 24 * 3600]];
        NSString *title = signedCount == 1 ? SFL(@"Signed 1 app") : [NSString stringWithFormat:SFL(@"Signed %lu apps"), (unsigned long)signedCount];
        [notifier sendSevenfoldNotificationWithTitle:title body:[NSString stringWithFormat:SFL(@"Valid until %@."), until] identifier:@"sf.success"];
    }

    if (!appVisible && (failedNames.count > 0 || self.runError) && [SFSettings notifyOnFailure]) {
        NSString *title;
        NSString *body;
        if (self.runError && signedCount == 0) {
            title = SFL(@"Signing failed");
            body = [NSString stringWithFormat:SFL(@"%@. Tap to open Sevenfold and retry."), self.runError];
        } else {
            title = failedNames.count == 1 ? [NSString stringWithFormat:SFL(@"Couldn't sign %@"), failedNames.firstObject]
                                           : [NSString stringWithFormat:SFL(@"Couldn't sign %lu apps"), (unsigned long)failedNames.count];
            SFSigningItem *firstFailed = nil;
            for (SFSigningItem *item in self.items) if (item.state == SFSigningItemFailed) { firstFailed = item; break; }
            body = [NSString stringWithFormat:SFL(@"%@. Tap to retry."), firstFailed.errorMessage ?: SFL(@"Something went wrong")];
        }
        [notifier sendSevenfoldNotificationWithTitle:title body:body identifier:@"sf.failure"];
    }

    if ([SFSettings notifyOnExpiry] && (failedNames.count > 0 || self.runError || nothingToDo)) {
        [self.class sendExpiryWarningIfNeeded];
    }
}

+ (void)sendExpiryWarningIfNeeded {
    if (![SFSettings notifyOnExpiry] || ![SFSettings isSignedIn]) return;
    NSMutableArray *soon = [NSMutableArray array];
    [[SFApplicationDatabase sharedInstance] getApplicationsWithExpiryDateBefore:&soon andAfter:nil
                                                                            date:[NSDate dateWithTimeIntervalSinceNow:24 * 3600]
                                                                       forTeamID:[SFResources getTeamID]];
    if (soon.count == 0) return;
    SFApplication *first = soon.firstObject;
    NSString *title = soon.count == 1 ? [NSString stringWithFormat:SFL(@"%@ expires soon"), first.applicationName]
                                      : [NSString stringWithFormat:SFL(@"%lu apps expire soon"), (unsigned long)soon.count];
    [[SFNotificationManager sharedInstance] sendSevenfoldNotificationWithTitle:title
                                                                           body:SFL(@"Less than a day left. Open Sevenfold to sign now.")
                                                                     identifier:@"sf.expiry"];
}

- (BOOL)signingScreenVisible {
    UIViewController *top = [UIApplication sharedApplication].windows.firstObject.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    if ([top isKindOfClass:[UINavigationController class]]) top = [(UINavigationController *)top topViewController];
    return [top isKindOfClass:[SFSigningViewController class]];
}

- (void)handleRetryWithFailure:(BOOL)failure {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (!self.automatic || !failure) {
        [defaults setInteger:0 forKey:@"sfRetryCount"];
        self.automatic = NO;
        return;
    }
    NSInteger count = [defaults integerForKey:@"sfRetryCount"];
    if ([SFSettings retryOnFailure] && count < 3) {
        [defaults setInteger:count + 1 forKey:@"sfRetryCount"];
        SFLogEvent(SFLogLevelInfo, @"retry %ld of 3 in 30 min", (long)count + 1);
        [(AppDelegate *)[UIApplication sharedApplication].delegate requestRetryAfter:30 * 60];
    } else {
        [defaults setInteger:0 forKey:@"sfRetryCount"];
    }
    self.automatic = NO;
}

@end
