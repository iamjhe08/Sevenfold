//
//  SFTableViewController.h
//  Sevenfold
//
//  Base for the grouped list screens, with helpers for common rows.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// iPad: keeps a table to a centred reading column (no-op on iPhone).
extern void SFApplyReadableColumn(UITableView *table);

@interface SFTableViewController : UITableViewController
- (UITableViewCell *)valueCellWithTitle:(NSString *)title value:(nullable NSString *)value;
- (UITableViewCell *)valueCellWithTitle:(NSString *)title value:(nullable NSString *)value detail:(nullable NSString *)detail;
- (UITableViewCell *)navigationCellWithTitle:(NSString *)title value:(nullable NSString *)value icon:(nullable UIImage *)icon;
- (UITableViewCell *)switchCellWithTitle:(NSString *)title subtitle:(nullable NSString *)subtitle on:(BOOL)on action:(SEL)action;
- (UITableViewCell *)buttonCellWithTitle:(NSString *)title color:(nullable UIColor *)color;
- (UITableViewCell *)subtitleCellWithTitle:(NSString *)title subtitle:(nullable NSString *)subtitle;
- (void)showError:(NSError *)error title:(NSString *)title;
- (void)showMessage:(NSString *)message title:(NSString *)title;
@end

NS_ASSUME_NONNULL_END
