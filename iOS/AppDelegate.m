//
//  AppDelegate.m
//  Sevenfold
//
//  BY: T4MAG0
//
//  Startup, background refresh, and opening things from outside the app:
//  .ipa files, certificate files, and sevenfold:// links.
//

#import "AppDelegate.h"
#import "SFServiceLink.h"
#import "SFBackgroundSigningManager.h"
#import "SFApplicationDatabase.h"
#import "SFNotificationManager.h"
#import "SFResources.h"
#import "SFTheme.h"
#import "SFRootController.h"
#import "SFSigningSession.h"
#import "SFLog.h"
#import "SFNetworkAccess.h"
#import "SAMKeychain.h"
#import "SFLocalization.h"
#import "SFLanguageViewController.h"

@interface AppDelegate ()
@property (nonatomic, strong) UIAlertController *downloadAlert;
@end

@implementation AppDelegate

#pragma mark - Launch

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [SFSigningSession shared];

    // The token must be readable while locked before the service can ask for a run.
    [SAMKeychain setAccessibilityType:kSecAttrAccessibleAfterFirstUnlock];
    [SFResources migrateStoredCredentialsForBackgroundAccessIfPossible];
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationProtectedDataDidBecomeAvailable object:nil queue:nil usingBlock:^(NSNotification *note) {
        [SFResources migrateStoredCredentialsForBackgroundAccessIfPossible];
    }];

    // Background refresh is only a safety net; the service owns the schedule.
    [application setMinimumBackgroundFetchInterval:UIApplicationBackgroundFetchIntervalMinimum];
    [[SFNotificationManager sharedInstance] registerToSendNotifications];
    [[SFServiceLink shared] connect];

    // China-model iPhones block network access for new apps until it's allowed.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ [SFNetworkAccess allowWiFiAndCellular]; });

    [SFTheme applyGlobalAppearance];
    [SFLanguage applyLayoutDirection];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(languageChanged) name:SFLanguageDidChangeNotification object:nil];
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.tintColor = [SFTheme accent];
    self.window.rootViewController = [SFRootController new];
    [self.window makeKeyAndVisible];
    return YES;
}

/// A new language: rebuild every screen (text and, for Arabic, the whole layout direction),
/// then come back to the same tab and to the Language screen the user was on.
- (void)languageChanged {
    UITabBarController *old = (UITabBarController *)self.window.rootViewController;
    NSUInteger tab = [old isKindOfClass:[UITabBarController class]] ? old.selectedIndex : 0;
    SFRootController *fresh = [SFRootController new];
    fresh.selectedIndex = tab;
    UINavigationController *nav = [fresh.selectedViewController isKindOfClass:[UINavigationController class]] ? (UINavigationController *)fresh.selectedViewController : nil;
    [nav pushViewController:[SFLanguageViewController new] animated:NO];
    [UIView transitionWithView:self.window duration:0.3 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
        self.window.rootViewController = fresh;
    } completion:nil];
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    [[SFServiceLink shared] appBecameActive];
}

- (void)applicationWillResignActive:(UIApplication *)application {
    [[SFServiceLink shared] appBecameInactive];
}

/// iOS wakes the app every so often. Sign only if an app would otherwise expire within a day
/// (for example after scheduled runs were missed).
- (void)application:(UIApplication *)application performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {
    NSMutableArray *expiring = [NSMutableArray array];
    NSString *team = [SFResources getTeamID];
    if (team.length)
        [[SFApplicationDatabase sharedInstance] getApplicationsWithExpiryDateBefore:&expiring andAfter:nil date:[NSDate dateWithTimeIntervalSinceNow:24 * 3600] forTeamID:team];
    if (expiring.count == 0) { completionHandler(UIBackgroundFetchResultNoData); return; }

    SFLogEvent(SFLogLevelInfo, @"background refresh · %lu app(s) expire within a day, signing now", (unsigned long)expiring.count);
    [[SFBackgroundSigningManager sharedInstance] attemptBackgroundSigningIfNecessary:^{
        completionHandler(UIBackgroundFetchResultNewData);
    }];
}

- (void)application:(UIApplication *)application performActionForShortcutItem:(UIApplicationShortcutItem *)shortcutItem completionHandler:(void (^)(BOOL))completionHandler {
    BOOL handled = [shortcutItem.type isEqualToString:@"com.t4mag0.sevenfold.sign-expiring"];
    if (handled) [[SFServiceLink shared] daemonDidRequestNewBackgroundSigning];
    completionHandler(handled);
}

#pragma mark - Background service

- (void)requestDebuggingBackgroundSigning                                       { [[SFServiceLink shared] testBackgroundRunWithCompletion:nil]; }
- (void)requestDebuggingBackgroundSigningWithCompletion:(void (^)(NSError *))c  { [[SFServiceLink shared] testBackgroundRunWithCompletion:c]; }
- (void)requestPreferencesUpdate                                                { [[SFServiceLink shared] sendPreferencesUpdate]; }
- (void)requestRetryAfter:(double)seconds                                       { [[SFServiceLink shared] retryAfter:seconds]; }
- (BOOL)daemonConnected                                                         { return [SFServiceLink shared].connected; }

#pragma mark - Opening files and links

