//
//  SFNotificationManager.m
//  Sevenfold
//

#import <objc/runtime.h>
#import <UIKit/UIKit.h>
#import "HookUtil.h"
#import "SFLocalization.h"
#import "SFNotificationManager.h"
#import "SFResources.h"
#import "SFLog.h"

// A platform app without a container can hand UNUserNotificationCenter a nil
// bundle ID; fall back to our own.
HOOK_MESSAGE(id, UNUserNotificationCenter, initWithBundleIdentifier_, NSString *bundleID) {
    if (!bundleID) bundleID = [[NSBundle mainBundle] bundleIdentifier];
    id result;
    @try {
        result = _UNUserNotificationCenter_initWithBundleIdentifier_(self, sel, bundleID);
    } @catch (NSException *e) {
        result = _UNUserNotificationCenter_initWithBundleIdentifier_(self, sel, [[NSBundle mainBundle] bundleIdentifier]);
    }
    return result;
}

@implementation SFNotificationManager

+ (instancetype)sharedInstance {
    static SFNotificationManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[SFNotificationManager alloc] init];
    });
    return sharedInstance;
}

- (void)registerToSendNotifications {
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    center.delegate = self;
    [center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge)
                          completionHandler:^(BOOL granted, NSError *error) {
        if (error) SFLogEvent(SFLogLevelWarning, @"notifications · permission error: %@", error.localizedDescription);
        else if (!granted) SFLogEvent(SFLogLevelWarning, @"notifications · permission not granted");
    }];
}

- (void)sendNotificationWithTitle:(NSString *)title body:(NSString *)body isDebugMessage:(BOOL)isDebug andNotificationID:(NSString *)identifier {
    [self sendNotificationWithTitle:title body:body isDebugMessage:isDebug isUrgentMessage:NO andNotificationID:identifier];
}

- (void)sendNotificationWithTitle:(NSString *)title body:(NSString *)body isDebugMessage:(BOOL)isDebug isUrgentMessage:(BOOL)isUrgent andNotificationID:(NSString *)identifier {
    if (isDebug && ![SFResources shouldShowDebugAlerts]) return;
    if (!isUrgent && ![SFResources shouldShowNonUrgentAlerts]) return;
    [self sendSevenfoldNotificationWithTitle:title body:body identifier:identifier];
}

- (void)sendSevenfoldNotificationWithTitle:(NSString *)title body:(NSString *)body identifier:(NSString *)identifier {
    [self sendSevenfoldNotificationWithTitle:title body:body identifier:identifier delay:1];
}

- (void)fetchPermissionSummary:(void (^)(NSString *, BOOL, BOOL))completion {
    [[UNUserNotificationCenter currentNotificationCenter] getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
        NSString *summary;
        BOOL allowed = NO, denied = NO;
        switch (settings.authorizationStatus) {
            case UNAuthorizationStatusNotDetermined: summary = SFL(@"Not asked yet"); break;
            case UNAuthorizationStatusDenied: summary = SFL(@"Not allowed"); denied = YES; break;
            default:
                allowed = YES;
                summary = settings.lockScreenSetting == UNNotificationSettingEnabled ? SFL(@"Allowed · lock screen on") : SFL(@"Allowed · lock screen off");
                break;
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(summary, allowed, denied); });
    }];
}

- (void)sendSevenfoldNotificationWithTitle:(NSString *)title body:(NSString *)body identifier:(NSString *)identifier delay:(NSTimeInterval)delay {
    // A new ID every time: reusing one lets iOS silently replace an older notification instead of showing a new one.
    identifier = [NSString stringWithFormat:@"%@.%.0f", identifier ?: @"sf", [NSDate date].timeIntervalSince1970 * 1000];
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = title ?: @"Sevenfold";
    content.body = body ?: @"";
    content.sound = [UNNotificationSound defaultSound];
    content.threadIdentifier = @"sevenfold.signing";
    if (@available(iOS 15.0, *)) content.interruptionLevel = UNNotificationInterruptionLevelActive;
    // No trigger: deliver right away, while Sevenfold is still allowed to run.
    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:identifier content:content trigger:nil];
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
        if (settings.authorizationStatus == UNAuthorizationStatusDenied || settings.authorizationStatus == UNAuthorizationStatusNotDetermined) {
            SFLogEvent(SFLogLevelWarning, @"notifications · \"%@\" not shown: %@", title,
                       settings.authorizationStatus == UNAuthorizationStatusDenied ? @"turned off in iOS Settings" : @"permission never granted");
            return;
        }
        [center addNotificationRequest:request withCompletionHandler:^(NSError *error) {
            if (error) SFLogEvent(SFLogLevelWarning, @"notifications · \"%@\" failed: %@", title, error.localizedDescription);
            else {
                SFLogEvent(SFLogLevelInfo, @"notifications · sent \"%@\"%@", title,
                           settings.lockScreenSetting == UNNotificationSettingEnabled ? @"" : @" (lock screen display is off)");
                // Check a moment later that iOS really shows it.
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                    [center getDeliveredNotificationsWithCompletionHandler:^(NSArray<UNNotification *> *delivered) {
                        BOOL shown = NO;
                        for (UNNotification *n in delivered) if ([n.request.identifier isEqualToString:identifier]) shown = YES;
                        SFLogEvent(shown ? SFLogLevelInfo : SFLogLevelWarning, @"notifications · \"%@\" %@", title,
                                   shown ? @"delivered" : @"not in Notification Center (iOS didn't deliver it)");
                    }];
                });
            }
        }];
    }];
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center didReceiveNotificationResponse:(UNNotificationResponse *)response withCompletionHandler:(void (^)(void))completionHandler {
    // Opening the app is enough: the Apps screen shows what needs attention.
    NSString *identifier = response.notification.request.identifier;
    if ([identifier hasPrefix:@"sf.failure"] || [identifier hasPrefix:@"sf.expiry"]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"com.t4mag0.sevenfold/openApps" object:nil];
    } else if ([identifier hasPrefix:@"sf.cert"]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"com.t4mag0.sevenfold/openCertificates" object:nil];
    }
    completionHandler();
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center willPresentNotification:(UNNotification *)notification withCompletionHandler:(void (^)(UNNotificationPresentationOptions options))completionHandler {
    completionHandler(UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionList);
}

@end
