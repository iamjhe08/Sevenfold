//
//  SFNotificationManager.h
//  Sevenfold
//

#import <Foundation/Foundation.h>
#import <UserNotifications/UserNotifications.h>

@interface SFNotificationManager : NSObject <UNUserNotificationCenterDelegate>
+ (instancetype)sharedInstance;
- (void)registerToSendNotifications;
- (void)sendNotificationWithTitle:(NSString*)title body:(NSString*)body isDebugMessage:(BOOL)isDebug isUrgentMessage:(BOOL)isUrgent andNotificationID:(NSString*)identifier;
- (void)sendNotificationWithTitle:(NSString*)title body:(NSString*)body isDebugMessage:(BOOL)isDebug andNotificationID:(NSString*)identifier;
/// Always delivered (the caller checks the user's notification settings).
- (void)sendSevenfoldNotificationWithTitle:(NSString *)title body:(NSString *)body identifier:(NSString *)identifier;
- (void)sendSevenfoldNotificationWithTitle:(NSString *)title body:(NSString *)body identifier:(NSString *)identifier delay:(NSTimeInterval)delay;
/// "Allowed", "Not allowed", "Not asked yet", with whether lock screen display is on.
- (void)fetchPermissionSummary:(void (^)(NSString *summary, BOOL allowed, BOOL denied))completion;
@end
