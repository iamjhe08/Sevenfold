//
//  SFAppIDBudget.h
//  Sevenfold
//
//  BY: T4MAG0
//
//  How many of a free Apple ID's 10 weekly App IDs are in use. Each App ID a free
//  account creates lasts 7 days, so the ones not yet expired are the ones that count.
//

#import <Foundation/Foundation.h>

extern NSString *const SFAppIDBudgetDidChangeNotification;

@interface SFAppIDBudget : NSObject

+ (instancetype)shared;

/// App IDs in use this week, or -1 when not known yet.
@property (nonatomic, readonly) NSInteger used;
/// When in-use App IDs free up: @{@"date": NSDate (start of day), @"count": NSNumber}, soonest first.
@property (nonatomic, readonly, copy) NSArray<NSDictionary *> *freeUps;
/// Paid developer accounts have no weekly limit: the meter is hidden.
@property (nonatomic, readonly) BOOL unlimited;

/// Asks Apple again (at most every 5 minutes unless forced).
- (void)refreshForce:(BOOL)force;

@end
