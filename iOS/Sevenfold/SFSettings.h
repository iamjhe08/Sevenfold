//
//  SFSettings.h
//  Sevenfold
//
//  All user settings in one place. Values the background service needs are
//  synced to it through SFResources.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const SFSettingsDidChangeNotification;

@interface SFSettings : NSObject

// Schedule
+ (BOOL)firstRunDone;                   // "sfFirstRunDone": welcome guide seen
+ (void)setFirstRunDone:(BOOL)done;
+ (BOOL)automaticSigning;               // "sfAutoSign"
+ (void)setAutomaticSigning:(BOOL)on;
+ (NSInteger)scheduleHour;
+ (NSInteger)scheduleMinute;
+ (void)setScheduleHour:(NSInteger)hour minute:(NSInteger)minute;
/// Signing times, as minutes after midnight, sorted (e.g. @[@0, @720] = 12 AM and 12 PM).
+ (NSArray<NSNumber *> *)scheduleTimes;
+ (void)setScheduleTimes:(NSArray<NSNumber *> *)times;
+ (NSString *)timeStringForMinutes:(NSInteger)minutes;
/// Bit 0 = Sunday … bit 6 = Saturday.
+ (NSInteger)scheduleDays;
+ (void)setScheduleDays:(NSInteger)days;
+ (NSString *)scheduleSummary;          // "Daily, 3:00 AM"
+ (NSDate *)nextScheduledRun;

/// When on, every automatic run signs all apps, not only those close to expiring.
/// Sign up to 3 apps at once (default on).
+ (BOOL)parallelSigning;
+ (void)setParallelSigning:(BOOL)on;
+ (BOOL)signAllEachRun;
+ (void)setSignAllEachRun:(BOOL)on;
+ (int)expiryThresholdDays;             // "sfExpiryThresholdDays"
+ (void)setExpiryThresholdDays:(int)days;

// Conditions
+ (BOOL)onlyOnWiFi;
+ (void)setOnlyOnWiFi:(BOOL)on;
+ (BOOL)onlyWhileCharging;
+ (void)setOnlyWhileCharging:(BOOL)on;
+ (BOOL)retryOnFailure;
+ (void)setRetryOnFailure:(BOOL)on;
+ (BOOL)signInLowPowerMode;
+ (void)setSignInLowPowerMode:(BOOL)on;

// Notifications
+ (BOOL)notifyOnSuccess;
+ (void)setNotifyOnSuccess:(BOOL)on;
+ (BOOL)notifyOnFailure;
+ (void)setNotifyOnFailure:(BOOL)on;
/// Pop-up inside Sevenfold (Dynamic Island style when available).
+ (BOOL)showInAppPopups;
+ (void)setShowInAppPopups:(BOOL)on;
+ (BOOL)notifyOnExpiry;
+ (void)setNotifyOnExpiry:(BOOL)on;

// Per-app
+ (NSArray<NSString *> *)excludedBundleIdentifiers;
+ (BOOL)isExcluded:(NSString *)bundleIdentifier;
+ (void)setExcluded:(BOOL)excluded forBundleIdentifier:(NSString *)bundleIdentifier;

// Account
+ (nullable NSString *)appleIDEmail;

// Profile (stored on this iPhone only)
+ (nullable NSString *)profileName;
+ (void)setProfileName:(nullable NSString *)name;
+ (BOOL)hideEmail;
+ (void)setHideEmail:(BOOL)hide;
/// The Apple ID email as it should be shown: "************" while hidden.
+ (nullable NSString *)displayEmail;
+ (nullable UIImage *)profileImage;
+ (void)setProfileImage:(nullable UIImage *)image;
+ (void)setAppleIDEmail:(nullable NSString *)email;
+ (BOOL)isSignedIn;

// Run history
+ (nullable NSDictionary *)lastRun;      // date, signed, failed, automatic, seconds, message
+ (void)setLastRun:(NSDictionary *)run;

@end

NS_ASSUME_NONNULL_END
