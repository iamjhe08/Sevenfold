//
//  SFCertificateReminder.m
//  Sevenfold
//
//  BY: T4MAG0
//

#import "SFCertificateReminder.h"
#import "SFCertificateStore.h"
#import "SFLocalization.h"
#import "SFSettings.h"
#import "SFLog.h"
#import <UserNotifications/UserNotifications.h>

NSString *const SFSignAllRequestedNotification = @"com.t4mag0.sevenfold/signAll";
NSString *const SFOpenCertificatesNotification = @"com.t4mag0.sevenfold/openCertificates";

static NSString *const SFCertExpiryKey = @"sfThisCertificateExpires";
static NSString *const SFCertCheckedKey = @"sfCertificateCheckedAt";

@implementation SFCertificateReminder

+ (NSInteger)bannerDays {
    return 14;
}

+ (NSDate *)thisDeviceExpiry {
    id date = [[NSUserDefaults standardUserDefaults] objectForKey:SFCertExpiryKey];
    return [date isKindOfClass:[NSDate class]] ? date : nil;
}

+ (void)updateWithCertificates:(NSArray<SFCertificate *> *)certificates {
    NSDate *expiry = nil;
    for (SFCertificate *certificate in certificates) {
        if (certificate.usedByThisDevice && certificate.expirationDate) { expiry = certificate.expirationDate; break; }
    }
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:[NSDate date] forKey:SFCertCheckedKey];
    NSDate *previous = [self thisDeviceExpiry];
    if (expiry) [defaults setObject:expiry forKey:SFCertExpiryKey];
    else [defaults removeObjectForKey:SFCertExpiryKey];
    if (previous && expiry && fabs([previous timeIntervalSinceDate:expiry]) < 60) return;   // nothing changed
    [self scheduleFor:expiry];
}

+ (void)scheduleFor:(nullable NSDate *)expiry {
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    NSArray *ids = @[@"sf.cert.14", @"sf.cert.3", @"sf.cert.1"];
    [center removePendingNotificationRequestsWithIdentifiers:ids];
    if (!expiry) return;

    NSDateFormatter *formatter = [NSDateFormatter new];
    [formatter setLocalizedDateFormatFromTemplate:@"d MMM"];
    NSString *day = [formatter stringFromDate:expiry];
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSInteger scheduled = 0;
    for (NSNumber *before in @[@14, @3, @1]) {
        NSDate *when = [calendar dateByAddingUnit:NSCalendarUnitDay value:-before.integerValue toDate:expiry options:0];
        // 10:00 that day, in the phone's time zone.
        when = [calendar dateBySettingHour:10 minute:0 second:0 ofDate:when options:0];
        if (!when || when.timeIntervalSinceNow < 60) continue;
        UNMutableNotificationContent *content = [UNMutableNotificationContent new];
        content.title = before.integerValue == 1 ? SFL(@"Certificate expires tomorrow")
                                                 : [NSString stringWithFormat:SFL(@"Certificate expires in %ld days"), (long)before.integerValue];
        content.body = [NSString stringWithFormat:SFL(@"On %@ all your apps stop opening. Tap to renew now; Sevenfold signs your apps again right after."), day];
        content.sound = [UNNotificationSound defaultSound];
        NSDateComponents *parts = [calendar components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute fromDate:when];
        UNCalendarNotificationTrigger *trigger = [UNCalendarNotificationTrigger triggerWithDateMatchingComponents:parts repeats:NO];
        NSString *identifier = [NSString stringWithFormat:@"sf.cert.%@", before];
        [center addNotificationRequest:[UNNotificationRequest requestWithIdentifier:identifier content:content trigger:trigger] withCompletionHandler:nil];
        scheduled++;
    }
    SFLogEvent(SFLogLevelInfo, @"certificate · expires %@ · %ld reminder(s) scheduled", day, (long)scheduled);
}

+ (void)refreshIfDue {
    if (![SFSettings isSignedIn]) return;
    id checked = [[NSUserDefaults standardUserDefaults] objectForKey:SFCertCheckedKey];
    if ([checked isKindOfClass:[NSDate class]] && -[checked timeIntervalSinceNow] < 24 * 3600) return;
    [SFCertificateStore fetchCertificatesWithCompletion:^(NSArray<SFCertificate *> *certificates, NSError *error) {
        // fetchCertificates already passes fresh lists to updateWithCertificates:.
    }];
}

@end
