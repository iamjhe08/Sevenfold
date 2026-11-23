//
//  SFApplicationSigning.m
//  Sevenfold
//
//  Sevenfold · BY: T4MAG0
//

#import "SFApplicationSigning.h"
#import "SFLocalization.h"
#import "SFBackend.h"
#import "SFApplication.h"
#import "SFApplicationDatabase.h"
#import "SSZipArchive.h"
#import "SFLog.h"
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <objc/message.h>

// MARK: - Installing (private iOS installers, looked up at runtime)

static BOOL SFIsIOS26OrLater(void) {
    return [[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){26, 0, 0}];
}

static id SFLegacyWorkspace(void) {
    Class cls = NSClassFromString(@"LSApplicationWorkspace");
    SEL sel = NSSelectorFromString(@"defaultWorkspace");
    if (![cls respondsToSelector:sel]) return nil;
    id (*call)(id, SEL) = (void *)objc_msgSend;
    return call(cls, sel);
}

static void SFInstallIPANow(NSURL *ipa, NSString *bundleID, void (^done)(BOOL ok, NSError *error));

/// Installs an .ipa, one at a time (iOS installs apps one after another anyway).
static void SFInstallIPA(NSURL *ipa, NSString *bundleID, void (^done)(BOOL ok, NSError *error)) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("com.t4mag0.sevenfold.install", DISPATCH_QUEUE_SERIAL); });
    dispatch_async(queue, ^{
        dispatch_semaphore_t finished = dispatch_semaphore_create(0);
        SFInstallIPANow(ipa, bundleID, ^(BOOL ok, NSError *error) {
            done(ok, error);
            dispatch_semaphore_signal(finished);
        });
        // Wait for this install before starting the next (at most 3 minutes).
        dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW, 180 * NSEC_PER_SEC));
    });
}

/// iOS 26 uses InstallCoordination; older iOS uses LaunchServices.
static void SFInstallIPANow(NSURL *ipa, NSString *bundleID, void (^done)(BOOL ok, NSError *error)) {
    if (SFIsIOS26OrLater()) {
        dlopen("/System/Library/PrivateFrameworks/MobileInstallation.framework/MobileInstallation", RTLD_NOW);
        dlopen("/System/Library/PrivateFrameworks/InstallCoordination.framework/InstallCoordination", RTLD_NOW);
        Class optionsClass = NSClassFromString(@"MIInstallOptions");
        Class coordinator = NSClassFromString(@"IXAppInstallCoordinator");
        SEL install = NSSelectorFromString(@"installApplication:options:completion:");
        if (!optionsClass || ![coordinator respondsToSelector:install]) {
            done(NO, [NSError errorWithDomain:@"Sevenfold.Install" code:SFErrorFailedToInstallSignedIPA
                                     userInfo:@{ NSLocalizedDescriptionKey: SFL(@"The iOS 26 installer isn't available on this iPhone.") }]);
            return;
        }
        id options = [optionsClass new];
        // user app, allow free-account (locally provisioned) profiles, developer install
        @try {
            [options setValue:@1 forKey:@"installTargetType"];
            [options setValue:@YES forKey:@"allowLocalProvisioned"];
            [options setValue:@YES forKey:@"developerInstall"];
            [options setValue:@YES forKey:@"userInitiated"];
            [options setValue:bundleID forKey:@"bundleIdentifier"];
        } @catch (NSException *e) {}
        void (*call)(id, SEL, NSURL *, id, void (^)(id, NSError *)) = (void *)objc_msgSend;
        call(coordinator, install, ipa, options, ^(id identity, NSError *error) { done(error == nil, error); });
        return;
    }
    id workspace = SFLegacyWorkspace();
    SEL install = NSSelectorFromString(@"installApplication:withOptions:error:");
    if (![workspace respondsToSelector:install]) {
        done(NO, [NSError errorWithDomain:@"Sevenfold.Install" code:SFErrorFailedToInstallSignedIPA
                                 userInfo:@{ NSLocalizedDescriptionKey: SFL(@"The iOS installer isn't available on this iPhone.") }]);
        return;
    }
    NSError *error = nil;
    BOOL ok = NO;
    @try {
        BOOL (*call)(id, SEL, NSURL *, NSDictionary *, NSError **) = (void *)objc_msgSend;
        ok = call(workspace, install, ipa, @{ @"CFBundleIdentifier": bundleID, @"AllowInstallLocalProvisioned": @YES }, &error);
    } @catch (NSException *exception) {
        error = [NSError errorWithDomain:@"Sevenfold.Install" code:SFErrorFailedToInstallSignedIPA
                                userInfo:@{ NSLocalizedDescriptionKey: exception.reason ?: SFL(@"The installer stopped unexpectedly.") }];
    }
    done(ok, error);
}

