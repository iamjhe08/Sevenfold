//
//  SFResources.m
//  Sevenfold
//
//  BY: T4MAG0
//

#import "SFResources.h"
#import "AppDelegate.h"
#import "SAMKeychain.h"

#import <objc/runtime.h>
#include <dlfcn.h>
#include <notify.h>

static NSString *const SFAccountService = @"com.t4mag0.sevenfold.account";   // keychain service for the token
static NSString *const SFShowSignIn = @"com.t4mag0.sevenfold.show-sign-in";

@interface NRDevice : NSObject
- (id)valueForProperty:(id)property;
@end

@interface NRPairedDeviceRegistry : NSObject
+ (instancetype)sharedInstance;
- (NRDevice *)getActivePairedDevice;
- (bool)isPaired;
@end

@implementation SFResources

#pragma mark - Preferences

+ (id)preferenceValueForKey:(NSString *)key {
    return [[NSUserDefaults standardUserDefaults] objectForKey:key];
}

+ (BOOL)flag:(NSString *)key fallback:(BOOL)fallback {
    id value = [self preferenceValueForKey:key];
    return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : fallback;
}

+ (BOOL)shouldShowDebugAlerts       { return [self flag:@"sfDebugAlerts" fallback:NO]; }
+ (BOOL)shouldShowNonUrgentAlerts   { return [self flag:@"sfMinorAlerts" fallback:NO]; }
+ (BOOL)autoSignEnabled   { return [self flag:@"sfAutoSign" fallback:YES]; }
+ (BOOL)lowPowerSigningAllowed  { return [self flag:@"sfSignInLowPower" fallback:NO]; }

+ (int)expiryThresholdDays {
    id value = [self preferenceValueForKey:@"sfExpiryThresholdDays"];
    return [value respondsToSelector:@selector(intValue)] ? [value intValue] : 2;
}

+ (void)setPreferenceValue:(id)value forKey:(NSString *)key withNotification:(NSString *)notification {
    [[NSUserDefaults standardUserDefaults] setObject:value forKey:key];
    // Also into the CFPreferences domain the background service reads.
    CFPreferencesSetValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, CFSTR("com.t4mag0.sevenfold"), kCFPreferencesCurrentUser, kCFPreferencesCurrentHost);
    CFPreferencesSynchronize(CFSTR("com.t4mag0.sevenfold"), kCFPreferencesCurrentUser, kCFPreferencesCurrentHost);

    // Two ways to tell the service: a system notification (works even without a connection) and XPC.
    notify_post("com.t4mag0.sevenfold.preferences-changed");
    [(AppDelegate *)[UIApplication sharedApplication].delegate requestPreferencesUpdate];

    if (notification) [[NSNotificationCenter defaultCenter] postNotificationName:notification object:nil];
}

#pragma mark - Saved sign-in

/// The saved identity looks like "<dsid>|<email>"; anything else means signed out.
+ (NSString *)getUsername {
    NSString *username = [self preferenceValueForKey:@"sfAccount"];
    if (![username isKindOfClass:[NSString class]]) return nil;
    return [username componentsSeparatedByString:@"|"].count >= 2 ? username : nil;
}

+ (NSString *)getPassword {
    NSString *username = [self getUsername];
    return username ? [SAMKeychain passwordForService:SFAccountService account:username] : nil;
}

+ (NSString *)getTeamID {
    return [self preferenceValueForKey:@"sfTeamID"];
}

+ (NSString *)getCredentialsVersion {
    return [self preferenceValueForKey:@"sfCredentialsVersion"] ?: @"0";
}

+ (void)storeUsername:(NSString *)username password:(NSString *)password andTeamID:(NSString *)teamId {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:username forKey:@"sfAccount"];
    [SAMKeychain setPassword:password forService:SFAccountService account:username];
    [defaults setObject:teamId forKey:@"sfTeamID"];
    [defaults setObject:CURRENT_CREDENTIALS_VERSION forKey:@"sfCredentialsVersion"];
}

+ (void)migrateStoredCredentialsForBackgroundAccessIfPossible {
    if (![UIApplication sharedApplication].protectedDataAvailable) return;
    NSString *username = [self getUsername];
    if (username.length == 0) return;

    NSError *error = nil;
    NSString *token = [SAMKeychain passwordForService:SFAccountService account:username error:&error];
    if (token.length == 0) {
        if (error) NSLog(@"[Sevenfold] keychain item not moved yet: %@", error.localizedDescription);
        return;
    }
    // Saving again applies the current accessibility (set at launch).
    if (![SAMKeychain setPassword:token forService:SFAccountService account:username error:&error])
        NSLog(@"[Sevenfold] couldn't re-save the token for locked signing: %@", error.localizedDescription);
}

+ (void)userDidRequestAccountSignIn {
    [[NSNotificationCenter defaultCenter] postNotificationName:SFShowSignIn object:nil];
}

+ (void)userDidRequestAccountSignOut {
    NSString *username = [self getUsername];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"sfAccount"];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"sfTeamID"];
    if (username) [SAMKeychain deletePasswordForService:SFAccountService account:username];
    [[NSNotificationCenter defaultCenter] postNotificationName:SFShowSignIn object:nil];
}

#pragma mark - Apple Watch

+ (NRPairedDeviceRegistry *)watchRegistry {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ dlopen("/System/Library/PrivateFrameworks/NanoRegistry.framework/NanoRegistry", RTLD_NOW); });
    return [objc_getClass("NRPairedDeviceRegistry") sharedInstance];
}

+ (BOOL)hasActivePairedWatch {
    return [[self watchRegistry] isPaired];
}

+ (NSString *)activePairedWatchUDID {
    return [[[self watchRegistry] getActivePairedDevice] valueForProperty:@"UDID"];
}

+ (NSString *)activePairedWatchName {
    return [[[self watchRegistry] getActivePairedDevice] valueForProperty:@"name"];
}

@end
