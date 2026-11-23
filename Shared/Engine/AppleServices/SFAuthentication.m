//
//  SFAuthentication.m
//  Sevenfold
//
//  BY: T4MAG0
//

#import "SFAuthentication.h"
#import "SFAuthKit.h"
#import "SFGrandSlam.h"
#import "SFRemoteAnisetteProvider.h"
#import "SFLog.h"

static NSString *const SFXcodeApp = @"com.apple.gs.xcode.auth";

@interface SFAuthentication ()
@property (nonatomic, strong) SFGrandSlam *grandSlam;
@property (nonatomic, strong) SFRemoteAnisetteProvider *anisetteProvider;
@property (nonatomic, strong) AKAppleIDSession *nativeSession;
@property (nonatomic, strong) NSDate *anisetteFetchedAt;

// Kept between "code needed" and "code entered".
@property (nonatomic, copy) NSString *pendingIdentity;
@property (nonatomic, copy) NSString *pendingIdmsToken;
@property (nonatomic, copy) NSString *pendingPassword;
@property (nonatomic) int pendingMode;
@end

@implementation SFAuthentication

- (instancetype)init {
    if ((self = [super init])) {
        _grandSlam = [SFGrandSlam new];
        _anisetteProvider = [SFRemoteAnisetteProvider new];
    }
    return self;
}

#pragma mark - Anisette

- (void)prepareAnisetteWithCompletion:(void (^)(NSError *))completion {
    [self.anisetteProvider fetchAnisetteDataWithCompletion:^(NSDictionary<NSString *, NSString *> *headers, NSError *error) {
        if (headers.count && !error) {
            self.grandSlam.anisette = headers;
            if ([headers[@"X-MMe-Client-Info"] length]) self.grandSlam.clientInfo = headers[@"X-MMe-Client-Info"];
        }
        completion(error);
    }];
}

- (void)prepareDeveloperServicesAnisetteWithCompletion:(void (^)(NSError *))completion {
    NSDictionary *cached = self.grandSlam.anisette;
    if (self.anisetteFetchedAt && cached.count && -self.anisetteFetchedAt.timeIntervalSinceNow < 60) {
        NSMutableDictionary *refreshed = [cached mutableCopy];
        NSDateFormatter *formatter = [NSDateFormatter new];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
        formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
        refreshed[@"X-Apple-I-Client-Time"] = [formatter stringFromDate:[NSDate date]];
        self.grandSlam.anisette = refreshed;
        completion(nil);
        return;
    }
    [self prepareAnisetteWithCompletion:^(NSError *error) {
        self.anisetteFetchedAt = error ? nil : [NSDate date];
        completion(error);
    }];
}

- (void)invalidateDeveloperServicesAnisette {
    self.anisetteFetchedAt = nil;
}

- (NSDictionary *)appleIDHeadersForRequest:(NSURLRequest *)request {
    NSMutableDictionary *headers = [self.grandSlam.anisette mutableCopy];
    if (!headers.count) {
        // No remote anisette yet: use this iPhone's own AuthKit.
        if (!self.nativeSession) self.nativeSession = [[NSClassFromString(@"AKAppleIDSession") alloc] initWithIdentifier:SFXcodeApp];
        headers = [[self.nativeSession appleIDHeadersForRequest:request] mutableCopy] ?: [NSMutableDictionary dictionary];
    }
    headers[@"X-Apple-App-Info"] = SFXcodeApp;
    if (self.grandSlam.clientInfo) headers[@"X-MMe-Client-Info"] = self.grandSlam.clientInfo;
    return headers;
}

#pragma mark - Sign-in

- (void)forgetTwoFactorSession {
    self.pendingIdentity = nil;
    self.pendingIdmsToken = nil;
    self.pendingPassword = nil;
    self.pendingMode = 0;
}

- (BOOL)hasActiveTwoFactorSession {
    return self.pendingIdentity.length && self.pendingIdmsToken.length && self.pendingPassword.length &&
           (self.pendingMode == SFInternalLogin2FARequiredTrustedDeviceError || self.pendingMode == SFInternalLogin2FARequiredSecondaryAuthError);
}

- (void)authenticateWithUsername:(NSString *)username password:(NSString *)password withCompletion:(SFAuthResult)completion {
    [self signInAs:username password:password fresh:YES completion:completion];
}

