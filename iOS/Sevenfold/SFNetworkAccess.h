//
//  SFNetworkAccess.h
//  Sevenfold
//
//  China-variant iPhones block network access for apps until it's allowed.
//  Apps installed by a jailbreak never get the system prompt, so Sevenfold
//  sets its own policy to "WLAN & Cellular Data" through CoreTelephony.
//

#import <Foundation/Foundation.h>

@interface SFNetworkAccess : NSObject
/// Returns YES if the policy call succeeded.
+ (BOOL)allowWiFiAndCellular;
@end
