//
//  SFApplicationDatabase.h
//  Sevenfold
//
//  Sevenfold · BY: T4MAG0
//
//  Finds the sideloaded apps on this iPhone.
//

#import <Foundation/Foundation.h>

@class SFApplication;

NS_ASSUME_NONNULL_BEGIN

@interface SFApplicationDatabase : NSObject

+ (instancetype)sharedInstance;

/// Installed apps signed by the given team.
- (NSArray<SFApplication *> *)getAllApplicationsForTeamID:(NSString *)teamID;

/// The installed app with exactly this bundle ID (nil if not installed).
- (nullable SFApplication *)getApplicationWithBundleIdentifier:(NSString *)bundleIdentifier;

/// Exact match first, then a sideloaded app whose bundle ID contains it
/// (signed apps can carry a team suffix like "com.example.app.ABCDE12345").
- (nullable SFApplication *)getApplicationContainsBundleIdentifier:(NSString *)bundleIdentifier;

/// Splits the team's apps into those expiring before `date` and the rest. Apps without a
/// readable profile count as expiring. `afterApplications` may be NULL.
- (BOOL)getApplicationsWithExpiryDateBefore:(NSMutableArray * _Nullable * _Nullable)beforeApplications
                                   andAfter:(NSMutableArray * _Nullable * _Nullable)afterApplications
                                       date:(NSDate *)cutoffDate
                                  forTeamID:(NSString *)teamID;

@end

NS_ASSUME_NONNULL_END
