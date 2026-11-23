//
//  SFApplication.m
//  Sevenfold
//
//  Sevenfold · BY: T4MAG0
//

#import "SFApplication.h"
#import <objc/message.h>

@interface SFApplication ()
@property (nonatomic, strong) id record;               // LSApplicationProxy
@property (nonatomic, strong, nullable) NSDictionary *profileCache;
@property (nonatomic) BOOL profileLoaded;
@end

@implementation SFApplication

+ (NSDictionary *)provisioningProfileAtPath:(NSString *)path {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data.length == 0) return nil;
    // The file is a signed (CMS) envelope with the XML plist stored inside as plain bytes.
    NSData *start = [@"<?xml" dataUsingEncoding:NSASCIIStringEncoding];
    NSData *end = [@"</plist>" dataUsingEncoding:NSASCIIStringEncoding];
    NSRange from = [data rangeOfData:start options:0 range:NSMakeRange(0, data.length)];
    if (from.location == NSNotFound) return nil;
    NSRange to = [data rangeOfData:end options:NSDataSearchBackwards range:NSMakeRange(from.location, data.length - from.location)];
    if (to.location == NSNotFound) return nil;
    NSData *xml = [data subdataWithRange:NSMakeRange(from.location, NSMaxRange(to) - from.location)];
    id plist = [NSPropertyListSerialization propertyListWithData:xml options:NSPropertyListImmutable format:NULL error:nil];
    return [plist isKindOfClass:[NSDictionary class]] ? plist : nil;
}

- (instancetype)initWithApplicationProxy:(id)proxy {
    self = [super init];
    if (self) _record = proxy;
    return self;
}

- (id)recordValue:(NSString *)key {
    if (!self.record) return nil;
    @try { return [self.record valueForKey:key]; } @catch (NSException *e) { return nil; }
}

- (NSString *)bundleIdentifier {
    return [self recordValue:@"applicationIdentifier"] ?: [self recordValue:@"bundleIdentifier"];
}

- (NSString *)applicationName {
    NSString *name = [self recordValue:@"localizedName"];
    return name.length ? name : [self recordValue:@"itemName"] ?: self.bundleIdentifier;
}

- (NSString *)applicationVersion {
    return [self recordValue:@"shortVersionString"] ?: [self recordValue:@"bundleVersion"];
}

- (NSNumber *)applicationInstalledSize {
    id usage = [self recordValue:@"diskUsage"];
    if (usage) {
        @try { id size = [usage valueForKey:@"staticUsage"]; if ([size isKindOfClass:[NSNumber class]]) return size; } @catch (NSException *e) {}
    }
    id size = [self recordValue:@"staticDiskUsage"];
    return [size isKindOfClass:[NSNumber class]] ? size : nil;
}

- (UIImage *)applicationIcon {
    NSString *bundleID = self.bundleIdentifier;
    if (!bundleID) return nil;
    // UIKit can render any installed app's Home Screen icon by bundle ID.
    SEL selector = NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:");
    if (![UIImage respondsToSelector:selector]) return nil;
    UIImage *(*render)(id, SEL, NSString *, int, CGFloat) = (void *)objc_msgSend;
    return render([UIImage class], selector, bundleID, 2, [UIScreen mainScreen].scale);
}

- (NSURL *)locationOfApplicationOnFilesystem {
    id url = [self recordValue:@"bundleURL"];
    return [url isKindOfClass:[NSURL class]] ? url : nil;
}

- (NSDictionary *)readProfile {
    NSString *bundlePath = self.locationOfApplicationOnFilesystem.path;
    return bundlePath ? [SFApplication provisioningProfileAtPath:[bundlePath stringByAppendingPathComponent:@"embedded.mobileprovision"]] : nil;
}

- (NSDictionary *)profile {
    if (!self.profileLoaded) {
        self.profileLoaded = YES;
        self.profileCache = [self readProfile];
        // Reinstalling moves the app to a new folder, so the old record points at a path
        // that no longer exists. Ask the system for the app's current record and try again.
        NSString *bundleID = self.bundleIdentifier;
        Class proxyClass = NSClassFromString(@"LSApplicationProxy");
        SEL lookup = NSSelectorFromString(@"applicationProxyForIdentifier:");
        if (!self.profileCache && bundleID && [proxyClass respondsToSelector:lookup]) {
            id (*find)(id, SEL, NSString *) = (void *)objc_msgSend;
            id fresh = find(proxyClass, lookup, bundleID);
            if (fresh) { self.record = fresh; self.profileCache = [self readProfile]; }
        }
    }
    return self.profileCache;
}

- (BOOL)hasEmbeddedMobileprovision {
    NSString *bundlePath = self.locationOfApplicationOnFilesystem.path;
    return bundlePath && [[NSFileManager defaultManager] fileExistsAtPath:[bundlePath stringByAppendingPathComponent:@"embedded.mobileprovision"]];
}

- (NSDate *)applicationExpiryDate {
    // Read fresh each time: signing replaces the profile on disk.
    self.profileLoaded = NO;
    id date = self.profile[@"ExpirationDate"];
    NSString *bundleID = self.bundleIdentifier;
    // While iOS swaps the app's files during an install the profile can't be read for a moment.
    // Keep showing the last date we read instead of flashing "Expired".
    static NSMutableDictionary<NSString *, NSDate *> *lastKnown;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lastKnown = [NSMutableDictionary dictionary]; });
    @synchronized (lastKnown) {
        if ([date isKindOfClass:[NSDate class]]) {
            if (bundleID) lastKnown[bundleID] = date;
            return date;
        }
        return bundleID ? lastKnown[bundleID] : nil;
    }
}

- (NSString *)teamIdentifier {
    NSDictionary *profile = self.profile;
    id teams = profile[@"TeamIdentifier"];
    if ([teams isKindOfClass:[NSArray class]] && [teams count] > 0) return [teams firstObject];
    id team = profile[@"Entitlements"][@"com.apple.developer.team-identifier"];
    return [team isKindOfClass:[NSString class]] ? team : nil;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<SFApplication %@ (%@)>", self.bundleIdentifier, self.applicationName];
}

@end
