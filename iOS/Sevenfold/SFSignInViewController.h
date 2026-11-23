//
//  SFSignInViewController.h
//  Sevenfold
//
//  Apple ID sign-in, two-factor code, and the account setup step.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SFSignInViewController : UIViewController
@property (nonatomic, copy, nullable) void (^onFinish)(void);
@end

@interface SFTwoFactorViewController : UIViewController
@property (nonatomic, copy) NSString *email;
@property (nonatomic, copy, nullable) void (^onFinish)(void);
@end

@interface SFAccountSetupViewController : UIViewController
- (instancetype)initWithEmail:(NSString *)email identity:(NSString *)identity token:(NSString *)token teamID:(NSString *)teamID;
@property (nonatomic, copy, nullable) void (^onFinish)(void);
@end

NS_ASSUME_NONNULL_END
