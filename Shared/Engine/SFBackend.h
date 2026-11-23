//
//  SFBackend.h
//  Sevenfold
//
//  Sevenfold · BY: T4MAG0
//
//  Signs an unpacked .app for the user's team: nested extensions and Watch apps
//  first, then the app itself. Credentials only ever go to Apple.
//

#import <Foundation/Foundation.h>
#import "SFAppleServices.h"

NS_ASSUME_NONNULL_BEGIN

@interface SFBackend : NSObject

/// Registers a device (UDID) with the team so profiles include it.
+ (void)provisionDevice:(NSString *)udid name:(NSString *)name identity:(NSString *)identity gsToken:(NSString *)gsToken priorChosenTeamID:(NSString *)teamId systemType:(SFSystemType)systemType withCallback:(void (^)(NSError * _Nullable error))completionHandler;

/// Revokes this device's development certificates for the team.
+ (void)revokeDevelopmentCertificatesForCurrentMachineWithIdentity:(NSString *)identity gsToken:(NSString *)gsToken priorChosenTeamID:(NSString *)teamId systemType:(SFSystemType)systemType withCallback:(void (^)(NSError * _Nullable error))completionHandler;

/// Gives the .app at `path` (and everything nested in it) a fresh profile and signature.
+ (void)signBundleAtPath:(NSString *)path identity:(NSString *)identity gsToken:(NSString *)gsToken priorChosenTeamID:(NSString *)teamId withCompletionHandler:(void (^)(NSError * _Nullable error))completionHandler;

/// Zips a folder containing Payload/ into an .ipa (stored, not compressed: faster to install).
+ (BOOL)repackIpaAtPath:(NSString *)extractedPath toPath:(NSString *)outputPath error:(NSError * _Nullable * _Nullable)error;

/// Where Sevenfold keeps its working files.
+ (NSString *)applicationTemporaryDirectory;

@end

NS_ASSUME_NONNULL_END
