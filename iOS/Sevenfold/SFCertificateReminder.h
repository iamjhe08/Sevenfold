//
//  SFCertificateReminder.h
//  Sevenfold
//
//  Reminds you before this iPhone's signing certificate expires (14, 3 and 1 day
//  before), and renews it: revoke, then sign every app again with a new one.
//

#import <Foundation/Foundation.h>

@class SFCertificate;

NS_ASSUME_NONNULL_BEGIN

/// Posted to ask the Apps screen to sign every app now.
extern NSString *const SFSignAllRequestedNotification;
/// Posted (by a reminder tap) to open the Certificates tab.
extern NSString *const SFOpenCertificatesNotification;

@interface SFCertificateReminder : NSObject

/// Days before expiry when the Certificates screen shows the renew banner.
+ (NSInteger)bannerDays;
/// This iPhone's certificate expiry, as last seen (nil if unknown).
+ (nullable NSDate *)thisDeviceExpiry;

/// Call with every fresh certificate list: saves the expiry and reschedules reminders.
+ (void)updateWithCertificates:(NSArray<SFCertificate *> *)certificates;
/// Fetches the list at most once a day so reminders stay right without opening Certificates.
+ (void)refreshIfDue;

@end

NS_ASSUME_NONNULL_END