static BOOL SFUninstall(NSString *bundleID, NSError **error) {
    if (bundleID.length == 0) return NO;
    if (SFIsIOS26OrLater()) {
        Class coordinator = NSClassFromString(@"IXAppInstallCoordinator");
        SEL remove = NSSelectorFromString(@"uninstallAppWithBundleID:error:");
        if ([coordinator respondsToSelector:remove]) {
            BOOL (*call)(id, SEL, NSString *, NSError **) = (void *)objc_msgSend;
            return call(coordinator, remove, bundleID, error);
        }
    }
    id workspace = SFLegacyWorkspace();
    SEL remove = NSSelectorFromString(@"uninstallApplication:withOptions:");
    if (![workspace respondsToSelector:remove]) return NO;
    BOOL (*call)(id, SEL, NSString *, NSDictionary *) = (void *)objc_msgSend;
    return call(workspace, remove, bundleID, nil);
}

/// Turns an installer error into a message that says what to do.
static NSString *SFInstallerMessage(NSError *error, NSString *original, NSString *signedID) {
    NSString *reason = error.localizedDescription.length ? error.localizedDescription : SFL(@"iOS refused the signed app without saying why.");
    NSString *detail = [NSString stringWithFormat:@"Installer: %@ (%@, code %ld)", reason, error.domain ?: @"unknown", (long)error.code];
    NSString *message;
    if ([reason localizedCaseInsensitiveContainsString:@"invalid entitlements"])
        message = SFL(@"This app asks for a capability a free Apple ID can't grant, so iOS refused it.");
    else if ([reason localizedCaseInsensitiveContainsString:@"valid provisioning profile"])
        message = SFL(@"The app's profile isn't valid for this iPhone. Sign out and back in, then sign it again.");
    else if (error.code == 13)
        message = SFL(@"Your Apple ID already has the most sideloaded apps it can have active (3 on a free account).");
    else
        message = reason;
    NSMutableString *text = [NSMutableString stringWithFormat:@"%@\n\n%@", message, detail];
    if (signedID.length && ![original isEqualToString:signedID])
        [text appendFormat:@"\nOriginal bundle ID: %@\nSigned bundle ID: %@", original, signedID];
    return text;
}

// MARK: - Pipeline

@interface SFApplicationSigning ()
@property (nonatomic, strong) NSMutableArray<id<SFApplicationSigningProtocol>> *observers;
@property (nonatomic, strong) NSMutableArray *queue;           // apps not started yet
@property (nonatomic) NSUInteger active;                       // apps being signed right now
@property (nonatomic) NSUInteger maxAtOnce;                    // 3, or 1 (setting off, or Apple asked us to slow down)
@property (nonatomic, strong) NSError *lastError;
@property (nonatomic, strong) NSMutableSet *retried;           // bundle IDs already retried after a rate limit
@property (atomic) BOOL running;
@property (atomic) BOOL stopAfterCurrent;
@property (nonatomic) UIBackgroundTaskIdentifier backgroundTask;
@property (nonatomic, copy) NSString *teamID;
@property (nonatomic, copy) NSString *username;
@property (nonatomic, copy) NSString *password;
@end

@implementation SFApplicationSigning

+ (instancetype)sharedInstance {
    static SFApplicationSigning *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [self new]; });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _observers = [NSMutableArray array];
        _backgroundTask = UIBackgroundTaskInvalid;
    }
    return self;
}

- (void)addSigningUpdatesObserver:(id<SFApplicationSigningProtocol>)observer {
    @synchronized (self.observers) { if (observer && ![self.observers containsObject:observer]) [self.observers addObject:observer]; }
}

- (void)removeSigningUpdatesObserver:(id<SFApplicationSigningProtocol>)observer {
    @synchronized (self.observers) { [self.observers removeObject:observer]; }
}

/// Newest observer first, on a snapshot (observers may change while we notify).
- (void)notify:(void (^)(id<SFApplicationSigningProtocol> observer))block {
    NSArray *snapshot;
    @synchronized (self.observers) { snapshot = [[self.observers reverseObjectEnumerator] allObjects]; }
    for (id<SFApplicationSigningProtocol> observer in snapshot) block(observer);
}

