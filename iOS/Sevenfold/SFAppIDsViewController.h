//
//  SFAppIDsViewController.h
//  Sevenfold
//
//  When this week's App IDs free up (free Apple IDs: 10 per 7 days).
//

#import "SFTableViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface SFAppIDsViewController : SFTableViewController
/// "+3 free on Thu", or nil when nothing is waiting to free up.
+ (nullable NSString *)nextFreeUpSummary;
@end

NS_ASSUME_NONNULL_END
