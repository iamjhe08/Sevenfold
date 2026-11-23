//
//  SFAccountChecker.m
//  Sevenfold
//
//  BY: T4MAG0
//

#import "SFAccountChecker.h"
#import "SFResources.h"
#import "SFAppleServices.h"
#import "SFBackend.h"
#import "SFLog.h"

#import <UIKit/UIKit.h>
#import "libMobileGestalt.h"

static NSString *SFText(id value) {
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

@implementation SFAccountChecker

+ (instancetype)sharedInstance {
    static SFAccountChecker *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [SFAccountChecker new]; });
    return shared;
}

#pragma mark - Sign-in

- (void)checkUsername:(NSString *)username withPassword:(NSString *)password andCompletionHandler:(SFSignInAnswer)completionHandler {
    [[SFAppleServices sharedInstance] signInWithUsername:username password:password andCompletionHandler:^(NSError *error, NSDictionary *plist, NSURLCredential *credential) {
        [self handleSignIn:error plist:plist credential:credential answer:completionHandler];
    }];
}

- (void)validateLoginCode:(NSString *)code withCompletionHandler:(SFSignInAnswer)completionHandler {
    [[SFAppleServices sharedInstance] validateLoginCode:code andCompletionHandler:^(NSError *error, NSDictionary *plist, NSURLCredential *credential) {
        [self handleSignIn:error plist:plist credential:credential answer:completionHandler];
    }];
}

- (void)requestLoginCodeWithCompletionHandler:(void (^)(NSError *))completion {
    [[SFAppleServices sharedInstance] requestTwoFactorLoginCodeWithCompletionHandler:completion];
}

- (BOOL)hasActiveTwoFactorSession {
    return [[SFAppleServices sharedInstance] hasActiveTwoFactorSession];
}

/// Apple's answer has a message only when another step is needed (or it failed).
/// No message means the password (or code) was accepted: load the teams next.
- (void)handleSignIn:(NSError *)error plist:(NSDictionary *)plist credential:(NSURLCredential *)credential answer:(SFSignInAnswer)answer {
    if (error) { answer(error.localizedDescription, @"err", nil, nil); return; }
    if (!plist) { answer(nil, @"err", nil, credential); return; }
    NSString *reason = SFText(plist[@"reason"]);
    NSString *message = SFText(plist[@"userString"]);
    if (message.length) { answer(message, reason, nil, credential); return; }
    // The sign-in is already used up at this point, so the team lookup retries rather than signing in again.
    [self loadTeamsWithCredential:credential reason:reason triesLeft:2 answer:answer];
}

- (void)loadTeamsWithCredential:(NSURLCredential *)credential reason:(NSString *)reason triesLeft:(NSUInteger)triesLeft answer:(SFSignInAnswer)answer {
    [[SFAppleServices sharedInstance] listTeamsWithCredentials:credential completionHandler:^(NSError *error, NSDictionary *plist) {
        NSArray *teams = [plist[@"teams"] isKindOfClass:[NSArray class]] ? plist[@"teams"] : nil;
        NSString *message = SFText(plist[@"userString"]);
        id code = plist[@"resultCode"];
        BOOL badCode = code && (![code respondsToSelector:@selector(integerValue)] || [code integerValue] != 0);
        BOOL failed = error || !teams || badCode || (teams.count == 0 && message.length);

        if (failed && triesLeft > 0) {
            SFLogEvent(SFLogLevelInfo, @"sign-in · team list failed, retrying (%lu left)", (unsigned long)triesLeft);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.75 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                [self loadTeamsWithCredential:credential reason:reason triesLeft:triesLeft - 1 answer:answer];
            });
            return;
        }
        if (failed) {
            NSString *why = error.localizedDescription.length ? error.localizedDescription : (message.length ? message : @"The developer account couldn't be loaded.");
            answer([@"Apple sign-in worked, but loading the developer account failed: " stringByAppendingString:why], @"err", nil, nil);
            return;
        }
        if (teams.count == 0) {
            answer(@"Please accept the Apple Developer terms at https://developer.apple.com", reason, teams, nil);
            return;
        }
        answer(message, reason, teams, credential);
    }];
}

#pragma mark - Devices

- (SFSystemType)systemType {
#if TARGET_OS_WATCH
    return SFSystemTypewatchOS;
#elif TARGET_OS_TV
    return SFSystemTypetvOS;
#else
    return SFSystemTypeiOS;
#endif
}

- (NSString *)deviceUDID {
    CFStringRef udid = (CFStringRef)MGCopyAnswer(kMGUniqueDeviceID);
    return CFBridgingRelease(udid);
}

- (void)registerCurrentDeviceForTeamID:(NSString *)teamID withIdentity:(NSString *)identity gsToken:(NSString *)gsToken andCompletionHandler:(void (^)(NSError *))completionHandler {
    [SFBackend provisionDevice:[self deviceUDID] name:[UIDevice currentDevice].name identity:identity gsToken:gsToken priorChosenTeamID:teamID systemType:[self systemType] withCallback:completionHandler];
}

- (void)registerCurrentWatchForTeamID:(NSString *)teamID withIdentity:(NSString *)identity gsToken:(NSString *)gsToken andCompletionHandler:(void (^)(NSError *))completionHandler {
    [SFBackend provisionDevice:[SFResources activePairedWatchUDID] name:[SFResources activePairedWatchName] identity:identity gsToken:gsToken priorChosenTeamID:teamID systemType:SFSystemTypewatchOS withCallback:completionHandler];
}

@end