- (void)progress:(int)percent for:(NSString *)bundleID {
    [self notify:^(id<SFApplicationSigningProtocol> o) { [o applicationSigningUpdateProgress:percent forBundleIdentifier:bundleID]; }];
}

- (NSError *)errorWithText:(NSString *)text code:(NSInteger)code {
    return [NSError errorWithDomain:@"Sevenfold.Signing" code:code userInfo:@{ NSLocalizedDescriptionKey: text ?: SFL(@"Signing failed.") }];
}

// MARK: Starting

- (void)signApplications:(BOOL)onlyExpiringApplications thresholdForExpiration:(int)thresholdForExpiration withTeamID:(NSString *)teamID username:(NSString *)username password:(NSString *)password {
    SFApplicationDatabase *database = [SFApplicationDatabase sharedInstance];
    NSMutableArray *apps = [NSMutableArray array];
    if (onlyExpiringApplications) {
        NSDate *cutoff = [NSDate dateWithTimeIntervalSinceNow:(NSTimeInterval)thresholdForExpiration * 24 * 3600];
        [database getApplicationsWithExpiryDateBefore:&apps andAfter:NULL date:cutoff forTeamID:teamID];
    } else {
        [apps addObjectsFromArray:[database getAllApplicationsForTeamID:teamID]];
    }
    // Skip apps the user turned off for automatic signing.
    NSArray *excluded = [[NSUserDefaults standardUserDefaults] arrayForKey:@"sfExcluded"];
    if (excluded.count) {
        NSIndexSet *skip = [apps indexesOfObjectsPassingTest:^BOOL(SFApplication *app, NSUInteger i, BOOL *stop) {
            return [excluded containsObject:app.bundleIdentifier];
        }];
        [apps removeObjectsAtIndexes:skip];
    }
    // Look each app up again right now: one removed since the list was read is skipped, not reinstalled.
    NSMutableArray *stillInstalled = [NSMutableArray array];
    for (SFApplication *app in apps) {
        SFApplication *fresh = [database getApplicationWithBundleIdentifier:app.bundleIdentifier];
        if (fresh) [stillInstalled addObject:fresh];
        else SFLogEvent(SFLogLevelInfo, @"skipped %@ · no longer installed", app.applicationName ?: app.bundleIdentifier);
    }
    [self startWithApplications:stillInstalled teamID:teamID username:username password:password];
}

- (void)signSpecificApplications:(NSArray *)applications withTeamID:(NSString *)teamID username:(NSString *)username password:(NSString *)password {
    [self startWithApplications:applications teamID:teamID username:username password:password];
}

- (void)startWithApplications:(NSArray *)applications teamID:(NSString *)teamID username:(NSString *)username password:(NSString *)password {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [self notify:^(id<SFApplicationSigningProtocol> o) { [o applicationSigningDidStart]; }];
        @synchronized (self) {
            if (self.running) {
                NSError *busy = [self errorWithText:SFL(@"Sevenfold is already signing.") code:SFErrorAlreadyUndertakingPipeline];
                [self notify:^(id<SFApplicationSigningProtocol> o) { [o applicationSigningCompleteWithError:busy]; }];
                return;
            }
            if (applications.count == 0) {
                NSError *none = [self errorWithText:SFL(@"No apps need signing.") code:SFErrorNoSigningRequired];
                [self notify:^(id<SFApplicationSigningProtocol> o) { [o applicationSigningCompleteWithError:none]; }];
                return;
            }
            self.running = YES;
            self.stopAfterCurrent = NO;
            self.queue = [applications mutableCopy];
            self.active = 0;
            self.lastError = nil;
            self.retried = [NSMutableSet set];
            NSNumber *parallel = [[NSUserDefaults standardUserDefaults] objectForKey:@"sfParallelSigning"];
            self.maxAtOnce = (parallel && !parallel.boolValue) ? 1 : 3;
            self.teamID = teamID; self.username = username; self.password = password;
        }
        // Keep running for a while if the user leaves the app.
        UIApplication *app = [UIApplication sharedApplication];
        __block UIBackgroundTaskIdentifier task = [app beginBackgroundTaskWithName:@"Sevenfold Signing" expirationHandler:^{
            [app endBackgroundTask:task];
            task = UIBackgroundTaskInvalid;
        }];
        self.backgroundTask = task;

        for (SFApplication *queued in [applications reverseObjectEnumerator]) [self progress:0 for:queued.bundleIdentifier ?: @""];
        [self signNext];
    });
}

