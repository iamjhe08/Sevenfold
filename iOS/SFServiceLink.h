//
//  SFServiceLink.h
//  Sevenfold
//
//  BY: T4MAG0
//
//  The app's side of the connection to the background service (sevenfoldd):
//  connects and reconnects, does what the service asks (scheduled run, sign-in
//  check, queued notice), and keeps the app awake while a signing pass runs.
//

#import <Foundation/Foundation.h>
#import "SFApplicationProtocol.h"
#import "SFApplicationSigning.h"

@interface SFServiceLink : NSObject <SFApplicationProtocol, SFApplicationSigningProtocol>

+ (instancetype)shared;

/// Connects (again, if needed). Safe to call any time.
- (void)connect;
/// The app became active: reconnect if idle and show any connection problem saved for now.
- (void)appBecameActive;
- (void)appBecameInactive;
@property (nonatomic, readonly) BOOL connected;

/// Settings › Diagnostics: ask the service to start a background run, answered when it ends.
- (void)testBackgroundRunWithCompletion:(void (^)(NSError *error))completion;
- (void)sendPreferencesUpdate;
- (void)retryAfter:(double)seconds;

@end
