//
//  SFIpaBundleApplication.h
//  Sevenfold
//
//  Sevenfold · BY: T4MAG0
//
//  An .ipa file the user picked to install. Reads the app's details straight
//  from the archive without unpacking all of it.
//

#import "SFApplication.h"

NS_ASSUME_NONNULL_BEGIN

@interface SFIpaBundleApplication : SFApplication
- (instancetype)initWithIpaURL:(NSURL *)url;
@end

NS_ASSUME_NONNULL_END