- (void)requestStopAfterCurrentApplication { self.stopAfterCurrent = YES; }

- (BOOL)removeApplicationWithBundleIdentifier:(NSString *)bundleIdentifier { return SFUninstall(bundleIdentifier, NULL); }

// MARK: Per app

/// Starts apps until maxAtOnce are running, half a second apart.
- (void)signNext {
    NSMutableArray *starting = [NSMutableArray array];
    BOOL finished = NO;
    @synchronized (self) {
        if (self.stopAfterCurrent) [self.queue removeAllObjects];
        while (self.active < self.maxAtOnce && self.queue.count) {
            [starting addObject:self.queue.firstObject];
            [self.queue removeObjectAtIndex:0];
            self.active++;
        }
        finished = self.active == 0 && self.queue.count == 0;
    }
    if (finished) { [self finishRunWithError:self.lastError]; return; }
    [starting enumerateObjectsUsingBlock:^(SFApplication *app, NSUInteger i, BOOL *stop) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 0.5 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            [self signApplication:app completion:^(NSError *error) { [self application:app finishedWithError:error]; }];
        });
    }];
}

/// Apple answers "too many requests" with HTTP 429 (sometimes 503).
static BOOL SFIsRateLimit(NSError *error) {
    NSString *text = error.localizedDescription ?: @"";
    return error.code == 429 || error.code == 503 || [text containsString:@"HTTP 429"] || [text containsString:@"HTTP 503"] ||
           [text localizedCaseInsensitiveContainsString:@"too many requests"];
}

- (void)application:(SFApplication *)app finishedWithError:(NSError *)error {
    NSString *bundleID = app.bundleIdentifier ?: @"";
    BOOL retry = NO;
    @synchronized (self) {
        self.active--;
        if (error && SFIsRateLimit(error) && ![self.retried containsObject:bundleID]) {
            // Slow down for the rest of the run and give this app one more go.
            [self.retried addObject:bundleID];
            if (self.maxAtOnce > 1) SFLogEvent(SFLogLevelInfo, @"signing · slowed down by Apple, signing one app at a time");
            self.maxAtOnce = 1;
            retry = YES;
        }
    }
    if (retry) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            @synchronized (self) { [self.queue insertObject:app atIndex:0]; }
            [self signNext];
        });
        return;
    }
    if (error) {
        @synchronized (self) { self.lastError = error; }
        [self notify:^(id<SFApplicationSigningProtocol> o) { [o applicationSigningDidEncounterError:error forBundleIdentifier:bundleID]; }];
    }
    [self signNext];
}

- (void)finishRunWithError:(NSError *)error {
    if (self.backgroundTask != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:self.backgroundTask];
        self.backgroundTask = UIBackgroundTaskInvalid;
    }
    self.running = NO;
    self.password = nil;
    [self notify:^(id<SFApplicationSigningProtocol> o) { [o applicationSigningCompleteWithError:error]; }];
}

/// Copies an installed app (or unpacks a picked .ipa) into a fresh folder laid out like an .ipa:
/// <workspace>/Payload/<Name>.app. Returns the .app path.
- (NSString *)stageApplication:(SFApplication *)app workspace:(NSString *)workspace error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *payload = [workspace stringByAppendingPathComponent:@"Payload"];
    NSError *fileError = nil;
    BOOL installed = [app.class isEqual:[SFApplication class]];
    NSString *source = app.locationOfApplicationOnFilesystem.path;
    if (source.length == 0) {
        if (error) *error = [self errorWithText:SFL(@"Couldn't find the app on this iPhone.") code:SFErrorFailedToCopyBundle];
        return nil;
    }
    if (installed) {
        if (![fm createDirectoryAtPath:payload withIntermediateDirectories:YES attributes:nil error:&fileError] ||
            ![fm copyItemAtPath:source toPath:[payload stringByAppendingPathComponent:source.lastPathComponent] error:&fileError]) {
            if (error) *error = [self errorWithText:fileError.localizedDescription ?: SFL(@"Couldn't copy the app.") code:SFErrorFailedToCopyBundle];
            return nil;
        }
    } else {
        if (![SSZipArchive unzipFileAtPath:source toDestination:workspace overwrite:YES password:nil error:&fileError]) {
            if (error) *error = [self errorWithText:fileError.localizedDescription ?: SFL(@"Couldn't unpack the .ipa.") code:SFErrorFailedToCopyBundle];
            return nil;
        }
        [fm removeItemAtPath:source error:nil];   // the picker's copy; no longer needed
    }
    NSMutableArray *apps = [NSMutableArray array];
    for (NSString *entry in [fm contentsOfDirectoryAtPath:payload error:nil]) {
        BOOL isDir = NO;
        if ([entry.pathExtension caseInsensitiveCompare:@"app"] == NSOrderedSame &&
            [fm fileExistsAtPath:[payload stringByAppendingPathComponent:entry] isDirectory:&isDir] && isDir) [apps addObject:entry];
    }
    if (apps.count != 1) {
        NSString *text = apps.count == 0 ? SFL(@"The .ipa has no app inside its Payload folder.")
                                         : [NSString stringWithFormat:SFL(@"The .ipa has more than one app inside (%@), so Sevenfold stopped."), [apps componentsJoinedByString:@", "]];
        if (error) *error = [self errorWithText:text code:SFErrorFailedToCopyBundle];
        return nil;
    }
    return [payload stringByAppendingPathComponent:apps.firstObject];
}

