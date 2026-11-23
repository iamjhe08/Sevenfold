//
//  SFResources.h
//  Sevenfold
//
//  BY: T4MAG0
//
//  The saved Apple ID (identity in settings, token in the keychain), the
//  preferences shared with the background service, and the paired Apple Watch.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

/// Bumped when the saved sign-in format changes; an older one asks the user to sign in again.
#define CURRENT_CREDENTIALS_VERSION @"2"

@interface SFResources : NSObject

#pragma mark Preferences

+ (BOOL)shouldShowDebugAlerts;
+ (BOOL)shouldShowNonUrgentAlerts;
/// Sign apps that have fewer than this many days left (default 2).
+ (int)expiryThresholdDays;
+ (BOOL)autoSignEnabled;
+ (BOOL)lowPowerSigningAllowed;

+ (id)preferenceValueForKey:(NSString *)key;
/// Saves a preference where the background service can read it and tells it to reload.
/// `notification` (optional) is also posted in the app.
+ (void)setPreferenceValue:(id)value forKey:(NSString *)key withNotification:(NSString *)notification;

#pragma mark Saved sign-in

+ (NSString *)getUsername;
+ (NSString *)getPassword;
+ (NSString *)getTeamID;
+ (NSString *)getCredentialsVersion;
+ (void)storeUsername:(NSString *)username password:(NSString *)password andTeamID:(NSString *)teamId;
/// Re-saves the token so it can be read while the phone is locked (after the first unlock).
+ (void)migrateStoredCredentialsForBackgroundAccessIfPossible;

+ (void)userDidRequestAccountSignIn;
+ (void)userDidRequestAccountSignOut;

#pragma mark Apple Watch

+ (BOOL)hasActivePairedWatch;
+ (NSString *)activePairedWatchUDID;
+ (NSString *)activePairedWatchName;

@end
