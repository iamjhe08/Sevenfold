//
//  SFNetworkAccess.m
//  Sevenfold
//

#import "SFNetworkAccess.h"
#import "SFLog.h"
#include <dlfcn.h>

typedef const void *SFCTServerConnectionRef;
typedef SFCTServerConnectionRef (*SFCTCreate)(CFAllocatorRef, void *, void *);
typedef int (*SFCTSetPolicy)(SFCTServerConnectionRef, CFStringRef, CFDictionaryRef);

@implementation SFNetworkAccess

+ (BOOL)allowWiFiAndCellular {
    void *handle = dlopen("/System/Library/Frameworks/CoreTelephony.framework/CoreTelephony", RTLD_NOW);
    if (!handle) {
        SFLogEvent(SFLogLevelWarning, @"network access · CoreTelephony unavailable");
        return NO;
    }
    SFCTCreate create = (SFCTCreate)dlsym(handle, "_CTServerConnectionCreate");
    SFCTSetPolicy setPolicy = (SFCTSetPolicy)dlsym(handle, "_CTServerConnectionSetCellularUsagePolicy");
    CFStringRef *cellularKey = (CFStringRef *)dlsym(handle, "kCTCellularDataUsagePolicy");
    CFStringRef *wifiKey = (CFStringRef *)dlsym(handle, "kCTWiFiDataUsagePolicy");
    CFStringRef *alwaysAllow = (CFStringRef *)dlsym(handle, "kCTCellularDataUsagePolicyAlwaysAllow");
    if (!create || !setPolicy || !cellularKey || !wifiKey || !alwaysAllow) {
        SFLogEvent(SFLogLevelWarning, @"network access · policy API not found");
        return NO;
    }

    SFCTServerConnectionRef connection = create(kCFAllocatorDefault, NULL, NULL);
    if (!connection) {
        SFLogEvent(SFLogLevelWarning, @"network access · no CommCenter connection");
        return NO;
    }
    NSDictionary *policy = @{
        (__bridge NSString *)*cellularKey: (__bridge NSString *)*alwaysAllow,
        (__bridge NSString *)*wifiKey: (__bridge NSString *)*alwaysAllow,
    };
    NSString *bundleID = [NSBundle mainBundle].bundleIdentifier ?: @"com.t4mag0.sevenfold";
    int result = setPolicy(connection, (__bridge CFStringRef)bundleID, (__bridge CFDictionaryRef)policy);
    CFRelease(connection);
    SFLogEvent(result == 0 ? SFLogLevelOK : SFLogLevelWarning, @"network access · WLAN & cellular %@ (%d)", result == 0 ? @"allowed" : @"not set", result);
    return result == 0;
}

@end
