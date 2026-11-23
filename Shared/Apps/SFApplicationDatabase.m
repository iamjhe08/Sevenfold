//
//  SFApplicationDatabase.m
//  Sevenfold
//
//  Sevenfold · BY: T4MAG0
//

#import "SFApplicationDatabase.h"
#import "SFApplication.h"

static id SFWorkspace(void) {
    Class workspace = NSClassFromString(@"LSApplicationWorkspace");
    SEL shared = NSSelectorFromString(@"defaultWorkspace");
    if (![workspace respondsToSelector:shared]) return nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    return [workspace performSelector:shared];
#pragma clang diagnostic pop
}

static id SFRecordValue(id record, NSString *key) {
    @try { return [record valueForKey:key]; } @catch (NSException *e) { return nil; }
}

@implementation SFApplicationDatabase

+ (instancetype)sharedInstance {
    static SFApplicationDatabase *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [self new]; });
    return shared;
}

/// Installed user apps (not built-in or jailbreak apps), as LaunchServices records.
- (NSArray *)userApplicationRecords {
    id workspace = SFWorkspace();
    NSArray *records = nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    for (NSString *name in @[@"allInstalledApplications", @"allApplications"]) {
        SEL selector = NSSelectorFromString(name);
        if ([workspace respondsToSelector:selector]) { records = [workspace performSelector:selector]; break; }
    }
#pragma clang diagnostic pop
    NSMutableArray *result = [NSMutableArray array];
    for (id record in records) {
        NSString *type = SFRecordValue(record, @"applicationType");
        NSURL *url = SFRecordValue(record, @"bundleURL");
        BOOL userApp = [type isEqualToString:@"User"] || [url.path containsString:@"/Containers/Bundle/Application/"];
        id installed = SFRecordValue(record, @"isInstalled");
        // The list can be stale in a long-running process: also check the app's folder is still there.
        if (userApp && url && (!installed || [installed boolValue]) && [[NSFileManager defaultManager] fileExistsAtPath:url.path])
            [result addObject:record];
    }
    return result;
}

- (NSArray<SFApplication *> *)getAllApplicationsForTeamID:(NSString *)teamID {
    if (teamID.length == 0) return @[];
    NSMutableArray *apps = [NSMutableArray array];
    for (id record in [self userApplicationRecords]) {
        // The signing team iOS recorded for the app; the profile is the backup.
        NSString *team = SFRecordValue(record, @"teamID");
        SFApplication *app = [[SFApplication alloc] initWithApplicationProxy:record];
        if (![team isKindOfClass:[NSString class]] || team.length == 0) team = app.teamIdentifier;
        if ([team isEqualToString:teamID]) [apps addObject:app];
    }
    return apps;
}

- (SFApplication *)getApplicationWithBundleIdentifier:(NSString *)bundleIdentifier {
    if (bundleIdentifier.length == 0) return nil;
    Class proxyClass = NSClassFromString(@"LSApplicationProxy");
    SEL lookup = NSSelectorFromString(@"applicationProxyForIdentifier:");
    if (![proxyClass respondsToSelector:lookup]) return nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id record = [proxyClass performSelector:lookup withObject:bundleIdentifier];
#pragma clang diagnostic pop
    NSURL *url = record ? SFRecordValue(record, @"bundleURL") : nil;
    if (!url || ![[NSFileManager defaultManager] fileExistsAtPath:url.path]) return nil;
    return [[SFApplication alloc] initWithApplicationProxy:record];
}

- (SFApplication *)getApplicationContainsBundleIdentifier:(NSString *)bundleIdentifier {
    SFApplication *exact = [self getApplicationWithBundleIdentifier:bundleIdentifier];
    if (exact || bundleIdentifier.length == 0) return exact;
    for (id record in [self userApplicationRecords]) {
        NSString *identifier = SFRecordValue(record, @"applicationIdentifier") ?: SFRecordValue(record, @"bundleIdentifier");
        if ([identifier containsString:bundleIdentifier]) return [[SFApplication alloc] initWithApplicationProxy:record];
    }
    return nil;
}

- (BOOL)getApplicationsWithExpiryDateBefore:(NSMutableArray **)beforeApplications andAfter:(NSMutableArray **)afterApplications date:(NSDate *)cutoffDate forTeamID:(NSString *)teamID {
    if (!beforeApplications) return NO;
    if (!*beforeApplications) *beforeApplications = [NSMutableArray array];
    if (afterApplications && !*afterApplications) *afterApplications = [NSMutableArray array];
    for (SFApplication *app in [self getAllApplicationsForTeamID:teamID]) {
        NSDate *expiry = app.applicationExpiryDate;
        if (!expiry || [expiry compare:cutoffDate] == NSOrderedAscending) [*beforeApplications addObject:app];
        else if (afterApplications) [*afterApplications addObject:app];
    }
    return YES;
}

@end
