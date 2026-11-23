//
//  SFAuthKit.h
//  Sevenfold
//
//  BY: T4MAG0
//
//  The few private AuthKit calls Sevenfold uses (AuthKit is loaded at run time).
//

#import <Foundation/Foundation.h>

/// This iPhone as AuthKit describes it to Apple.
@interface AKDevice : NSObject
+ (instancetype)currentDevice;
- (NSString *)uniqueDeviceIdentifier;
- (NSString *)serialNumber;
- (NSString *)MLBSerialNumber;
- (NSString *)ROMAddress;
@end

/// Produces the anisette headers for a request, using this iPhone's own identity.
@interface AKAppleIDSession : NSObject
- (instancetype)initWithIdentifier:(NSString *)identifier;
- (NSDictionary *)appleIDHeadersForRequest:(NSURLRequest *)request;
@end
