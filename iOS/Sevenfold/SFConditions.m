//
//  SFConditions.m
//  Sevenfold
//

#import "SFConditions.h"
#import "SFLocalization.h"
#import "SFSettings.h"
#import <UIKit/UIKit.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <netinet/in.h>

@implementation SFConditions

+ (BOOL)isOnWiFi {
    struct sockaddr_in zero;
    memset(&zero, 0, sizeof(zero));
    zero.sin_len = sizeof(zero);
    zero.sin_family = AF_INET;
    SCNetworkReachabilityRef reachability = SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, (const struct sockaddr *)&zero);
    if (!reachability) return NO;
    SCNetworkReachabilityFlags flags = 0;
    BOOL ok = SCNetworkReachabilityGetFlags(reachability, &flags);
    CFRelease(reachability);
    if (!ok || !(flags & kSCNetworkReachabilityFlagsReachable)) return NO;
    return !(flags & kSCNetworkReachabilityFlagsIsWWAN);
}

+ (BOOL)isCharging {
    UIDevice *device = [UIDevice currentDevice];
    BOOL wasMonitoring = device.batteryMonitoringEnabled;
    device.batteryMonitoringEnabled = YES;
    UIDeviceBatteryState state = device.batteryState;
    device.batteryMonitoringEnabled = wasMonitoring;
    return state == UIDeviceBatteryStateCharging || state == UIDeviceBatteryStateFull;
}

+ (NSString *)reasonToWait {
    if ([SFSettings onlyOnWiFi] && ![self isOnWiFi]) return SFL(@"Waiting for Wi-Fi");
    if ([SFSettings onlyWhileCharging] && ![self isCharging]) return SFL(@"Waiting for the iPhone to charge");
    return nil;
}

@end
