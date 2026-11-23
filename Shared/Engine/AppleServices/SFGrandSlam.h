//
//  SFGrandSlam.h
//  Sevenfold
//
//  BY: T4MAG0
//
//  Signs in to Apple's GrandSlam service (gsa.apple.com) the way Xcode does:
//  SRP password proof, then an app token for com.apple.gs.xcode.auth.
//  Also requests and checks two-factor codes.
//

#import <Foundation/Foundation.h>

// Error codes (NSError.code) the rest of Sevenfold looks at.
#define SFInternalLoginError                            5000   // anything not covered below
#define SFInternalLogin2FARequiredTrustedDeviceError    4010   // code goes to a trusted device
#define SFInternalLogin2FARequiredSecondaryAuthError    4011   // code goes to a trusted phone number
#define SFInternalLoginIncorrect2FACodeError            4012
#define SFInternalLoginInvalid2FAFormatError            4013
#define SFInternalLoginPostTwoFactorError               4014   // code accepted, follow-up sign-in failed

/// error == nil: signed in, userIdentity is "<dsid>|<account>" and gsToken the Xcode token.
/// error.code 4010/4011: two-factor needed; userIdentity and idmsToken are set for the code step.
typedef void (^SFLoginResultBlock)(NSError *error, NSString *userIdentity, NSString *gsToken, NSString *idmsToken);
typedef void (^SFTwoFactorResultBlock)(NSError *error);

@interface SFGrandSlam : NSObject

/// Sent as X-MMe-Client-Info. Any Xcode client name in it is changed to akd.
@property (nonatomic, copy) NSString *clientInfo;
/// Anisette headers from the remote provider. When empty, this iPhone's own AuthKit is used.
@property (nonatomic, copy) NSDictionary *anisette;

- (void)loginWithUsername:(NSString *)username password:(NSString *)password completion:(SFLoginResultBlock)completion;

/// mode is 4010 (trusted device) or 4011 (trusted phone).
- (void)requestTwoFactorCodeWithUserIdentity:(NSString *)userIdentity idmsToken:(NSString *)token mode:(int)mode completion:(SFTwoFactorResultBlock)completion;
- (void)submitTwoFactorCode:(NSString *)code userIdentity:(NSString *)userIdentity idmsToken:(NSString *)token mode:(int)mode completion:(SFTwoFactorResultBlock)completion;

@end
