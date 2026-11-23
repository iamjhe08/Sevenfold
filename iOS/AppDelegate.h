//
//  AppDelegate.h
//  Sevenfold
//
//  BY: T4MAG0
//

#import <UIKit/UIKit.h>

@interface AppDelegate : UIResponder <UIApplicationDelegate, NSURLSessionDownloadDelegate>

@property (strong, nonatomic) UIWindow *window;

// Background service (see SFServiceLink).
- (void)requestDebuggingBackgroundSigning;
- (void)requestDebuggingBackgroundSigningWithCompletion:(void (^)(NSError *error))completionHandler;
- (void)requestPreferencesUpdate;
- (void)requestRetryAfter:(double)seconds;
- (BOOL)daemonConnected;

@end
