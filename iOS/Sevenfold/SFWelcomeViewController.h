//
//  SFWelcomeViewController.h
//  Sevenfold
//
//  First-run guide: three short pages before the first sign-in.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SFWelcomeViewController : UIViewController
/// YES when opened again from Settings: the last button says Done and closes the guide.
@property (nonatomic) BOOL reopened;
/// Called when the guide finishes (last button or Skip).
@property (nonatomic, copy, nullable) void (^onDone)(void);
@end

NS_ASSUME_NONNULL_END
