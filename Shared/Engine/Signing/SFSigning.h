//
//  SFSigning.h
//  Sevenfold
//
//  Sevenfold · BY: T4MAG0
//
//  Code-signs an app bundle (and everything nested in it) with the user's
//  development certificate, using ldid.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SFSigning : NSObject

/// certificate: DER bytes from Apple. privateKey: PEM text of the matching key.
+ (instancetype)signerWithCertificate:(NSData *)certificate privateKey:(NSString *)privateKey;

/// Entitlements embedded in a Mach-O binary (empty if it has none, nil if unreadable).
+ (nullable NSMutableDictionary *)getEntitlementsForBinaryAtLocation:(NSString *)binaryLocation;

/// The binary's entitlements rewritten for this team and bundle ID.
+ (NSDictionary *)updateEntitlementsForBinaryAtLocation:(NSString *)binaryLocation bundleIdentifier:(NSString *)bundleIdentifier teamID:(NSString *)teamid;

/// Signs the .app at `absolutePath`. The top-level app gets `entitlements`; nested
/// extensions and frameworks keep their own. Calls back with success and an error message.
- (void)signBundleAtPath:(NSString *)absolutePath entitlements:(NSDictionary *)entitlements identifier:(NSString *)bundleIdentifier withCallback:(void (^)(BOOL success, NSString *message))completionHandler;

@end

NS_ASSUME_NONNULL_END
