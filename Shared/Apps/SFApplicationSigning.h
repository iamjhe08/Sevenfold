//
//  SFApplicationSigning.h
//  Sevenfold
//
//  Sevenfold · BY: T4MAG0
//
//  Runs apps through the signing pipeline one at a time:
//  stage → sign → pack → install, reporting progress to observers.
//

#import <Foundation/Foundation.h>
#import "SFErrors.h"

NS_ASSUME_NONNULL_BEGIN

@protocol SFApplicationSigningProtocol <NSObject>
/// A run started.
- (void)applicationSigningDidStart;
/// 0–100 for one app (10 staged… 30 copied, 50 signed, 60 packed, 90 installed, 100 done).
- (void)applicationSigningUpdateProgress:(int)progress forBundleIdentifier:(NSString *)bundleIdentifier;
/// One app failed; the run carries on with the next.
- (void)applicationSigningDidEncounterError:(NSError *)error forBundleIdentifier:(NSString *)bundleIdentifier;
/// The run ended (error = the last app's failure, or a reason nothing ran).
- (void)applicationSigningCompleteWithError:(nullable NSError *)error;
@end

@interface SFApplicationSigning : NSObject

+ (instancetype)sharedInstance;

/// Signs the team's apps: all of them, or only those expiring within `thresholdForExpiration` days.
/// Apps the user excluded from auto-signing are skipped.
- (void)signApplications:(BOOL)onlyExpiringApplications thresholdForExpiration:(int)thresholdForExpiration withTeamID:(NSString *)teamID username:(NSString *)username password:(NSString *)password;

/// Signs exactly these apps (installed apps or picked .ipa files).
- (void)signSpecificApplications:(NSArray *)applications withTeamID:(NSString *)teamID username:(NSString *)username password:(NSString *)password;

- (void)addSigningUpdatesObserver:(id<SFApplicationSigningProtocol>)observer;
- (void)removeSigningUpdatesObserver:(id<SFApplicationSigningProtocol>)observer;

- (BOOL)removeApplicationWithBundleIdentifier:(NSString *)bundleIdentifier;
/// Finish the app being signed, then stop.
- (void)requestStopAfterCurrentApplication;

@end

NS_ASSUME_NONNULL_END
