//
//  SFBackgroundSigningManager.h
//  Sevenfold
//
//  BY: T4MAG0
//
//  Runs an automatic (scheduled or background refresh) signing pass. Requests that
//  arrive while one is running join it and are answered when it ends.
//

#import <Foundation/Foundation.h>
#import "SFApplicationSigning.h"

@interface SFBackgroundSigningManager : NSObject <SFApplicationSigningProtocol>

+ (instancetype)sharedInstance;
- (void)attemptBackgroundSigningIfNecessary:(void (^)(void))completionHandler;
- (void)attemptBackgroundSigningIfNecessaryWithCompletion:(void (^)(NSError *error))completionHandler;

/// YES when an app is within the signing threshold.
- (BOOL)anyApplicationsNeedingSigning;
/// Plugged in: signs only apps expiring within the threshold; does nothing (quietly) if none are.
- (void)attemptPlugInSigningWithCompletion:(void (^)(NSError *error))completionHandler;

@end
