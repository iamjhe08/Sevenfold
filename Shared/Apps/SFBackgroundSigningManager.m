//
//  SFBackgroundSigningManager.m
//  Sevenfold
//
//  BY: T4MAG0
//

#import "SFBackgroundSigningManager.h"
#import "SFLocalization.h"
#import "SFApplicationDatabase.h"
#import "SFResources.h"
#import "SFNotificationManager.h"
#import "SFConditions.h"
#import "SFSettings.h"
#import "SFSigningSession.h"
#import "SFLog.h"
#import "AppDelegate.h"

static NSString *const SFAutoRunErrorDomain = @"com.t4mag0.sevenfold.background-signing";

typedef NS_ENUM(NSInteger, SFAutoRunError) {
    SFAutoRunErrorTurnedOff = 1,
    SFAutoRunErrorNotSignedIn = 2,
    SFAutoRunErrorPostponed = 3,
};

@interface SFBackgroundSigningManager ()
@property (nonatomic, strong) NSMutableArray *waiting;   // completion blocks
@property (nonatomic) BOOL running;
@end

@implementation SFBackgroundSigningManager

+ (instancetype)sharedInstance {
    static SFBackgroundSigningManager *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [SFBackgroundSigningManager new]; });
    return shared;
}

- (instancetype)init {
    if ((self = [super init])) {
        _waiting = [NSMutableArray array];
        [[SFApplicationSigning sharedInstance] addSigningUpdatesObserver:self];
    }
    return self;
}

- (void)attemptBackgroundSigningIfNecessary:(void (^)(void))completionHandler {
    [self attemptBackgroundSigningIfNecessaryWithCompletion:^(NSError *error) { if (completionHandler) completionHandler(); }];
}

- (void)attemptBackgroundSigningIfNecessaryWithCompletion:(void (^)(NSError *))completionHandler {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self attemptBackgroundSigningIfNecessaryWithCompletion:completionHandler]; });
        return;
    }
    if (completionHandler) [self.waiting addObject:[completionHandler copy]];
    if (self.running) return;   // joins the pass already under way

    if (![SFResources autoSignEnabled]) {
        [self finish:[self error:SFAutoRunErrorTurnedOff text:SFL(@"Automatic signing is off. Turn it on in Settings and try again.")]];
        return;
    }

    NSString *team = [SFResources getTeamID], *identity = [SFResources getUsername], *token = [SFResources getPassword];
    if (!team.length || !identity.length || !token.length) {
        [[SFNotificationManager sharedInstance] sendNotificationWithTitle:SFL(@"Sign-in needed")
                                                                       body:SFL(@"Open Sevenfold and sign in again so automatic signing can continue.")
                                                             isDebugMessage:NO isUrgentMessage:YES andNotificationID:@"login"];
        [self finish:[self error:SFAutoRunErrorNotSignedIn text:SFL(@"Your saved Apple ID can't be read. Open Sevenfold, sign out and sign in again.")]];
        return;
    }

    // Conditions set in Settings › Schedule (Wi-Fi only, charging, …): try again in 30 minutes.
    NSString *waitReason = [SFConditions reasonToWait];
    if (waitReason) {
        SFLogEvent(SFLogLevelInfo, @"automatic run postponed · %@", waitReason);
        [(AppDelegate *)[UIApplication sharedApplication].delegate requestRetryAfter:30 * 60];
        [self finish:[self error:SFAutoRunErrorPostponed text:waitReason]];
        return;
    }

    self.running = YES;
    // "Sign all apps every run" signs everything; otherwise only apps close to expiring.
    [[SFApplicationSigning sharedInstance] signApplications:![SFSettings signAllEachRun]
                                        thresholdForExpiration:[SFResources expiryThresholdDays]
                                                    withTeamID:team username:identity password:token];
}

- (void)attemptPlugInSigningWithCompletion:(void (^)(NSError *))completionHandler {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self attemptPlugInSigningWithCompletion:completionHandler]; });
        return;
    }
    NSString *team = [SFResources getTeamID], *identity = [SFResources getUsername], *token = [SFResources getPassword];
    NSString *skip = nil;
    if (self.running) skip = @"a run is already under way";
    else if (![SFResources autoSignEnabled] || ![SFSettings signOnPlugIn]) skip = @"turned off";
    else if (!team.length || !identity.length || !token.length) skip = @"not signed in";
    else if ([SFConditions reasonToWait]) skip = [SFConditions reasonToWait];
    else if (![self anyApplicationsNeedingSigning]) skip = @"no app is about to expire";
    if (skip) {
        SFLogEvent(SFLogLevelInfo, @"plugged in · nothing to do (%@)", skip);
        if (completionHandler) completionHandler(nil);
        return;
    }
    SFLogEvent(SFLogLevelInfo, @"plugged in · signing apps that are about to expire");
    if (completionHandler) [self.waiting addObject:[completionHandler copy]];
    [[SFSigningSession shared] markNextRunAutomatic];
    self.running = YES;
    [[SFApplicationSigning sharedInstance] signApplications:YES
                                        thresholdForExpiration:[SFResources expiryThresholdDays]
                                                    withTeamID:team username:identity password:token];
}

- (NSError *)error:(SFAutoRunError)code text:(NSString *)text {
    return [NSError errorWithDomain:SFAutoRunErrorDomain code:code userInfo:@{ NSLocalizedDescriptionKey: text }];
}

- (void)finish:(NSError *)error {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self finish:error]; });
        return;
    }
    self.running = NO;
    NSArray *handlers = [self.waiting copy];
    [self.waiting removeAllObjects];
    for (void (^handler)(NSError *) in handlers) handler(error);
}

- (BOOL)anyApplicationsNeedingSigning {
    NSMutableArray *expiring = [NSMutableArray array];
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:24 * 3600 * [SFResources expiryThresholdDays]];
    [[SFApplicationDatabase sharedInstance] getApplicationsWithExpiryDateBefore:&expiring andAfter:nil date:limit forTeamID:[SFResources getTeamID]];
    return expiring.count > 0;
}

#pragma mark - Signing updates

- (void)applicationSigningDidStart {}
- (void)applicationSigningUpdateProgress:(int)progress forBundleIdentifier:(NSString *)bundleIdentifier {}
- (void)applicationSigningDidEncounterError:(NSError *)error forBundleIdentifier:(NSString *)bundleIdentifier {}

- (void)applicationSigningCompleteWithError:(NSError *)error {
    if (self.running) [self finish:error];
}

@end
