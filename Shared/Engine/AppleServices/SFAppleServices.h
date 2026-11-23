//
//  SFAppleServices.h
//  Sevenfold
//
//  BY: T4MAG0
//
//  Talks to Apple's developer servers (developerservices2.apple.com) as Xcode does.
//  Every call answers (error, dictionary): error is a network or format problem,
//  and the dictionary is Apple's answer, which can still hold an error of its own.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

typedef enum : NSUInteger {
    SFSystemTypeUndefined,
    SFSystemTypeiOS,
    SFSystemTypewatchOS,
    SFSystemTypetvOS
} SFSystemType;

typedef void (^SFAppleAnswer)(NSError *error, NSDictionary *answer);
typedef void (^SFSignInResult)(NSError *error, NSDictionary *answer, NSURLCredential *credential);

@interface SFAppleServices : NSObject

+ (instancetype)sharedInstance;

#pragma mark Session

/// The team chosen by the last updateCurrentTeamID call ("" if none).
- (NSString *)currentTeamID;

/// Uses a saved identity and token for the calls that follow.
- (void)ensureSessionWithIdentity:(NSString *)identity gsToken:(NSString *)token andCompletionHandler:(SFAppleAnswer)completionHandler;

/// Signs in with an Apple ID. The answer has "reason" and "userString"; an empty userString means signed in.
- (void)signInWithUsername:(NSString *)email password:(NSString *)password andCompletionHandler:(SFSignInResult)completionHandler;
- (void)requestTwoFactorLoginCodeWithCompletionHandler:(void (^)(NSError *))completion;
- (BOOL)hasActiveTwoFactorSession;
- (void)validateLoginCode:(NSString *)code andCompletionHandler:(SFSignInResult)completionHandler;

#pragma mark Teams

/// Finds the account's team (asking teamIDCallback when there are several) and remembers it for 10 minutes.
- (void)updateCurrentTeamIDWithTeamIDCheck:(NSString * (^)(NSArray *))teamIDCallback andCallback:(void (^)(NSError *, NSString *))completionHandler;
- (void)listTeamsWithCompletionHandler:(SFAppleAnswer)completionHandler;
- (void)listTeamsWithCredentials:(NSURLCredential *)credentials completionHandler:(SFAppleAnswer)completionHandler;

#pragma mark Devices

- (void)addDevice:(NSString *)udid deviceName:(NSString *)name forTeamID:(NSString *)teamID systemType:(SFSystemType)systemType withCompletionHandler:(SFAppleAnswer)completionHandler;
- (void)listDevicesForTeamID:(NSString *)teamID systemType:(SFSystemType)systemType withCompletionHandler:(SFAppleAnswer)completionHandler;

#pragma mark App IDs and app groups

- (void)listAllApplicationsForTeamID:(NSString *)teamID systemType:(SFSystemType)systemType withCompletionHandler:(SFAppleAnswer)completionHandler;
- (void)addApplicationId:(NSString *)applicationIdentifier name:(NSString *)applicationName enabledFeatures:(NSDictionary *)enabledFeatures teamID:(NSString *)teamID entitlements:(NSDictionary *)entitlements systemType:(SFSystemType)systemType withCompletionHandler:(SFAppleAnswer)completionHandler;
- (void)updateApplicationIdId:(NSString *)appIdId enabledFeatures:(NSDictionary *)enabledFeatures teamID:(NSString *)teamID entitlements:(NSDictionary *)entitlements systemType:(SFSystemType)systemType withCompletionHandler:(SFAppleAnswer)completionHandler;
- (void)deleteApplicationIdId:(NSString *)appIdId teamID:(NSString *)teamID systemType:(SFSystemType)systemType withCompletionHandler:(SFAppleAnswer)completionHandler;
- (void)listAllApplicationGroupsForTeamID:(NSString *)teamID systemType:(SFSystemType)systemType withCompletionHandler:(SFAppleAnswer)completionHandler;
- (void)addApplicationGroupWithIdentifier:(NSString *)identifier andName:(NSString *)groupName forTeamID:(NSString *)teamID systemType:(SFSystemType)systemType withCompletionHandler:(SFAppleAnswer)completionHandler;
- (void)assignApplicationGroup:(NSString *)applicationGroup toApplicationIdId:(NSString *)appIdId teamID:(NSString *)teamID systemType:(SFSystemType)systemType withCompletionHandler:(SFAppleAnswer)completionHandler;

#pragma mark Certificates

/// Lists development certificates (v1 API). useFilter limits it to iOS development certificates.
- (void)listAllDevelopmentCertificatesWithFiltering:(BOOL)useFilter teamID:(NSString *)teamID systemType:(SFSystemType)systemType withCompletionHandler:(SFAppleAnswer)completionHandler;
- (void)listAllDevelopmentCertificatesForTeamID:(NSString *)teamID systemType:(SFSystemType)systemType withCompletionHandler:(SFAppleAnswer)completionHandler;
/// Revokes by certificate ID (v1 DELETE; an empty 204 answer means success).
- (void)revokeCertificateForIdentifier:(NSString *)identifier andTeamID:(NSString *)teamID systemType:(SFSystemType)systemType withCompletionHandler:(SFAppleAnswer)completionHandler;
- (void)submitCodeSigningRequestForTeamID:(NSString *)teamId machineName:(NSString *)machineName machineID:(NSString *)machineID codeSigningRequest:(NSData *)csr systemType:(SFSystemType)systemType withCompletionHandler:(SFAppleAnswer)completionHandler;

#pragma mark Profiles

- (void)listAllProvisioningProfilesForTeamID:(NSString *)teamID systemType:(SFSystemType)systemType withCompletionHandler:(SFAppleAnswer)completionHandler;
- (void)getProvisioningProfileForAppIdId:(NSString *)appIdId withTeamID:(NSString *)teamId systemType:(SFSystemType)systemType andCompletionHandler:(SFAppleAnswer)completionHandler;
/// Deletes the team profile whose App ID contains applicationId (errors if there is none).
- (void)deleteProvisioningProfileForApplication:(NSString *)applicationId andTeamID:(NSString *)teamID systemType:(SFSystemType)systemType withCompletionHandler:(SFAppleAnswer)completionHandler;

@end
