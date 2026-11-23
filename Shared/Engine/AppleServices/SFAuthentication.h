//
//  SFAuthentication.h
//  Sevenfold
//
//  BY: T4MAG0
//
//  Holds one sign-in session: fetches anisette from the remote Mac servers, runs
//  GrandSlam sign-in, keeps what the two-factor step needs, and supplies the
//  anisette headers for developer-server requests.
//

#import <Foundation/Foundation.h>

typedef void (^SFAuthResult)(NSError *error, NSString *userIdentity, NSString *gsToken);

@interface SFAuthentication : NSObject

/// Signs in. On error 4010/4011 a two-factor session is kept for the calls below.
- (void)authenticateWithUsername:(NSString *)username password:(NSString *)password withCompletion:(SFAuthResult)completion;

- (BOOL)hasActiveTwoFactorSession;
- (void)requestLoginCodeWithCompletion:(void (^)(NSError *error))completion;
/// Checks the code, then signs in again (Apple now trusts this session) to get the token.
- (void)validateLoginCode:(NSString *)code withCompletion:(SFAuthResult)completion;

/// Anisette headers for a developer-server request.
- (NSDictionary *)appleIDHeadersForRequest:(NSURLRequest *)request;
/// Fresh anisette from the remote provider.
- (void)prepareAnisetteWithCompletion:(void (^)(NSError *error))completion;
/// Same, but reuses anisette fetched in the last 60 seconds (with a new client time).
- (void)prepareDeveloperServicesAnisetteWithCompletion:(void (^)(NSError *error))completion;
- (void)invalidateDeveloperServicesAnisette;

@end
