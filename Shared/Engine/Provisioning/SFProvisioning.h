//
//  SFProvisioning.h
//  Sevenfold
//
//  Gets everything Apple has to hand out before an app can be signed:
//  the team, this iPhone's development certificate, the App ID and the profile.
//

#import <Foundation/Foundation.h>
#import "SFAppleServices.h"

@interface SFProvisioning : NSObject

/// A provisioner that works with the given Apple session.
+ (instancetype)provisionerWithCredentials:(NSString *)identity :(NSString *)gsToken;

/// Registers a device (by UDID) with the team.
- (void)provisionDevice:(NSString *)udid name:(NSString *)name withTeamIDCheck:(NSString * (^)(NSArray *))teamIDCallback systemType:(SFSystemType)systemType andCallback:(void (^)(NSError *))completionHandler;

/// Revokes the certificate that belongs to this iPhone, if there is one.
- (void)revokeCertificatesWithTeamIDCheck:(NSString * (^)(NSArray *))teamIDCallback systemType:(SFSystemType)systemType andCallback:(void (^)(NSError *))completionHandler;

/// Returns, for one bundle ID: the profile, the private key (PEM), the certificate
/// attributes and the entitlements the app may be signed with.
- (void)downloadProvisioningProfileForApplicationIdentifier:(NSString *)identifier applicationName:(NSString *)applicationName binaryLocation:(NSString *)binaryLocation withTeamIDCheck:(NSString * (^)(NSArray *))teamIDCallback systemType:(SFSystemType)systemType andCallback:(void (^)(NSError *, NSData *, NSString *, NSDictionary *, NSDictionary *))completionHandler;

/// Forgets the certificate remembered during a signing run.
+ (void)sevenfoldResetCertificateCache;

@end
