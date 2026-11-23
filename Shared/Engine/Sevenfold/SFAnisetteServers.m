//
//  SFAnisetteServers.m
//  Sevenfold
//

#import "SFAnisetteServers.h"
#import "SFLog.h"

// Matches iloader 2.4.2 (Nov 19, 2026), after the Mac15,7 identity stopped working.
NSString *const SFClientIdentity = @"<MacBookPro13,3> <Mac OS X;10.12.6;16G29> <com.apple.AuthKit/1 (com.apple.akd/1.0)>";
NSString *const SFAkdUserAgent = @"akd/1.0 CFNetwork/811.5.4 Darwin/16.7.0";

static NSString *const SFServersKey = @"sfAnisetteServers";
static NSString *const SFFallbackKey = @"sfAnisetteFallback";
static NSString *const SFStatusKey = @"sfAnisetteStatus";
static NSString *const SFLastGoodKey = @"sfAnisetteLastGood";

@implementation SFAnisetteServers

+ (NSUserDefaults *)defaults {
    return [NSUserDefaults standardUserDefaults];
}

+ (NSArray<NSDictionary *> *)defaultServers {
    return @[
        // Same default as iloader 2.4.2, then the others as fallbacks.
        @{ @"name": @"jkcoxson", @"url": @"https://mac-ani.jkcoxson.com" },
        @{ @"name": @"iloader", @"url": @"https://ani.iloader.app" },
        @{ @"name": @"SideStore", @"url": @"https://new.ani.sidestore.io" },
        @{ @"name": @"StikStore", @"url": @"https://ani3.stikstore.app" },
    ];
}

+ (NSArray<NSDictionary *> *)servers {
    NSArray *stored = [[self defaults] arrayForKey:SFServersKey];
    NSMutableArray *valid = [NSMutableArray array];
    for (id item in stored) {
        if ([item isKindOfClass:[NSDictionary class]] && [item[@"url"] isKindOfClass:[NSString class]] && [item[@"url"] length] > 0)
            [valid addObject:item];
    }
    return valid.count > 0 ? valid : [self defaultServers];
}

+ (void)setServers:(NSArray<NSDictionary *> *)servers {
    [[self defaults] setObject:servers forKey:SFServersKey];
}

+ (BOOL)automaticFallback {
    id value = [[self defaults] objectForKey:SFFallbackKey];
    return value ? [value boolValue] : YES;
}

+ (void)setAutomaticFallback:(BOOL)enabled {
    [[self defaults] setBool:enabled forKey:SFFallbackKey];
}

+ (NSArray<NSString *> *)orderedServerURLs {
    NSMutableArray *urls = [NSMutableArray array];
    for (NSDictionary *server in [self servers])
        [urls addObject:[self normalisedURL:server[@"url"]]];

    if (![self automaticFallback])
        return urls.count > 0 ? @[urls.firstObject] : @[];

    // Start with the server that worked last time, then follow the user's order.
    NSString *lastGood = [self lastGoodServer];
    if (lastGood && [urls containsObject:lastGood]) {
        [urls removeObject:lastGood];
        [urls insertObject:lastGood atIndex:0];
    }
    return urls;
}

+ (NSString *)normalisedURL:(NSString *)url {
    NSString *trimmed = [url stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (![trimmed hasPrefix:@"http://"] && ![trimmed hasPrefix:@"https://"])
        trimmed = [@"https://" stringByAppendingString:trimmed];
    while ([trimmed hasSuffix:@"/"])
        trimmed = [trimmed substringToIndex:trimmed.length - 1];
    return trimmed;
}

+ (void)recordResultForServer:(NSString *)url success:(BOOL)success milliseconds:(NSInteger)ms {
    if (url.length == 0) return;
    @synchronized (self) {
        NSMutableDictionary *statuses = [[self statuses] mutableCopy];
        statuses[url] = @{ @"ok": @(success), @"ms": @(ms), @"date": [NSDate date] };
        [[self defaults] setObject:statuses forKey:SFStatusKey];
        if (success)
            [[self defaults] setObject:url forKey:SFLastGoodKey];
        else if ([[self lastGoodServer] isEqualToString:url])
            [[self defaults] removeObjectForKey:SFLastGoodKey];
    }
}

+ (NSDictionary<NSString *, NSDictionary *> *)statuses {
    NSDictionary *value = [[self defaults] dictionaryForKey:SFStatusKey];
    return value ?: @{};
}

+ (NSString *)lastGoodServer {
    return [[self defaults] stringForKey:SFLastGoodKey];
}

+ (NSString *)nameForServer:(NSString *)url {
    for (NSDictionary *server in [self servers]) {
        if ([[self normalisedURL:server[@"url"]] isEqualToString:url])
            return server[@"name"] ?: [NSURL URLWithString:url].host ?: url;
    }
    return [NSURL URLWithString:url].host ?: url;
}

+ (void)testAllServersWithCompletion:(void (^)(void))completion {
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    configuration.timeoutIntervalForRequest = 8.0;
    configuration.timeoutIntervalForResource = 10.0;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
    dispatch_group_t group = dispatch_group_create();

    for (NSDictionary *server in [self servers]) {
        NSString *base = [self normalisedURL:server[@"url"]];
        NSURL *url = [NSURL URLWithString:[base stringByAppendingString:@"/v3/client_info"]];
        if (!url) continue;
        dispatch_group_enter(group);
        NSDate *start = [NSDate date];
        [[session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            NSInteger ms = (NSInteger)([[NSDate date] timeIntervalSinceDate:start] * 1000);
            NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)response statusCode] : 0;
            BOOL ok = !error && status == 200 && data.length > 0;
            // Record without promoting a server to "last good" just because it answered a test.
            @synchronized (self) {
                NSMutableDictionary *statuses = [[self statuses] mutableCopy];
                statuses[base] = @{ @"ok": @(ok), @"ms": @(ms), @"date": [NSDate date] };
                [[self defaults] setObject:statuses forKey:SFStatusKey];
            }
            SFLogEvent(ok ? SFLogLevelOK : SFLogLevelWarning, @"test %@ · %@ · %ld ms", [self nameForServer:base], ok ? @"online" : (error.localizedDescription ?: [NSString stringWithFormat:@"HTTP %ld", (long)status]), (long)ms);
            dispatch_group_leave(group);
        }] resume];
    }

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        [session finishTasksAndInvalidate];
        if (completion) completion();
    });
}

@end