- (void)signApplication:(SFApplication *)app completion:(void (^)(NSError *error))completion {
    NSString *original = [app.bundleIdentifier copy] ?: @"";
    BOOL replacesInstalled = [app.class isEqual:[SFApplication class]];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *workspace = [[SFBackend applicationTemporaryDirectory] stringByAppendingPathComponent:
                           [NSString stringWithFormat:@"sevenfold-staging-%@", [NSUUID UUID].UUIDString]];
    void (^fail)(NSError *) = ^(NSError *error) {
        [fm removeItemAtPath:workspace error:nil];
        completion(error);
    };

    [self progress:10 for:original];
    NSError *error = nil;
    if (![fm createDirectoryAtPath:workspace withIntermediateDirectories:YES attributes:nil error:&error]) {
        fail([self errorWithText:error.localizedDescription ?: SFL(@"Couldn't create a working folder.") code:SFErrorFailedToCopyBundle]);
        return;
    }
    NSString *appPath = [self stageApplication:app workspace:workspace error:&error];
    if (!appPath) { fail(error); return; }
    SFLogEvent(SFLogLevelInfo, @"signing · %@ staged (%@)", app.applicationName ?: original, replacesInstalled ? @"installed app" : @".ipa");
    [self progress:30 for:original];

    [SFBackend signBundleAtPath:appPath identity:self.username gsToken:self.password priorChosenTeamID:self.teamID withCompletionHandler:^(NSError *signError) {
        if (signError) { fail(signError); return; }
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[appPath stringByAppendingPathComponent:@"Info.plist"]];
        NSString *signedID = [info[@"CFBundleIdentifier"] isKindOfClass:[NSString class]] ? info[@"CFBundleIdentifier"] : nil;
        if (signedID.length == 0) {
            fail([self errorWithText:SFL(@"The signed app has no bundle ID, so it wasn't installed.") code:SFErrorFailedToInstallSignedIPA]);
            return;
        }
        [self progress:50 for:original];

        NSString *ipa = [[SFBackend applicationTemporaryDirectory] stringByAppendingPathComponent:
                         [NSString stringWithFormat:@"sevenfold-signed-%@.ipa", [NSUUID UUID].UUIDString]];
        NSError *packError = nil;
        BOOL packed = [SFBackend repackIpaAtPath:workspace toPath:ipa error:&packError];
        [fm removeItemAtPath:workspace error:nil];
        if (!packed) { completion(packError); return; }
        [self progress:60 for:original];
        SFLogEvent(SFLogLevelInfo, @"signing · %@ packed, installing", signedID);

        SFInstallIPA([NSURL fileURLWithPath:ipa], signedID, ^(BOOL ok, NSError *installError) {
            [fm removeItemAtPath:ipa error:nil];
            if (!ok) {
                completion([self errorWithText:SFInstallerMessage(installError, original, signedID) code:SFErrorFailedToInstallSignedIPA]);
                return;
            }
            [self progress:90 for:original];
            // The app came back under a new bundle ID: remove the old copy.
            if (replacesInstalled && ![original isEqualToString:signedID]) {
                NSError *removeError = nil;
                if (!SFUninstall(original, &removeError))
                    NSLog(@"[Sevenfold] installed %@ but couldn't remove the old %@: %@", signedID, original, removeError);
            }
            [self progress:100 for:original];
            completion(nil);
        });
    }];
}

@end
