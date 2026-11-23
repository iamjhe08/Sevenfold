//
//  SFCertificatesViewController.h
//  Sevenfold
//

#import "SFTableViewController.h"

@class SFCertificate;

@interface SFCertificatesViewController : SFTableViewController
/// Asks to confirm, revokes, and offers to sign again if this iPhone's apps were signed with it.
+ (void)confirmRevokeCertificate:(SFCertificate *)certificate from:(UIViewController *)presenter completion:(void (^)(BOOL revoked))completion;
@end
