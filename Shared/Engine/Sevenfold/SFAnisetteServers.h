//
//  SFAnisetteServers.h
//  Sevenfold
//
//  The list of anisette servers, the order they are tried in, and their last
//  known status. Sign-in moves to the next server when one stalls or errors.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Client identity sent to Apple. Matches the identity used by the working 28.4 build.
extern NSString *const SFClientIdentity;
/// User agent for akd-style Apple requests.
extern NSString *const SFAkdUserAgent;

@interface SFAnisetteServers : NSObject

/// Each server: @{ @"name": NSString, @"url": NSString (https://host) }
+ (NSArray<NSDictionary *> *)servers;
+ (void)setServers:(NSArray<NSDictionary *> *)servers;
+ (NSArray<NSDictionary *> *)defaultServers;

/// Adds (or moves) a server to the top of the list and makes it the one tried first.
+ (BOOL)automaticFallback;
+ (void)setAutomaticFallback:(BOOL)enabled;

/// Server URLs in the order to try for the next request.
+ (NSArray<NSString *> *)orderedServerURLs;

/// Records how a server behaved. Successful servers are tried first next time.
+ (void)recordResultForServer:(NSString *)url success:(BOOL)success milliseconds:(NSInteger)ms;

/// @{ url: @{ @"ok": NSNumber, @"ms": NSNumber, @"date": NSDate } }
+ (NSDictionary<NSString *, NSDictionary *> *)statuses;
+ (nullable NSString *)lastGoodServer;
+ (NSString *)nameForServer:(NSString *)url;

/// Checks /v3/client_info on every server and records the result.
+ (void)testAllServersWithCompletion:(void (^)(void))completion;

@end

NS_ASSUME_NONNULL_END
