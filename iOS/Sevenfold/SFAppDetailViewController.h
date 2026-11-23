//
//  SFAppDetailViewController.h
//  Sevenfold
//

#import "SFTableViewController.h"

@class SFApplication;

NS_ASSUME_NONNULL_BEGIN

@interface SFAppDetailViewController : SFTableViewController
- (instancetype)initWithApplication:(SFApplication *)application installMode:(BOOL)installMode;
@end

NS_ASSUME_NONNULL_END