/// fresh: a sign-in the user started. It may get a new anisette identity and starts a new 2FA session.
/// Not fresh: the follow-up after a code was accepted, which must keep the same identity.
- (void)signInAs:(NSString *)username password:(NSString *)password fresh:(BOOL)fresh completion:(SFAuthResult)completion {
    [self invalidateDeveloperServicesAnisette];
    if (fresh) {
        [self forgetTwoFactorSession];
        self.anisetteProvider.identityPinned = NO;
    }
    [self prepareAnisetteWithCompletion:^(NSError *anisetteError) {
        if (anisetteError) { completion(anisetteError, nil, nil); return; }
        // From here on, login, 2FA, the token and developer requests all use this one identity.
        self.anisetteProvider.identityPinned = YES;
        [self.grandSlam loginWithUsername:username.lowercaseString password:password completion:^(NSError *error, NSString *identity, NSString *gsToken, NSString *idmsToken) {
            if (fresh && (error.code == SFInternalLogin2FARequiredTrustedDeviceError || error.code == SFInternalLogin2FARequiredSecondaryAuthError)) {
                self.pendingIdentity = identity;
                self.pendingIdmsToken = idmsToken;
                self.pendingPassword = password;
                self.pendingMode = (int)error.code;
            }
            completion(error, identity, gsToken);
        }];
    }];
}

- (void)requestLoginCodeWithCompletion:(void (^)(NSError *))completion {
    [self prepareAnisetteWithCompletion:^(NSError *anisetteError) {
        if (anisetteError) { completion(anisetteError); return; }
        [self.grandSlam requestTwoFactorCodeWithUserIdentity:self.pendingIdentity idmsToken:self.pendingIdmsToken mode:self.pendingMode completion:completion];
    }];
}

- (void)validateLoginCode:(NSString *)code withCompletion:(SFAuthResult)completion {
    if (![self hasActiveTwoFactorSession]) {
        completion([NSError errorWithDomain:NSCocoaErrorDomain code:SFInternalLoginError userInfo:@{ NSLocalizedDescriptionKey: @"The sign-in session has ended. Please go back and sign in again." }], nil, nil);
        return;
    }
    [self prepareAnisetteWithCompletion:^(NSError *anisetteError) {
        if (anisetteError) { completion(anisetteError, nil, nil); return; }
        [self.grandSlam submitTwoFactorCode:code userIdentity:self.pendingIdentity idmsToken:self.pendingIdmsToken mode:self.pendingMode completion:^(NSError *error) {
            if (error) { completion(error, nil, nil); return; }
            NSString *username = [self.pendingIdentity componentsSeparatedByString:@"|"].lastObject;
            [self finishAfterCodeAs:username password:self.pendingPassword triesLeft:2 completion:completion];
        }];
    }];
}

/// Apple can take a moment to trust the session after the code, so the follow-up sign-in
/// is tried up to 3 times (0.75 s and 1.5 s apart).
- (void)finishAfterCodeAs:(NSString *)username password:(NSString *)password triesLeft:(NSUInteger)triesLeft completion:(SFAuthResult)completion {
    [self signInAs:username password:password fresh:NO completion:^(NSError *error, NSString *identity, NSString *gsToken) {
        if (!error && identity.length && gsToken.length) {
            [self forgetTwoFactorSession];
            completion(nil, identity, gsToken);
            return;
        }
        if (triesLeft > 0) {
            SFLogEvent(SFLogLevelInfo, @"sign-in · code accepted, finishing (%lu tries left)", (unsigned long)triesLeft);
            NSTimeInterval wait = triesLeft == 2 ? 0.75 : 1.5;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(wait * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                [self finishAfterCodeAs:username password:password triesLeft:triesLeft - 1 completion:completion];
            });
            return;
        }
        [self forgetTwoFactorSession];
        NSMutableDictionary *info = [@{ NSLocalizedDescriptionKey: @"Apple accepted the code but didn't finish the sign-in. Please go back and sign in again." } mutableCopy];
        if (error) info[NSUnderlyingErrorKey] = error;
        completion([NSError errorWithDomain:NSCocoaErrorDomain code:SFInternalLoginPostTwoFactorError userInfo:info], nil, nil);
    }];
}

@end
