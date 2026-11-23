//
//  SFApplication.h
//  Sevenfold
//
//  Sevenfold · BY: T4MAG0
//
//  An app installed on this iPhone that Sevenfold can sign.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SFApplication : NSObject

/// The plist inside an embedded.mobileprovision file (nil if missing or unreadable).
+ (nullable NSDictionary *)provisioningProfileAtPath:(NSString *)path;

/// Wraps a LaunchServices record for an installed app.
- (instancetype)initWithApplicationProxy:(nullable id)proxy;

- (nullable NSString *)bundleIdentifier;
- (nullable NSString *)applicationName;
- (nullable NSString *)applicationVersion;
- (nullable NSNumber *)applicationInstalledSize;
- (nullable UIImage *)applicationIcon;

/// When the app's provisioning profile runs out (nil = no profile).
- (nullable NSDate *)applicationExpiryDate;
/// Team that signed the app (from its provisioning profile).
- (nullable NSString *)teamIdentifier;
- (BOOL)hasEmbeddedMobileprovision;

/// The .app folder for an installed app, or the .ipa file for one being installed.
- (nullable NSURL *)locationOfApplicationOnFilesystem;

@end

NS_ASSUME_NONNULL_END
