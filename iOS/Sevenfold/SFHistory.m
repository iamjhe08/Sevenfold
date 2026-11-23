//
//  SFHistory.m
//  Sevenfold
//

#import "SFHistory.h"

NSString *const SFHistoryDidChangeNotification = @"com.t4mag0.sevenfold/historyChanged";
static NSString *const SFHistoryKey = @"sfRunHistory";
static const NSUInteger SFHistoryLimit = 200;

@implementation SFHistory

+ (NSArray<NSDictionary *> *)runs {
    NSArray *value = [[NSUserDefaults standardUserDefaults] arrayForKey:SFHistoryKey];
    return value ?: @[];
}

+ (void)addRun:(NSDictionary *)run {
    NSMutableArray *runs = [[self runs] mutableCopy];
    [runs insertObject:run atIndex:0];
    if (runs.count > SFHistoryLimit) [runs removeObjectsInRange:NSMakeRange(SFHistoryLimit, runs.count - SFHistoryLimit)];
    [[NSUserDefaults standardUserDefaults] setObject:runs forKey:SFHistoryKey];
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SFHistoryDidChangeNotification object:nil];
    });
}

+ (void)clear {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:SFHistoryKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:SFHistoryDidChangeNotification object:nil];
}

@end
