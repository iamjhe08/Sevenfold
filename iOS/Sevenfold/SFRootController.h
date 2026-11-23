//
//  SFRootController.h
//  Sevenfold
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SFRootController : UITabBarController
- (void)presentInstallForIPAURL:(NSURL *)url;
- (void)presentCertificateImportForURL:(NSURL *)url;
- (void)presentSigningProgress;   // separate screen; only used when installing a new .ipa
- (void)showAppsList;             // signing progress shows in the Apps list
- (void)presentSignIn;
@end

NS_ASSUME_NONNULL_END
