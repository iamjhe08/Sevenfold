//
//  SFApplicationProtocol.h
//  Sevenfold
//
//  BY: T4MAG0
//
//  Calls the background service (sevenfoldd) makes on the app over XPC.
//

@protocol SFApplicationProtocol <NSObject>

/// It's time for a scheduled run.
- (void)daemonDidRequestNewBackgroundSigning;
/// The phone restarted: check the saved sign-in still works.
- (void)daemonDidRequestCredentialsCheck;
/// Show a notification that was waiting for the phone to be unlocked.
- (void)daemonDidRequestQueuedNotification;

@end
