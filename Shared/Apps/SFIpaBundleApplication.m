//
//  SFIpaBundleApplication.m
//  Sevenfold
//
//  Sevenfold · BY: T4MAG0
//

#import "SFIpaBundleApplication.h"
#import "unzip.h"

@interface SFIpaBundleApplication ()
@property (nonatomic, strong) NSURL *ipaURL;
@property (nonatomic, copy, nullable) NSDictionary *info;      // the app's Info.plist
@property (nonatomic, strong, nullable) UIImage *icon;
@end

@implementation SFIpaBundleApplication

/// Names of all entries in the archive with their uncompressed sizes.
static NSDictionary<NSString *, NSNumber *> *SFZipEntries(unzFile zip) {
    NSMutableDictionary *entries = [NSMutableDictionary dictionary];
    if (unzGoToFirstFile(zip) != UNZ_OK) return entries;
    do {
        unz_file_info64 info;
        char name[1024];
        if (unzGetCurrentFileInfo64(zip, &info, name, sizeof(name), NULL, 0, NULL, 0) == UNZ_OK) {
            NSString *path = [NSString stringWithUTF8String:name];
            if (path) entries[path] = @(info.uncompressed_size);
        }
    } while (unzGoToNextFile(zip) == UNZ_OK);
    return entries;
}

/// Reads one entry fully (up to 16 MB).
static NSData *SFZipRead(unzFile zip, NSString *entry) {
    if (unzGoToFirstFile(zip) != UNZ_OK) return nil;
    do {
        unz_file_info64 info;
        char name[1024];
        if (unzGetCurrentFileInfo64(zip, &info, name, sizeof(name), NULL, 0, NULL, 0) != UNZ_OK) continue;
        if (strcmp(name, entry.UTF8String) != 0) continue;
        if (info.uncompressed_size > 16 * 1024 * 1024 || unzOpenCurrentFile(zip) != UNZ_OK) return nil;
        NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)info.uncompressed_size];
        int read = unzReadCurrentFile(zip, data.mutableBytes, (uint32_t)data.length);
        unzCloseCurrentFile(zip);
        return read == (int)data.length ? data : nil;
    } while (unzGoToNextFile(zip) == UNZ_OK);
    return nil;
}

- (instancetype)initWithIpaURL:(NSURL *)url {
    self = [super initWithApplicationProxy:nil];
    if (!self) return nil;
    _ipaURL = url;

    unzFile zip = unzOpen64(url.path.fileSystemRepresentation);
    if (!zip) return self;
    NSDictionary *entries = SFZipEntries(zip);

    // Payload/<Name>.app/Info.plist (top level of the .app only)
    NSString *appFolder = nil;
    for (NSString *path in entries) {
        NSArray *parts = path.pathComponents;
        if (parts.count == 3 && [parts[0] isEqualToString:@"Payload"] && [parts[1] hasSuffix:@".app"] && [parts[2] isEqualToString:@"Info.plist"]) {
            appFolder = [@"Payload" stringByAppendingPathComponent:parts[1]];
            break;
        }
    }
    if (appFolder) {
        NSData *plist = SFZipRead(zip, [appFolder stringByAppendingPathComponent:@"Info.plist"]);
        id info = plist ? [NSPropertyListSerialization propertyListWithData:plist options:NSPropertyListImmutable format:NULL error:nil] : nil;
        if ([info isKindOfClass:[NSDictionary class]]) _info = info;

        // Icon: the biggest PNG in the .app whose name matches one of the declared icon names.
        NSMutableArray *names = [NSMutableArray array];
        for (NSString *key in @[@"CFBundleIcons", @"CFBundleIcons~ipad"]) {
            id files = _info[key][@"CFBundlePrimaryIcon"][@"CFBundleIconFiles"];
            if ([files isKindOfClass:[NSArray class]]) [names addObjectsFromArray:files];
        }
        id legacy = _info[@"CFBundleIconFiles"];
        if ([legacy isKindOfClass:[NSArray class]]) [names addObjectsFromArray:legacy];
        if ([_info[@"CFBundleIconFile"] isKindOfClass:[NSString class]]) [names addObject:_info[@"CFBundleIconFile"]];
        if (names.count == 0) [names addObject:@"AppIcon"];

        NSString *best = nil; unsigned long long bestSize = 0;
        for (NSString *path in entries) {
            if (![path.stringByDeletingLastPathComponent isEqualToString:appFolder] || ![path.pathExtension.lowercaseString isEqualToString:@"png"]) continue;
            NSString *file = path.lastPathComponent.stringByDeletingPathExtension;
            for (NSString *name in names) {
                NSString *base = name.stringByDeletingPathExtension;
                if (base.length && [file hasPrefix:base] && [entries[path] unsignedLongLongValue] > bestSize) {
                    best = path; bestSize = [entries[path] unsignedLongLongValue];
                }
            }
        }
        if (best) {
            NSData *png = SFZipRead(zip, best);
            if (png) _icon = [UIImage imageWithData:png];   // iOS reads Xcode-optimised PNGs
        }
    }
    unzClose(zip);
    return self;
}

- (NSString *)bundleIdentifier { return self.info[@"CFBundleIdentifier"]; }

- (NSString *)applicationName {
    NSString *name = self.info[@"CFBundleDisplayName"];
    if (name.length == 0) name = self.info[@"CFBundleName"];
    return name.length ? name : self.ipaURL.lastPathComponent.stringByDeletingPathExtension;
}

- (NSString *)applicationVersion { return self.info[@"CFBundleShortVersionString"] ?: self.info[@"CFBundleVersion"]; }

- (NSNumber *)applicationInstalledSize {
    NSNumber *size = [[NSFileManager defaultManager] attributesOfItemAtPath:self.ipaURL.path error:nil][NSFileSize];
    return size;
}

- (UIImage *)applicationIcon { return self.icon; }
- (NSDate *)applicationExpiryDate { return nil; }   // not signed yet
- (NSString *)teamIdentifier { return nil; }
- (BOOL)hasEmbeddedMobileprovision { return NO; }
- (NSURL *)locationOfApplicationOnFilesystem { return self.ipaURL; }

@end
