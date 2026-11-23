//
//  SFDevice.m
//  Sevenfold
//

#import "SFDevice.h"
#include <sys/sysctl.h>

static NSString *const SFCertificatePrefix = @"Sevenfold · ";

@implementation SFDevice

+ (NSString *)hardwareIdentifier {
    size_t size = 0;
    sysctlbyname("hw.machine", NULL, &size, NULL, 0);
    if (size == 0) return @"iPhone";
    char *machine = malloc(size);
    sysctlbyname("hw.machine", machine, &size, NULL, 0);
    NSString *identifier = [NSString stringWithUTF8String:machine] ?: @"iPhone";
    free(machine);
    return identifier;
}

+ (NSString *)modelName {
    return [self modelNameForIdentifier:[self hardwareIdentifier]];
}

+ (NSString *)modelNameForIdentifier:(NSString *)identifier {
    static NSDictionary *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = @{
            @"iPhone10,1": @"iPhone 8", @"iPhone10,4": @"iPhone 8",
            @"iPhone10,2": @"iPhone 8 Plus", @"iPhone10,5": @"iPhone 8 Plus",
            @"iPhone10,3": @"iPhone X", @"iPhone10,6": @"iPhone X",
            @"iPhone11,2": @"iPhone XS", @"iPhone11,4": @"iPhone XS Max", @"iPhone11,6": @"iPhone XS Max",
            @"iPhone11,8": @"iPhone XR",
            @"iPhone12,1": @"iPhone 11", @"iPhone12,3": @"iPhone 11 Pro", @"iPhone12,5": @"iPhone 11 Pro Max",
            @"iPhone12,8": @"iPhone SE (2nd gen)",
            @"iPhone13,1": @"iPhone 12 mini", @"iPhone13,2": @"iPhone 12",
            @"iPhone13,3": @"iPhone 12 Pro", @"iPhone13,4": @"iPhone 12 Pro Max",
            @"iPhone14,4": @"iPhone 13 mini", @"iPhone14,5": @"iPhone 13",
            @"iPhone14,2": @"iPhone 13 Pro", @"iPhone14,3": @"iPhone 13 Pro Max",
            @"iPhone14,6": @"iPhone SE (3rd gen)",
            @"iPhone14,7": @"iPhone 14", @"iPhone14,8": @"iPhone 14 Plus",
            @"iPhone15,2": @"iPhone 14 Pro", @"iPhone15,3": @"iPhone 14 Pro Max",
            @"iPhone15,4": @"iPhone 15", @"iPhone15,5": @"iPhone 15 Plus",
            @"iPhone16,1": @"iPhone 15 Pro", @"iPhone16,2": @"iPhone 15 Pro Max",
            @"iPhone17,3": @"iPhone 16", @"iPhone17,4": @"iPhone 16 Plus",
            @"iPhone17,1": @"iPhone 16 Pro", @"iPhone17,2": @"iPhone 16 Pro Max",
            @"iPhone17,5": @"iPhone 16e",
            @"iPhone18,3": @"iPhone 17", @"iPhone18,4": @"iPhone Air",
            @"iPhone18,1": @"iPhone 17 Pro", @"iPhone18,2": @"iPhone 17 Pro Max",
        };
    });
    NSString *name = names[identifier];
    if (name) return name;
    if ([identifier hasPrefix:@"iPad"]) return [NSString stringWithFormat:@"iPad (%@)", identifier];
    return identifier.length > 0 ? identifier : @"iPhone";
}

+ (NSString *)certificateMachineName {
    return [SFCertificatePrefix stringByAppendingString:[self modelName]];
}

+ (NSString *)modelFromCertificateMachineName:(NSString *)machineName {
    if (![machineName isKindOfClass:[NSString class]]) return nil;
    if (![machineName hasPrefix:SFCertificatePrefix]) return nil;
    return [machineName substringFromIndex:SFCertificatePrefix.length];
}

@end
