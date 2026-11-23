//
//  SFLog.h
//  Sevenfold
//
//  A small on-device event log shown in Settings > Diagnostics.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SFLogLevel) {
    SFLogLevelInfo = 0,
    SFLogLevelOK = 1,
    SFLogLevelWarning = 2,
    SFLogLevelError = 3,
};

void SFLogEvent(SFLogLevel level, NSString *format, ...) NS_FORMAT_FUNCTION(2, 3);

@interface SFLog : NSObject
/// Most recent entries first. Each entry: @{ @"date": NSDate, @"level": NSNumber, @"message": NSString }
+ (NSArray<NSDictionary *> *)recentEntries:(NSUInteger)limit;
+ (NSString *)exportText;
+ (void)clear;
@end

NS_ASSUME_NONNULL_END
