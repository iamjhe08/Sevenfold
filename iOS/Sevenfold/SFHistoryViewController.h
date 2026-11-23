//
//  SFHistoryViewController.h
//  Sevenfold
//
//  History tab: every signing run with its time and result.
//

#import "SFTableViewController.h"

@interface SFHistoryViewController : SFTableViewController
@end

@interface SFHistoryRunViewController : SFTableViewController
- (instancetype)initWithRun:(NSDictionary *)run;
@end
