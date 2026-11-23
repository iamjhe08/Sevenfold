//
//  SFConditions.h
//  Sevenfold
//
//  Checks the schedule's conditions (Wi-Fi only, charging only) before an
//  automatic run.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SFConditions : NSObject
+ (BOOL)isOnWiFi;
+ (BOOL)isCharging;
/// nil when an automatic run may go ahead, else the reason it's waiting.
+ (nullable NSString *)reasonToWait;
@end

NS_ASSUME_NONNULL_END
