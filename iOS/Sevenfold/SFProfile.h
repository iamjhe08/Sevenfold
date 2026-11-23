//
//  SFProfile.h
//  Sevenfold
//
//  Apple ID card in Settings (photo, name, email with show/hide, iPhone model)
//  and the Edit profile screen. Profile data stays on this iPhone.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SFProfileCell : UITableViewCell
@property (nonatomic, copy, nullable) void (^onToggleEmail)(void);
- (void)refresh;
@end

@interface SFEditProfileViewController : UITableViewController
@end

/// Round avatar: the chosen photo, or initials on the Sevenfold gradient.
UIImage *SFProfileAvatar(CGFloat size);

NS_ASSUME_NONNULL_END
