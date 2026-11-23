//
//  SFAppIDBudget.m
//  Sevenfold
//
//  BY: T4MAG0
//

#import "SFAppIDBudget.h"
#import "SFAppleServices.h"
#import "SFResources.h"
#import "SFLog.h"

NSString *const SFAppIDBudgetDidChangeNotification = @"SFAppIDBudgetDidChange";
static NSString *const SFBudgetUsedKey = @"sfAppIDsUsed";
static NSString *const SFBudgetUnlimitedKey = @"sfAppIDsUnlimited";

@interface SFAppIDBudget ()
@property (nonatomic, readwrite) NSInteger used;
@property (nonatomic, readwrite) BOOL unlimited;
@property (nonatomic, strong) NSDate *checkedAt;
@property (nonatomic) BOOL checking;
@end

@implementation SFAppIDBudget

+ (instancetype)shared {
    static SFAppIDBudget *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [SFAppIDBudget new]; });
    return shared;
}

- (instancetype)init {
    if ((self = [super init])) {
        // Last known values, so the card shows a number straight away.
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        id saved = [defaults objectForKey:SFBudgetUsedKey];
        _used = [saved respondsToSelector:@selector(integerValue)] ? [saved integerValue] : -1;
        _unlimited = [defaults boolForKey:SFBudgetUnlimitedKey];
    }
    return self;
}

- (void)publishUsed:(NSInteger)used unlimited:(BOOL)unlimited {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.used = used;
        self.unlimited = unlimited;
        [[NSUserDefaults standardUserDefaults] setObject:@(used) forKey:SFBudgetUsedKey];
        [[NSUserDefaults standardUserDefaults] setBool:unlimited forKey:SFBudgetUnlimitedKey];
        [[NSNotificationCenter defaultCenter] postNotificationName:SFAppIDBudgetDidChangeNotification object:self];
    });
}

static BOOL SFIsPaidTeam(NSDictionary *answer, NSString *team) {
    for (NSDictionary *entry in answer[@"teams"]) {
        if (![entry isKindOfClass:[NSDictionary class]] || ![entry[@"teamId"] isEqual:team]) continue;
        for (NSDictionary *membership in entry[@"memberships"]) {
            if (![membership isKindOfClass:[NSDictionary class]]) continue;
            NSString *name = membership[@"name"], *platform = membership[@"platform"];
            if ([name isKindOfClass:[NSString class]] && [name containsString:@"Apple Developer Program"] && [platform isEqual:@"ios"]) return YES;
        }
    }
    return NO;
}

- (void)refreshForce:(BOOL)force {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.checking) return;
        if (!force && self.checkedAt && -self.checkedAt.timeIntervalSinceNow < 300) return;
        NSString *identity = [SFResources getUsername], *token = [SFResources getPassword], *team = [SFResources getTeamID];
        if (!identity.length || !token.length || !team.length) return;
        self.checking = YES;

        SFAppleServices *apple = [SFAppleServices sharedInstance];
        void (^done)(void) = ^{ dispatch_async(dispatch_get_main_queue(), ^{ self.checking = NO; }); };
        [apple ensureSessionWithIdentity:identity gsToken:token andCompletionHandler:^(NSError *sessionError, NSDictionary *unused) {
            [apple listTeamsWithCompletionHandler:^(NSError *teamsError, NSDictionary *teams) {
                if (!teamsError && SFIsPaidTeam(teams, team)) {
                    self.checkedAt = [NSDate date];
                    [self publishUsed:0 unlimited:YES];
                    done();
                    return;
                }
                [apple listAllApplicationsForTeamID:team systemType:SFSystemTypeiOS withCompletionHandler:^(NSError *error, NSDictionary *answer) {
                    NSArray *appIDs = [answer[@"appIds"] isKindOfClass:[NSArray class]] ? answer[@"appIds"] : nil;
                    if (error || !appIDs) {
                        SFLogEvent(SFLogLevelInfo, @"App IDs · couldn't check this week's count: %@", error.localizedDescription ?: @"no list");
                        done();
                        return;
                    }
                    NSInteger active = 0;
                    for (NSDictionary *appID in appIDs) {
                        id expires = [appID isKindOfClass:[NSDictionary class]] ? appID[@"expirationDate"] : nil;
                        if ([expires isKindOfClass:[NSString class]]) {
                            NSISO8601DateFormatter *iso = [NSISO8601DateFormatter new];
                            expires = [iso dateFromString:expires];
                        }
                        if ([expires isKindOfClass:[NSDate class]] && [expires timeIntervalSinceNow] > 0) active++;
                    }
                    if (active == 0 && appIDs.count) {
                        NSDictionary *first = [appIDs.firstObject isKindOfClass:[NSDictionary class]] ? appIDs.firstObject : @{};
                        SFLogEvent(SFLogLevelInfo, @"App IDs · %lu listed but none with an expiry date (fields: %@)", (unsigned long)appIDs.count, [first.allKeys componentsJoinedByString:@", "]);
                    }
                    self.checkedAt = [NSDate date];
                    SFLogEvent(SFLogLevelInfo, @"App IDs · %ld of 10 in use this week", (long)active);
                    [self publishUsed:MIN(active, 10) unlimited:NO];
                    done();
                }];
            }];
        }];
    });
}

@end
