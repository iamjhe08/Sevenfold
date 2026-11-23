//
//  SFShareCertificateViewController.h
//  Sevenfold
//
//  Send this iPhone's certificate to your other iPhone, or receive one.
//

#import "SFTableViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface SFShareCertificateViewController : SFTableViewController
/// Set when the app was opened with a .sevenfold-cert file.
@property (nonatomic, strong, nullable) NSURL *pendingImportURL;
@end

NS_ASSUME_NONNULL_END
