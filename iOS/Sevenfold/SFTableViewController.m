//
//  SFTableViewController.m
//  Sevenfold
//

#import "SFTableViewController.h"
#import "SFLocalization.h"
#import "SFTheme.h"

@implementation SFTableViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.backgroundColor = [SFTheme background];
    self.tableView.separatorColor = [SFTheme separator];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    SFApplyReadableColumn(self.tableView);
}

/// On a wide iPad, keep lists to a ~680 pt column centred in the space.
void SFApplyReadableColumn(UITableView *table) {
    if (UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPad) return;
    CGFloat width = CGRectGetWidth(table.safeAreaLayoutGuide.layoutFrame);
    CGFloat side = width > 760 ? floor((width - 680) / 2) : 20;
    NSDirectionalEdgeInsets m = table.directionalLayoutMargins;
    if (fabs(m.leading - side) < 0.5 && fabs(m.trailing - side) < 0.5) return;
    table.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(m.top, side, m.bottom, side);
}

- (UITableViewCell *)baseCell {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.backgroundColor = [SFTheme card];
    return cell;
}

- (UITableViewCell *)valueCellWithTitle:(NSString *)title value:(NSString *)value {
    UITableViewCell *cell = [self baseCell];
    UIListContentConfiguration *config = [UIListContentConfiguration valueCellConfiguration];
    config.text = title;
    config.secondaryText = value;
    config.secondaryTextProperties.color = [SFTheme secondaryText];
    config.secondaryTextProperties.numberOfLines = 2;
    cell.contentConfiguration = config;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

/// Title on the left; on the right a value with a smaller second line under it.
- (UITableViewCell *)valueCellWithTitle:(NSString *)title value:(NSString *)value detail:(NSString *)detail {
    UITableViewCell *cell = [self baseCell];
    UIListContentConfiguration *config = [UIListContentConfiguration valueCellConfiguration];
    config.text = title;
    NSMutableAttributedString *right = [[NSMutableAttributedString alloc] initWithString:value ?: @"" attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold],
        NSForegroundColorAttributeName: [UIColor labelColor] }];
    if (detail.length) {
        [right appendAttributedString:[[NSAttributedString alloc] initWithString:[@"\n" stringByAppendingString:detail] attributes:@{
            NSFontAttributeName: [UIFont systemFontOfSize:13],
            NSForegroundColorAttributeName: [SFTheme secondaryText] }]];
    }
    config.secondaryAttributedText = right;
    config.secondaryTextProperties.numberOfLines = 2;
    config.secondaryTextProperties.alignment = UIListContentTextAlignmentNatural;
    config.prefersSideBySideTextAndSecondaryText = YES;
    cell.contentConfiguration = config;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (UITableViewCell *)navigationCellWithTitle:(NSString *)title value:(NSString *)value icon:(UIImage *)icon {
    UITableViewCell *cell = [self baseCell];
    UIListContentConfiguration *config = [UIListContentConfiguration valueCellConfiguration];
    config.text = title;
    config.secondaryText = value;
    config.secondaryTextProperties.color = [SFTheme secondaryText];
    config.image = icon;
    cell.contentConfiguration = config;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (UITableViewCell *)switchCellWithTitle:(NSString *)title subtitle:(NSString *)subtitle on:(BOOL)on action:(SEL)action {
    UITableViewCell *cell = [self baseCell];
    UIListContentConfiguration *config = [UIListContentConfiguration subtitleCellConfiguration];
    config.text = title;
    config.secondaryText = subtitle;
    config.secondaryTextProperties.color = [SFTheme secondaryText];
    config.textToSecondaryTextVerticalPadding = 3;
    cell.contentConfiguration = config;
    UISwitch *toggle = [UISwitch new];
    toggle.on = on;
    toggle.onTintColor = [SFTheme accent];
    [toggle addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = toggle;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (UITableViewCell *)buttonCellWithTitle:(NSString *)title color:(UIColor *)color {
    UITableViewCell *cell = [self baseCell];
    UIListContentConfiguration *config = [UIListContentConfiguration cellConfiguration];
    config.text = title;
    config.textProperties.color = color ?: [SFTheme accent];
    config.textProperties.font = [SFTheme fontOfSize:17 weight:UIFontWeightMedium];
    cell.contentConfiguration = config;
    return cell;
}

- (UITableViewCell *)subtitleCellWithTitle:(NSString *)title subtitle:(NSString *)subtitle {
    UITableViewCell *cell = [self baseCell];
    UIListContentConfiguration *config = [UIListContentConfiguration subtitleCellConfiguration];
    config.text = title;
    config.secondaryText = subtitle;
    config.secondaryTextProperties.color = [SFTheme secondaryText];
    config.textToSecondaryTextVerticalPadding = 3;
    cell.contentConfiguration = config;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (void)showError:(NSError *)error title:(NSString *)title {
    [self showMessage:error.localizedDescription ?: SFL(@"Something went wrong.") title:title];
}

- (void)showMessage:(NSString *)message title:(NSString *)title {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SFL(@"OK") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
