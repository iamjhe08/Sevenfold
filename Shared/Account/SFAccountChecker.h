//
//  SFAccountChecker.h
//  Sevenfold
//
//  BY: T4MAG0
//
//  What the sign-in screen talks to: signs in, handles the 2FA code, loads the
//  developer teams, and registers this iPhone (and a paired Watch) with the team.
//
//  Every sign-in answer is (message, code, teams, credential):
//    teams != nil      signed in; message may hold a note (e.g. accept the terms)
//    code == "err"     failed; message says why
//    otherwise         Apple wants another step (e.g. 2FA); code is Apple's reason
//

#import <Foundation/Foundation.h>

typedef void (^SFSignInAnswer)(NSString *message, NSString *code, NSArray *teams, NSURLCredential *credential);

@interface SFAccountChecker : NSObject

+ (instancetype)sharedInstance;

- (void)checkUsername:(NSString *)username withPassword:(NSString *)password andCompletionHandler:(SFSignInAnswer)completionHandler;
- (void)requestLoginCodeWithCompletionHandler:(void (^)(NSError *error))completion;
- (BOOL)hasActiveTwoFactorSession;
- (void)validateLoginCode:(NSString *)code withCompletionHandler:(SFSignInAnswer)completionHandler;

- (void)registerCurrentDeviceForTeamID:(NSString *)teamID withIdentity:(NSString *)username gsToken:(NSString *)password andCompletionHandler:(void (^)(NSError *))completionHandler;
- (void)registerCurrentWatchForTeamID:(NSString *)teamID withIdentity:(NSString *)username gsToken:(NSString *)password andCompletionHandler:(void (^)(NSError *))completionHandler;

@end
