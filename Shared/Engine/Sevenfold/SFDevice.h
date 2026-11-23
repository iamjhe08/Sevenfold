//
//  SFDevice.h
//  Sevenfold
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SFDevice : NSObject
/// Hardware identifier, e.g. "iPhone16,2".
+ (NSString *)hardwareIdentifier;
/// Marketing name, e.g. "iPhone 15 Pro Max". Falls back to the identifier.
+ (NSString *)modelName;
+ (NSString *)modelNameForIdentifier:(NSString *)identifier;
/// Label written into new certificates so they can be recognised later.
+ (NSString *)certificateMachineName;
/// Extracts the model from a certificate label written by Sevenfold, or nil.
+ (nullable NSString *)modelFromCertificateMachineName:(NSString *)machineName;
@end

NS_ASSUME_NONNULL_END
