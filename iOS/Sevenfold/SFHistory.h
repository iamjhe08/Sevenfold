//
//  SFHistory.h
//  Sevenfold
//
//  Saved record of signing runs, shown in the History tab.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const SFHistoryDidChangeNotification;

@interface SFHistory : NSObject
/// Each run: date, automatic, seconds, signed, failed, nothingToDo, error (optional),
/// apps: [ { name, bundleIdentifier, ok, reason, error } ]. Newest first.
+ (NSArray<NSDictionary *> *)runs;
+ (void)addRun:(NSDictionary *)run;
+ (void)clear;
@end

NS_ASSUME_NONNULL_END