- (SFRootController *)root {
    return (SFRootController *)self.window.rootViewController;
}

- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options {
    NSString *extension = url.pathExtension.lowercaseString;

    if ([extension isEqualToString:@"sevenfold-cert"]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [[self root] presentCertificateImportForURL:url]; });
        return YES;
    }
    if (url.isFileURL && [extension isEqualToString:@"ipa"]) {
        [self openIPA:url];
        return YES;
    }

    if ([url.scheme isEqualToString:@"sevenfold"]) {
        // sevenfold://share/<path>: a file handed over by the share sheet.
        if ([url.host containsString:@"share"] && url.path.length > 1) {
            [self openIPA:[NSURL fileURLWithPath:[url.path substringFromIndex:1]]];
            return YES;
        }
        // sevenfold://install?url=<link to an .ipa>: download it first.
        if ([url.host containsString:@"install"]) {
            NSString *link = nil;
            for (NSURLQueryItem *item in [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO].queryItems)
                if ([item.name isEqualToString:@"url"]) link = item.value;
            NSURL *download = link.length ? [NSURL URLWithString:link] : nil;
            if (!download) { [self showDownloadMessage:SFL(@"That link has no .ipa to install.") closeAfter:2]; return NO; }
            [self startDownload:download];
            return YES;
        }
    }
    [self showDownloadMessage:SFL(@"Sevenfold can't open this link.") closeAfter:2];
    return NO;
}

- (void)openIPA:(NSURL *)url {
    dispatch_async(dispatch_get_main_queue(), ^{ [[self root] presentInstallForIPAURL:url]; });
}

#pragma mark - Downloading an .ipa from a link

- (void)startDownload:(NSURL *)url {
    [self showDownloadMessage:SFL(@"Downloading…") closeAfter:0];
    NSURL *target = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:url.lastPathComponent];
    [[NSFileManager defaultManager] removeItemAtURL:target error:nil];
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:@"BackgroundSessionConfiguration"];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:nil];
    [[session downloadTaskWithURL:url] resume];
}

/// One alert shows the download; closeAfter > 0 closes it after that many seconds.
- (void)showDownloadMessage:(NSString *)message closeAfter:(NSTimeInterval)seconds {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.downloadAlert) {
            self.downloadAlert = [UIAlertController alertControllerWithTitle:nil message:message preferredStyle:UIAlertControllerStyleAlert];
            UIViewController *top = self.window.rootViewController;
            while (top.presentedViewController) top = top.presentedViewController;
            [top presentViewController:self.downloadAlert animated:YES completion:nil];
        }
        self.downloadAlert.message = message;
        if (seconds > 0) {
            UIAlertController *alert = self.downloadAlert;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (self.downloadAlert != alert) return;
                [self closeDownloadMessage];
            });
        }
    });
}

- (void)closeDownloadMessage {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = self.downloadAlert;
        self.downloadAlert = nil;
        [alert.presentingViewController dismissViewControllerAnimated:YES completion:nil];
    });
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task didWriteData:(int64_t)written totalBytesWritten:(int64_t)total totalBytesExpectedToWrite:(int64_t)expected {
    if (expected > 0) [self showDownloadMessage:[NSString stringWithFormat:SFL(@"Downloading…\n%d%%"), (int)lround(100.0 * total / expected)] closeAfter:0];
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task didFinishDownloadingToURL:(NSURL *)location {
    NSURL *target = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:task.originalRequest.URL.lastPathComponent];
    NSError *error = nil;
    [[NSFileManager defaultManager] removeItemAtURL:target error:nil];
    if ([[NSFileManager defaultManager] copyItemAtURL:location toURL:target error:&error]) {
        [self closeDownloadMessage];
        [self openIPA:target];
    } else {
        [self showDownloadMessage:[SFL(@"Couldn't save the download: ") stringByAppendingString:error.localizedDescription] closeAfter:2];
    }
    [session finishTasksAndInvalidate];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (!error) return;
    NSData *resumeData = error.userInfo[NSURLSessionDownloadTaskResumeData];
    BOOL appWasClosed = [error.userInfo[NSURLErrorBackgroundTaskCancelledReasonKey] integerValue] == NSURLErrorCancelledReasonUserForceQuitApplication;
    if (!(appWasClosed && resumeData)) {
        [self showDownloadMessage:[SFL(@"Download failed: ") stringByAppendingString:error.localizedDescription] closeAfter:2];
        [session finishTasksAndInvalidate];
        return;
    }
    // Sevenfold was closed mid-download: offer to pick up where it stopped.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self closeDownloadMessage];
        UIAlertController *ask = [UIAlertController alertControllerWithTitle:SFL(@"Download interrupted") message:SFL(@"Sevenfold was closed while downloading. Continue the download?") preferredStyle:UIAlertControllerStyleAlert];
        [ask addAction:[UIAlertAction actionWithTitle:SFL(@"Continue") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self showDownloadMessage:SFL(@"Downloading…") closeAfter:0];
            [[session downloadTaskWithResumeData:resumeData] resume];
        }]];
        [ask addAction:[UIAlertAction actionWithTitle:SFL(@"Cancel") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
            [session finishTasksAndInvalidate];
        }]];
        [self.window.rootViewController presentViewController:ask animated:YES completion:nil];
    });
}

@end
