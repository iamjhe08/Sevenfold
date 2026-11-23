//
//  SFDaemonProtocol.h
//  Sevenfold
//
//  BY: T4MAG0
//
//  Calls the app makes on the background service (sevenfoldd) over XPC.
//

@protocol SFDaemonProtocol <NSObject>

/// The app is up and connected: deliver anything that was waiting for it.
- (void)applicationDidLaunch;
/// The app finished what it was woken for and may be suspended again.
- (void)applicationDidFinishTask;
/// Keep the app running in the background for a little while.
- (void)applicationRequestsSigningAssertion;
/// Keep the app (and the phone) awake until the run with this identifier finishes.
- (void)applicationRequestsSigningAssertionWithIdentifier:(NSString *)identifier;
- (void)applicationDidFinishSigningWithIdentifier:(NSString *)identifier;

/// Start a background run now (Settings › Diagnostics).
- (void)applicationRequestsDebuggingBackgroundSigning;
/// Settings changed: re-read them and re-plan the schedule.
- (void)applicationRequestsPreferencesUpdate;
/// Try the run again after this many seconds (clamped to 1 min … 6 h).
- (void)applicationRequestsRetryAfter:(double)seconds;

@end
