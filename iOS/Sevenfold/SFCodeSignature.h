//
//  SFCodeSignature.h
//  Sevenfold
//
//  Reads which certificate actually signed an app, from the code signature
//  inside its main executable (not the provisioning profile, which lists
//  every certificate on the Apple ID).
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Uppercase hex serial number (no leading zeros) of the signing certificate,
/// or nil if the app isn't signed with a certificate (e.g. ad-hoc).
NSString * _Nullable SFSigningCertificateSerialForApp(NSURL *appBundleURL);

NS_ASSUME_NONNULL_END
