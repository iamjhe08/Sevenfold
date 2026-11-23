//
//  SFSettings.m
//  Sevenfold
//

#import "SFSettings.h"
#import "SFLocalization.h"
#import "SFResources.h"

NSString *const SFSettingsDidChangeNotification = @"com.t4mag0.sevenfold/settingsChanged";

@implementation SFSettings

+ (id)value:(NSString *)key {
    return [SFResources preferenceValueForKey:key];
}

+ (BOOL)bool:(NSString *)key fallback:(BOOL)fallback {
    id value = [self value:key];
    return value ? [value boolValue] : fallback;
}

+ (NSInteger)integer:(NSString *)key fallback:(NSInteger)fallback {
    id value = [self value:key];
    return value ? [value integerValue] : fallback;
}

/// Saves and tells the background service.
+ (void)set:(id)value key:(NSString *)key {
    [SFResources setPreferenceValue:value forKey:key withNotification:SFSettingsDidChangeNotification];
}

/// Saves locally only (the background service doesn't need it).
+ (void)setLocal:(id)value key:(NSString *)key {
    if (value) [[NSUserDefaults standardUserDefaults] setObject:value forKey:key];
    else [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
    [[NSNotificationCenter defaultCenter] postNotificationName:SFSettingsDidChangeNotification object:nil];
}

+ (BOOL)firstRunDone { return [self bool:@"sfFirstRunDone" fallback:NO]; }
+ (void)setFirstRunDone:(BOOL)done { [self set:@(done) key:@"sfFirstRunDone"]; }
+ (BOOL)automaticSigning { return [self bool:@"sfAutoSign" fallback:YES]; }
+ (void)setAutomaticSigning:(BOOL)on { [self set:@(on) key:@"sfAutoSign"]; }

+ (NSInteger)scheduleHour { return MIN(MAX([self integer:@"sfScheduleHour" fallback:3], 0), 23); }
+ (NSInteger)scheduleMinute { return MIN(MAX([self integer:@"sfScheduleMinute" fallback:0], 0), 59); }
+ (void)setScheduleHour:(NSInteger)hour minute:(NSInteger)minute {
    [[NSUserDefaults standardUserDefaults] setObject:@(hour) forKey:@"sfScheduleHour"];
    [self set:@(minute) key:@"sfScheduleMinute"];
    // Make sure the hour reaches the shared preferences too.
    [self set:@(hour) key:@"sfScheduleHour"];
}

+ (NSArray<NSNumber *> *)scheduleTimes {
    NSMutableArray *times = [NSMutableArray array];
    id stored = [self value:@"sfScheduleTimes"];
    if ([stored isKindOfClass:[NSArray class]]) {
        for (id value in stored) {
            if (![value respondsToSelector:@selector(integerValue)]) continue;
            NSInteger minutes = [value integerValue];
            if (minutes >= 0 && minutes < 24 * 60 && ![times containsObject:@(minutes)]) [times addObject:@(minutes)];
        }
    }
    if (times.count == 0) [times addObject:@([self scheduleHour] * 60 + [self scheduleMinute])];
    return [times sortedArrayUsingSelector:@selector(compare:)];
}

+ (void)setScheduleTimes:(NSArray<NSNumber *> *)times {
    NSMutableArray *clean = [NSMutableArray array];
    for (NSNumber *time in times) {
        NSInteger minutes = time.integerValue;
        if (minutes >= 0 && minutes < 24 * 60 && ![clean containsObject:@(minutes)]) [clean addObject:@(minutes)];
    }
    if (clean.count == 0) return;
    [clean sortUsingSelector:@selector(compare:)];
    // Keep the single-time keys in step for older code paths.
    NSInteger first = [clean.firstObject integerValue];
    [SFResources setPreferenceValue:@(first / 60) forKey:@"sfScheduleHour" withNotification:nil];
    [SFResources setPreferenceValue:@(first % 60) forKey:@"sfScheduleMinute" withNotification:nil];
    [self set:clean key:@"sfScheduleTimes"];
}

+ (NSString *)timeStringForMinutes:(NSInteger)minutes {
    NSDate *date = [[NSCalendar currentCalendar] dateBySettingHour:minutes / 60 minute:minutes % 60 second:0 ofDate:[NSDate date] options:0];
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateStyle = NSDateFormatterNoStyle;
    formatter.timeStyle = NSDateFormatterShortStyle;
    return [formatter stringFromDate:date];
}

+ (NSInteger)scheduleDays {
    NSInteger days = [self integer:@"sfScheduleDays" fallback:127] & 127;
    return days == 0 ? 127 : days;
}
+ (void)setScheduleDays:(NSInteger)days { [self set:@(days & 127) key:@"sfScheduleDays"]; }

+ (NSString *)timeString {
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDate *date = [calendar dateBySettingHour:[self scheduleHour] minute:[self scheduleMinute] second:0 ofDate:[NSDate date] options:0];
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateStyle = NSDateFormatterNoStyle;
    formatter.timeStyle = NSDateFormatterShortStyle;
    return [formatter stringFromDate:date];
}

+ (NSString *)scheduleSummary {
    if (![self automaticSigning]) return SFL(@"Off");
    NSInteger days = [self scheduleDays];
    NSString *dayText;
    if (days == 127) dayText = SFL(@"Daily");
    else if (days == 0b0111110) dayText = SFL(@"Weekdays");
    else if (days == 0b1000001) dayText = SFL(@"Weekends");
    else {
        NSArray *names = @[SFL(@"Sun"), SFL(@"Mon"), SFL(@"Tue"), SFL(@"Wed"), SFL(@"Thu"), SFL(@"Fri"), SFL(@"Sat")];
        NSMutableArray *picked = [NSMutableArray array];
        for (NSInteger i = 1; i <= 7; i++) {
            NSInteger d = i % 7; // Monday first
            if (days & (1 << d)) [picked addObject:names[d]];
        }
        dayText = [picked componentsJoinedByString:@" "];
    }
    NSArray *times = [self scheduleTimes];
    NSString *timeText;
    if (times.count <= 2) {
        NSMutableArray *labels = [NSMutableArray array];
        for (NSNumber *t in times) [labels addObject:[self timeStringForMinutes:t.integerValue]];
        timeText = [labels componentsJoinedByString:@" & "];
    } else {
        timeText = [NSString stringWithFormat:SFL(@"%lu times"), (unsigned long)times.count];
    }
    return [NSString stringWithFormat:@"%@, %@", dayText, timeText];
}

+ (NSDate *)nextScheduledRun {
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDate *now = [NSDate date];
    NSDate *startOfDay = [calendar startOfDayForDate:now];
    NSInteger days = [self scheduleDays];
    NSArray *times = [self scheduleTimes];
    for (NSInteger offset = 0; offset <= 7; offset++) {
        NSDate *day = [calendar dateByAddingUnit:NSCalendarUnitDay value:offset toDate:startOfDay options:0];
        NSInteger weekday = [calendar component:NSCalendarUnitWeekday fromDate:day] - 1;
        if (!(days & (1 << weekday))) continue;
        for (NSNumber *t in times) {
            NSInteger minutes = t.integerValue;
            NSDate *candidate = [calendar dateBySettingHour:minutes / 60 minute:minutes % 60 second:0 ofDate:day options:0];
            if ([candidate timeIntervalSinceDate:now] > 30) return candidate;
        }
    }
    return [now dateByAddingTimeInterval:24 * 3600];
}

+ (BOOL)parallelSigning { return [self bool:@"sfParallelSigning" fallback:YES]; }
+ (void)setParallelSigning:(BOOL)on { [self set:@(on) key:@"sfParallelSigning"]; }

+ (BOOL)signAllEachRun { return YES; } // Scheduled runs always sign every app.
+ (void)setSignAllEachRun:(BOOL)on { [self set:@(on) key:@"sfSignAllEachRun"]; }

+ (int)expiryThresholdDays { return [SFResources expiryThresholdDays]; }
+ (void)setExpiryThresholdDays:(int)days { [self set:@(MIN(MAX(days, 1), 6)) key:@"sfExpiryThresholdDays"]; }

+ (BOOL)onlyOnWiFi { return [self bool:@"sfOnlyWiFi" fallback:NO]; }
+ (void)setOnlyOnWiFi:(BOOL)on { [self set:@(on) key:@"sfOnlyWiFi"]; }
+ (BOOL)onlyWhileCharging { return [self bool:@"sfOnlyCharging" fallback:NO]; }
+ (void)setOnlyWhileCharging:(BOOL)on { [self set:@(on) key:@"sfOnlyCharging"]; }
+ (BOOL)retryOnFailure { return [self bool:@"sfRetry" fallback:YES]; }
+ (void)setRetryOnFailure:(BOOL)on { [self set:@(on) key:@"sfRetry"]; }
+ (BOOL)signInLowPowerMode { return [SFResources lowPowerSigningAllowed]; }
+ (void)setSignInLowPowerMode:(BOOL)on { [self set:@(on) key:@"sfSignInLowPower"]; }

+ (BOOL)notifyOnSuccess { return [self bool:@"sfNotifySuccess" fallback:YES]; }
+ (void)setNotifyOnSuccess:(BOOL)on { [self setLocal:@(on) key:@"sfNotifySuccess"]; }
+ (BOOL)notifyOnFailure { return [self bool:@"sfNotifyFailure" fallback:YES]; }
+ (void)setNotifyOnFailure:(BOOL)on { [self setLocal:@(on) key:@"sfNotifyFailure"]; }
+ (BOOL)showInAppPopups { return [self bool:@"sfInAppPopups" fallback:YES]; }
+ (void)setShowInAppPopups:(BOOL)on { [self setLocal:@(on) key:@"sfInAppPopups"]; }
+ (BOOL)notifyOnExpiry { return [self bool:@"sfNotifyExpiry" fallback:YES]; }
+ (void)setNotifyOnExpiry:(BOOL)on { [self setLocal:@(on) key:@"sfNotifyExpiry"]; }

+ (NSArray<NSString *> *)excludedBundleIdentifiers {
    NSArray *value = [self value:@"sfExcluded"];
    return [value isKindOfClass:[NSArray class]] ? value : @[];
}
+ (BOOL)isExcluded:(NSString *)bundleIdentifier {
    return bundleIdentifier && [[self excludedBundleIdentifiers] containsObject:bundleIdentifier];
}
+ (void)setExcluded:(BOOL)excluded forBundleIdentifier:(NSString *)bundleIdentifier {
    if (!bundleIdentifier) return;
    NSMutableArray *list = [[self excludedBundleIdentifiers] mutableCopy];
    [list removeObject:bundleIdentifier];
    if (excluded) [list addObject:bundleIdentifier];
    [self setLocal:list key:@"sfExcluded"];
}

+ (NSString *)appleIDEmail { return [self value:@"sfAppleIDEmail"]; }
+ (void)setAppleIDEmail:(NSString *)email { [self setLocal:email key:@"sfAppleIDEmail"]; }

+ (NSString *)profileName {
    NSString *name = [[[NSUserDefaults standardUserDefaults] stringForKey:@"sfProfileName"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return name.length ? name : nil;
}
+ (void)setProfileName:(NSString *)name { [self setLocal:name.length ? name : nil key:@"sfProfileName"]; }
+ (BOOL)hideEmail { return [[NSUserDefaults standardUserDefaults] boolForKey:@"sfHideEmail"]; }
+ (void)setHideEmail:(BOOL)hide { [self setLocal:@(hide) key:@"sfHideEmail"]; }
+ (NSString *)displayEmail {
    NSString *email = [self appleIDEmail];
    if (!email) return nil;
    return [self hideEmail] ? @"************" : email;
}

+ (NSString *)profileImagePath {
    NSString *dir = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"Sevenfold"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:@"profile.jpg"];
}
+ (UIImage *)profileImage {
    static UIImage *cached; static NSDate *cachedDate;
    NSString *path = [self profileImagePath];
    NSDate *date = [[[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil] fileModificationDate];
    if (!date) return nil;
    if (!cached || ![cachedDate isEqualToDate:date]) { cached = [UIImage imageWithContentsOfFile:path]; cachedDate = date; }
    return cached;
}
+ (void)setProfileImage:(UIImage *)image {
    NSString *path = [self profileImagePath];
    if (!image) [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    else {
        // Square crop from the middle, 512 px.
        CGFloat side = MIN(image.size.width, image.size.height);
        CGRect crop = CGRectMake((image.size.width - side) / 2, (image.size.height - side) / 2, side, side);
        UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
        format.scale = 1;
        UIImage *square = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(512, 512) format:format] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            CGFloat scale = 512 / side;
            [image drawInRect:CGRectMake(-crop.origin.x * scale, -crop.origin.y * scale, image.size.width * scale, image.size.height * scale)];
        }];
        [UIImageJPEGRepresentation(square, 0.88) writeToFile:path atomically:YES];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:SFSettingsDidChangeNotification object:nil];
}
+ (BOOL)isSignedIn {
    return [SFResources getUsername].length > 0 && [SFResources getPassword].length > 0 && [SFResources getTeamID].length > 0;
}

+ (NSDictionary *)lastRun {
    NSDictionary *value = [self value:@"sfLastRun"];
    return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}
+ (void)setLastRun:(NSDictionary *)run { [self setLocal:run key:@"sfLastRun"]; }

@end
