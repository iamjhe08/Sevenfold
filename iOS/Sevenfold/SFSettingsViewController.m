//
//  SFSettingsViewController.m
//  Sevenfold
//

#import "SFSettingsViewController.h"
#import "SFLocalization.h"
#import "SFLanguageViewController.h"
#import "SFWelcomeViewController.h"
#import "SFCertificatesViewController.h"
#import "SFShareCertificateViewController.h"
#import "SFCertificateStore.h"
#import "SFAnisetteServers.h"
#import "SFSigningSession.h"
#import "SFSettings.h"
#import "SFTheme.h"
#import "SFDevice.h"
#import "SFLog.h"
#import "SFResources.h"
#import "SFNotificationManager.h"
#import <UserNotifications/UserNotifications.h>
#import "SFPopup.h"
#import "SFProfile.h"
#import "AppDelegate.h"

#pragma mark - Settings

@interface SFSettingsViewController ()
@property (nonatomic) BOOL checkingCertificates;
@end

@implementation SFSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self.tableView selector:@selector(reloadData) name:SFSettingsDidChangeNotification object:nil];
    [center addObserver:self.tableView selector:@selector(reloadData) name:@"com.t4mag0.sevenfold/userDidSignIn" object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;   // Certificates live in their own tab
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return [SFSettings isSignedIn] ? 3 : 2;
        case 1: return 3;
        default: return 3;   // Language, How Sevenfold works, Diagnostics
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[SFL(@"Apple ID"), SFL(@"Signing"), SFL(@"Support")][section];
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    if (section != 2) return nil;
    UIView *footer = [UIView new];
    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"1.0";
    UILabel *about = [SFTheme labelWithSize:13 weight:UIFontWeightRegular color:[SFTheme secondaryText]];
#ifndef SF_BUILD
#define SF_BUILD "dev"
#endif
    about.text = [NSString stringWithFormat:@"Sevenfold %@ · build %s", version, SF_BUILD];
    about.textAlignment = NSTextAlignmentCenter;
    UILabel *by = [SFTheme labelWithSize:12 weight:UIFontWeightBold color:[SFTheme accent]];
    NSMutableAttributedString *byText = [[NSMutableAttributedString alloc] initWithString:@"BY: T4MAG0"];
    [byText addAttribute:NSKernAttributeName value:@2 range:NSMakeRange(0, byText.length)];
    by.attributedText = byText;
    by.textAlignment = NSTextAlignmentCenter;
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[about, by]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 4;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [footer addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:footer.topAnchor constant:24],
        [stack.bottomAnchor constraintEqualToAnchor:footer.bottomAnchor constant:-24],
        [stack.leadingAnchor constraintEqualToAnchor:footer.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:footer.trailingAnchor],
    ]];
    return footer;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    BOOL signedIn = [SFSettings isSignedIn];
    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            // Photo, name, email (with show/hide) and iPhone model. No Team ID.
            SFProfileCell *cell = [[SFProfileCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
            __weak typeof(self) weakSelf = self;
            cell.onToggleEmail = ^{ [weakSelf.tableView reloadData]; };
            [cell refresh];
            return cell;
        }
        if (signedIn && indexPath.row == 1) {
            UITableViewCell *cell = [self buttonCellWithTitle:SFL(@"Edit profile") color:[SFTheme amber]];
            cell.imageView.image = [UIImage systemImageNamed:@"pencil" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightSemibold]];
            cell.imageView.tintColor = [SFTheme amber];
            UIListContentConfiguration *config = (UIListContentConfiguration *)cell.contentConfiguration;
            if ([config isKindOfClass:[UIListContentConfiguration class]]) {
                config.image = cell.imageView.image;
                config.imageProperties.tintColor = [SFTheme amber];
                cell.contentConfiguration = config;
            }
            return cell;
        }
        return signedIn ? [self buttonCellWithTitle:SFL(@"Sign out") color:[SFTheme danger]] : [self buttonCellWithTitle:SFL(@"Sign in") color:nil];
    }
    if (indexPath.section == 1) {
        switch (indexPath.row) {
            case 0: return [self navigationCellWithTitle:SFL(@"Schedule") value:[SFSettings scheduleSummary] icon:[SFTheme settingsIcon:@"clock.fill" color:[SFTheme accent]]];
            case 1: {
                NSString *value = [SFAnisetteServers automaticFallback] ? SFL(@"Automatic") : [SFAnisetteServers nameForServer:[SFAnisetteServers orderedServerURLs].firstObject ?: @""];
                return [self navigationCellWithTitle:SFL(@"Anisette servers") value:value icon:[SFTheme settingsIcon:@"server.rack" color:[UIColor systemTealColor]]];
            }
            default: {
                BOOL any = [SFSettings notifyOnSuccess] || [SFSettings notifyOnFailure] || [SFSettings notifyOnExpiry];
                return [self navigationCellWithTitle:SFL(@"Notifications") value:any ? SFL(@"On") : SFL(@"Off") icon:[SFTheme settingsIcon:@"bell.badge.fill" color:[UIColor systemRedColor]]];
            }
        }
    }
    if (indexPath.row == 0) {
        NSString *code = [SFLanguage selectedCode];
        NSString *value = SFL(@"Auto");
        for (NSDictionary *language in [SFLanguage available]) if ([language[@"code"] isEqualToString:code]) value = language[@"native"];
        return [self navigationCellWithTitle:SFL(@"Language") value:value icon:[SFTheme settingsIcon:@"globe" color:[UIColor systemBlueColor]]];
    }
    if (indexPath.row == 1) return [self navigationCellWithTitle:SFL(@"How Sevenfold works") value:nil icon:[SFTheme settingsIcon:@"book.fill" color:[UIColor systemOrangeColor]]];
    return [self navigationCellWithTitle:SFL(@"Diagnostics") value:nil icon:[SFTheme settingsIcon:@"waveform.path.ecg" color:[UIColor systemGrayColor]]];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    UIViewController *next = nil;
    if (indexPath.section == 0 && (indexPath.row == 0 || (indexPath.row == 1 && [SFSettings isSignedIn]))) {
        if (![SFSettings isSignedIn]) { [SFResources userDidRequestAccountSignIn]; return; }
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[SFEditProfileViewController new]];
        [self presentViewController:nav animated:YES completion:nil];
        return;
    }
    if (indexPath.section == 0 && indexPath.row >= 1) {
        if (![SFSettings isSignedIn]) { [SFResources userDidRequestAccountSignIn]; return; }
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:SFL(@"Sign out?") message:SFL(@"Apps you've signed keep working until they expire. Automatic signing stops until you sign in again.") preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:SFL(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:SFL(@"Sign out") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            SFLogEvent(SFLogLevelInfo, @"signed out");
            [SFResources userDidRequestAccountSignOut];
            [self.tableView reloadData];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    if (indexPath.section == 1) {
        if (indexPath.row == 0) next = [SFScheduleViewController new];
        else if (indexPath.row == 1) next = [SFServersViewController new];
        else next = [SFNotificationSettingsViewController new];
    } else if (indexPath.section == 2 && indexPath.row == 1) {
        SFWelcomeViewController *welcome = [SFWelcomeViewController new];
        welcome.reopened = YES;
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:welcome];
        __weak UINavigationController *weakNav = nav;
        welcome.onDone = ^{ [weakNav dismissViewControllerAnimated:YES completion:nil]; };
        [self presentViewController:nav animated:YES completion:nil];
        return;
    } else if (indexPath.section == 2) {
        next = indexPath.row == 0 ? (UIViewController *)[SFLanguageViewController new] : [SFDiagnosticsViewController new];
    }
    if (next) [self.navigationController pushViewController:next animated:YES];
}


- (void)revokeThisDevicesCertificate {
    if (![SFSettings isSignedIn]) { [SFResources userDidRequestAccountSignIn]; return; }
    if (self.checkingCertificates) return;
    // A spinner on the row (a loading alert could swallow the confirmation that follows it).
    self.checkingCertificates = YES;
    NSIndexPath *row = [NSIndexPath indexPathForRow:2 inSection:2];
    [self.tableView reloadRowsAtIndexPaths:@[row] withRowAnimation:UITableViewRowAnimationNone];
    [SFCertificateStore fetchCertificatesWithCompletion:^(NSArray<SFCertificate *> *certificates, NSError *error) {
        [SFCertificateStore fetchRegisteredDevicesWithCompletion:^(NSArray<SFRegisteredDevice *> *devices, NSError *deviceError) {
            NSMutableArray *otherModels = [NSMutableArray array];
            for (SFRegisteredDevice *device in devices)
                if (!device.isThisDevice && device.model.length > 0) [otherModels addObject:device.model];
            SFCertificate *mine = nil;
            for (SFCertificate *certificate in certificates) {
                certificate.otherRegisteredModels = otherModels;
                if (certificate.usedByThisDevice) { mine = certificate; break; }
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                self.checkingCertificates = NO;
                [self.tableView reloadRowsAtIndexPaths:@[row] withRowAnimation:UITableViewRowAnimationNone];
                if (error || !mine) {
                    NSString *message = error ? error.localizedDescription
                                              : SFL(@"This iPhone isn't signing with a certificate yet. Open Certificates to see all of them.");
                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:error ? SFL(@"Couldn't load certificates") : SFL(@"No certificate")
                                                                                   message:message preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:SFL(@"OK") style:UIAlertActionStyleCancel handler:nil]];
                    [self presentViewController:alert animated:YES completion:nil];
                    return;
                }
                [SFCertificatesViewController confirmRevokeCertificate:mine from:self completion:nil];
            });
        }];
    }];
}

@end

#pragma mark - Time picker sheet

@interface SFTimePickerController : UIViewController
@property (nonatomic) NSInteger minutes;
@property (nonatomic, copy) NSString *heading;
@property (nonatomic, copy) void (^onDone)(NSInteger minutes);
@end

@implementation SFTimePickerController {
    UIDatePicker *_picker;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [SFTheme background];
    self.title = self.heading ?: SFL(@"Signing time");
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
    UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done)];
    done.style = UIBarButtonItemStyleDone;
    self.navigationItem.rightBarButtonItem = done;

    _picker = [UIDatePicker new];
    _picker.translatesAutoresizingMaskIntoConstraints = NO;
    _picker.datePickerMode = UIDatePickerModeTime;
    _picker.preferredDatePickerStyle = UIDatePickerStyleWheels;
    _picker.date = [[NSCalendar currentCalendar] dateBySettingHour:self.minutes / 60 minute:self.minutes % 60 second:0 ofDate:[NSDate date] options:0];
    [self.view addSubview:_picker];

    UIButton *doneButton = [SFTheme primaryButtonWithTitle:SFL(@"Done")];
    [doneButton addTarget:self action:@selector(done) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:doneButton];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_picker.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
        [_picker.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [doneButton.topAnchor constraintEqualToAnchor:_picker.bottomAnchor constant:16],
        [doneButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [doneButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
    ]];
}

- (void)cancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)done {
    NSDateComponents *parts = [[NSCalendar currentCalendar] components:NSCalendarUnitHour | NSCalendarUnitMinute fromDate:_picker.date];
    NSInteger minutes = parts.hour * 60 + parts.minute;
    void (^handler)(NSInteger) = self.onDone;
    [self dismissViewControllerAnimated:YES completion:^{
        if (handler) handler(minutes);
    }];
}

@end

#pragma mark - Schedule

@interface SFScheduleViewController ()
@property (nonatomic, strong) NSMutableArray<UIButton *> *dayButtons;
@property (nonatomic, strong) NSArray<NSNumber *> *times;
@end

static const NSUInteger SFMaxScheduleTimes = 6;

@implementation SFScheduleViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = SFL(@"Schedule");
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.times = [SFSettings scheduleTimes];
}

// Section 1 rows: one per time, then "Add a time" (if room), then the days row.
- (BOOL)canAddTime {
    return self.times.count < SFMaxScheduleTimes;
}

- (NSInteger)addRow {
    return [self canAddTime] ? (NSInteger)self.times.count : -1;
}

- (NSInteger)daysRow {
    return (NSInteger)self.times.count + ([self canAddTime] ? 1 : 0);
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [SFSettings automaticSigning] ? 3 : 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 2;
        case 1: return [self daysRow] + 1;
        default: return 4;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[@"", SFL(@"Times"), SFL(@"Conditions")][section];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        if (![SFSettings automaticSigning]) return SFL(@"Apps are only signed when you tap Sign now.");
        return [NSString stringWithFormat:SFL(@"Next run: %@. If your iPhone is locked then, Sevenfold signs as soon as you unlock it."), [SFTheme shortDateTime:[SFSettings nextScheduledRun]]];
    }
    if (section == 1) return SFL(@"Sevenfold signs at each of these times on the days you pick. Swipe left on a time to remove it.");
    if (section == 2) return SFL(@"If a run is postponed or fails, Sevenfold tries again every 30 minutes, up to 3 times.");
    return nil;
}

- (UITableViewCell *)timeCellAtIndex:(NSInteger)index {
    NSString *title = self.times.count > 1 ? [NSString stringWithFormat:SFL(@"Time %ld"), (long)index + 1] : SFL(@"Time");
    UITableViewCell *cell = [self valueCellWithTitle:title value:[SFSettings timeStringForMinutes:self.times[index].integerValue]];
    UIListContentConfiguration *config = (UIListContentConfiguration *)cell.contentConfiguration;
    config.secondaryTextProperties.color = [SFTheme accent];
    config.secondaryTextProperties.font = [SFTheme fontOfSize:17 weight:UIFontWeightSemibold];
    cell.contentConfiguration = config;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (void)presentTimePickerWithMinutes:(NSInteger)minutes heading:(NSString *)heading onDone:(void (^)(NSInteger minutes))onDone {
    SFTimePickerController *picker = [SFTimePickerController new];
    picker.minutes = minutes;
    picker.heading = heading;
    picker.onDone = onDone;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:picker];
    UISheetPresentationController *sheet = nav.sheetPresentationController;
    sheet.detents = @[[UISheetPresentationControllerDetent mediumDetent]];
    sheet.prefersGrabberVisible = YES;
    [self presentViewController:nav animated:YES completion:nil];
}

- (UITableViewCell *)daysCell {
    UITableViewCell *cell = [self valueCellWithTitle:@"" value:nil];
    cell.contentConfiguration = nil;
    self.dayButtons = [NSMutableArray array];
    NSArray *letters = @[@"S", @"M", @"T", @"W", @"T", @"F", @"S"];
    NSArray *names = @[SFL(@"Sunday"), SFL(@"Monday"), SFL(@"Tuesday"), SFL(@"Wednesday"), SFL(@"Thursday"), SFL(@"Friday"), SFL(@"Saturday")];
    NSInteger days = [SFSettings scheduleDays];
    UIStackView *row = [UIStackView new];
    row.distribution = UIStackViewDistributionFillEqually;
    row.spacing = 6;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    for (NSInteger i = 1; i <= 7; i++) {
        NSInteger day = i % 7; // Monday first
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.tag = day;
        [button setTitle:letters[day] forState:UIControlStateNormal];
        button.titleLabel.font = [SFTheme fontOfSize:15 weight:UIFontWeightSemibold];
        button.accessibilityLabel = names[day];
        button.layer.cornerRadius = 19;
        [button.heightAnchor constraintEqualToConstant:38].active = YES;
        [button addTarget:self action:@selector(dayTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self styleDay:button on:(days & (1 << day)) != 0];
        [self.dayButtons addObject:button];
        [row addArrangedSubview:button];
    }
    [cell.contentView addSubview:row];
    UILayoutGuide *m = cell.contentView.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [row.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:10],
        [row.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-10],
        [row.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
        [row.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
    ]];
    return cell;
}

- (void)styleDay:(UIButton *)button on:(BOOL)on {
    button.selected = on;
    button.backgroundColor = on ? [SFTheme accent] : [SFTheme separator];
    [button setTitleColor:on ? [UIColor whiteColor] : [SFTheme secondaryText] forState:UIControlStateNormal];
    button.accessibilityTraits = on ? (UIAccessibilityTraitButton | UIAccessibilityTraitSelected) : UIAccessibilityTraitButton;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0 && indexPath.row == 1)
        return [self switchCellWithTitle:SFL(@"Sign apps at the same time") subtitle:SFL(@"Up to 3 at once. Off signs one by one.") on:[SFSettings parallelSigning] action:@selector(parallelChanged:)];
    if (indexPath.section == 0) return [self switchCellWithTitle:SFL(@"Automatic signing") subtitle:SFL(@"Sign apps at the time you choose") on:[SFSettings automaticSigning] action:@selector(autoChanged:)];
    if (indexPath.section == 1) {
        if (indexPath.row < (NSInteger)self.times.count) return [self timeCellAtIndex:indexPath.row];
        if (indexPath.row == [self addRow]) {
            UITableViewCell *cell = [self buttonCellWithTitle:SFL(@"Add a time") color:nil];
            UIListContentConfiguration *config = (UIListContentConfiguration *)cell.contentConfiguration;
            config.image = [UIImage systemImageNamed:@"plus.circle.fill"];
            config.imageProperties.tintColor = [SFTheme accent];
            cell.contentConfiguration = config;
            return cell;
        }
        return [self daysCell];
    }
    switch (indexPath.row) {
        case 0: return [self switchCellWithTitle:SFL(@"Only on Wi-Fi") subtitle:SFL(@"Wait instead of using mobile data") on:[SFSettings onlyOnWiFi] action:@selector(wifiChanged:)];
        case 1: return [self switchCellWithTitle:SFL(@"Only while charging") subtitle:SFL(@"Wait until the iPhone is plugged in") on:[SFSettings onlyWhileCharging] action:@selector(chargingChanged:)];
        case 2: return [self switchCellWithTitle:SFL(@"Retry if it fails") subtitle:SFL(@"Every 30 minutes, up to 3 times") on:[SFSettings retryOnFailure] action:@selector(retryChanged:)];
        default: return [self switchCellWithTitle:SFL(@"Sign in Low Power Mode") subtitle:nil on:[SFSettings signInLowPowerMode] action:@selector(lowPowerChanged:)];
    }
}

- (void)autoChanged:(UISwitch *)sender {
    [SFSettings setAutomaticSigning:sender.on];
    [self.tableView reloadData];
}

- (void)saveTimes:(NSArray *)times {
    [SFSettings setScheduleTimes:times];
    self.times = [SFSettings scheduleTimes];
    // Re-sort the rows after the picker closes, and refresh the "Next run" text.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 2)] withRowAnimation:UITableViewRowAnimationNone];
    });
}

- (void)addTime {
    if (![self canAddTime]) return;
    // Suggest 12 hours after the first time (e.g. 12 AM -> 12 PM), else the next free hour.
    NSInteger suggestion = (self.times.firstObject.integerValue + 12 * 60) % (24 * 60);
    while ([self.times containsObject:@(suggestion)]) suggestion = (suggestion + 60) % (24 * 60);
    [self presentTimePickerWithMinutes:suggestion heading:SFL(@"Add a time") onDone:^(NSInteger minutes) {
        [self saveTimes:[self.times arrayByAddingObject:@(minutes)]];
    }];
}

- (void)editTimeAtIndex:(NSInteger)index {
    if (index >= (NSInteger)self.times.count) return;
    NSString *heading = self.times.count > 1 ? [NSString stringWithFormat:SFL(@"Time %ld"), (long)index + 1] : SFL(@"Signing time");
    [self presentTimePickerWithMinutes:self.times[index].integerValue heading:heading onDone:^(NSInteger minutes) {
        NSMutableArray *times = [self.times mutableCopy];
        if (index < (NSInteger)times.count) times[index] = @(minutes);
        [self saveTimes:times];
    }];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != 1 || indexPath.row >= (NSInteger)self.times.count || self.times.count <= 1) return nil;
    UIContextualAction *remove = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:SFL(@"Remove") handler:^(UIContextualAction *action, UIView *view, void (^done)(BOOL)) {
        NSMutableArray *times = [self.times mutableCopy];
        [times removeObjectAtIndex:indexPath.row];
        [self saveTimes:times];
        done(YES);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[remove]];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 1) return;
    if (indexPath.row == [self addRow]) [self addTime];
    else if (indexPath.row < (NSInteger)self.times.count) [self editTimeAtIndex:indexPath.row];
}

- (void)dayTapped:(UIButton *)button {
    NSInteger days = [SFSettings scheduleDays];
    NSInteger bit = 1 << button.tag;
    NSInteger updated = button.selected ? (days & ~bit) : (days | bit);
    if (updated == 0) return; // keep at least one day
    [SFSettings setScheduleDays:updated];
    [self styleDay:button on:!button.selected];
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)wifiChanged:(UISwitch *)sender { [SFSettings setOnlyOnWiFi:sender.on]; }
- (void)chargingChanged:(UISwitch *)sender { [SFSettings setOnlyWhileCharging:sender.on]; }
- (void)parallelChanged:(UISwitch *)sender { [SFSettings setParallelSigning:sender.on]; }
- (void)retryChanged:(UISwitch *)sender { [SFSettings setRetryOnFailure:sender.on]; }
- (void)lowPowerChanged:(UISwitch *)sender { [SFSettings setSignInLowPowerMode:sender.on]; }

@end

#pragma mark - Servers

@interface SFServersViewController ()
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *servers;
@property (nonatomic) BOOL testing;
@end

@implementation SFServersViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = SFL(@"Anisette servers");
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:SFL(@"Test all") style:UIBarButtonItemStylePlain target:self action:@selector(testAll)];
    self.servers = [[SFAnisetteServers servers] mutableCopy];
    self.tableView.editing = YES;
    self.tableView.allowsSelectionDuringEditing = YES;
}

- (void)save {
    [SFAnisetteServers setServers:self.servers];
}

- (void)testAll {
    if (self.testing) return;
    self.testing = YES;
    self.navigationItem.rightBarButtonItem.enabled = NO;
    [self.tableView reloadData];
    [SFAnisetteServers testAllServersWithCompletion:^{
        self.testing = NO;
        self.navigationItem.rightBarButtonItem.enabled = YES;
        [self.tableView reloadData];
    }];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 4;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 1;
        case 1: return self.servers.count;
        case 2: return 2;
        default: return 1;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[@"", SFL(@"Order of use"), @"", SFL(@"Device identity sent to Apple")][section];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return SFL(@"Anisette servers provide the device data Apple asks for at every sign-in and signing step. With automatic fallback on, a slow or failing server hands over to the next one.");
    if (section == 1) return SFL(@"Drag to reorder. The server that worked last is tried first.");
    if (section == 3) return SFL(@"The same identity iloader 2.4.2 uses.");
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) return [self switchCellWithTitle:SFL(@"Automatic fallback") subtitle:SFL(@"Switch to the next server if one stalls") on:[SFAnisetteServers automaticFallback] action:@selector(fallbackChanged:)];
    if (indexPath.section == 2) {
        return indexPath.row == 0 ? [self buttonCellWithTitle:SFL(@"Add custom server") color:nil] : [self buttonCellWithTitle:SFL(@"Reset to defaults") color:[SFTheme secondaryText]];
    }
    if (indexPath.section == 3) return [self valueCellWithTitle:SFL(@"Identity") value:@"MacBookPro13,3 · Mac OS X 10.12.6"];

    NSDictionary *server = self.servers[indexPath.row];
    NSString *url = server[@"url"];
    NSURL *parsed = [NSURL URLWithString:url];
    NSDictionary *status = nil;
    for (NSString *key in [SFAnisetteServers statuses]) if ([key containsString:parsed.host ?: @"-"]) status = [SFAnisetteServers statuses][key];
    NSString *statusText = SFL(@"Not tested");
    UIColor *dot = [UIColor systemGrayColor];
    if (self.testing) statusText = SFL(@"Testing…");
    else if (status) {
        BOOL ok = [status[@"ok"] boolValue];
        NSInteger ms = [status[@"ms"] integerValue];
        if (!ok) { statusText = SFL(@"Offline"); dot = [SFTheme danger]; }
        else if (ms > 3000) { statusText = [NSString stringWithFormat:SFL(@"Slow · %ld ms"), (long)ms]; dot = [SFTheme warning]; }
        else { statusText = [NSString stringWithFormat:SFL(@"Online · %ld ms"), (long)ms]; dot = [SFTheme success]; }
    }
    UITableViewCell *cell = [self subtitleCellWithTitle:[NSString stringWithFormat:@"%ld. %@", (long)indexPath.row + 1, server[@"name"] ?: parsed.host] subtitle:[NSString stringWithFormat:@"%@\n%@", parsed.host ?: url, statusText]];
    UIListContentConfiguration *config = (UIListContentConfiguration *)cell.contentConfiguration;
    config.image = [UIImage systemImageNamed:@"circle.fill"];
    config.imageProperties.tintColor = dot;
    config.imageProperties.maximumSize = CGSizeMake(10, 10);
    config.secondaryTextProperties.numberOfLines = 2;
    cell.contentConfiguration = config;
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 1;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 1;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 1 && self.servers.count > 1 ? UITableViewCellEditingStyleDelete : UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 1;
}

- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)source toProposedIndexPath:(NSIndexPath *)proposed {
    if (proposed.section < 1) return [NSIndexPath indexPathForRow:0 inSection:1];
    if (proposed.section > 1) return [NSIndexPath indexPathForRow:self.servers.count - 1 inSection:1];
    return proposed;
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)source toIndexPath:(NSIndexPath *)destination {
    NSDictionary *server = self.servers[source.row];
    [self.servers removeObjectAtIndex:source.row];
    [self.servers insertObject:server atIndex:destination.row];
    [self save];
    dispatch_async(dispatch_get_main_queue(), ^{ [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationNone]; });
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (style != UITableViewCellEditingStyleDelete) return;
    [self.servers removeObjectAtIndex:indexPath.row];
    [self save];
    [tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 2) return;
    if (indexPath.row == 1) {
        self.servers = [[SFAnisetteServers defaultServers] mutableCopy];
        [self save];
        [self.tableView reloadData];
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:SFL(@"Add server") message:SFL(@"An anisette v3 server address.") preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = SFL(@"Name"); }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"https://ani.example.com";
        field.keyboardType = UIKeyboardTypeURL;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:SFL(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:SFL(@"Add") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *url = [alert.textFields[1].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (url.length == 0) return;
        if (![url hasPrefix:@"http"]) url = [@"https://" stringByAppendingString:url];
        NSString *name = alert.textFields[0].text.length > 0 ? alert.textFields[0].text : ([NSURL URLWithString:url].host ?: url);
        [self.servers addObject:@{ @"name": name, @"url": url }];
        [self save];
        [self.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)fallbackChanged:(UISwitch *)sender {
    [SFAnisetteServers setAutomaticFallback:sender.on];
}

@end

#pragma mark - Notifications

@interface SFNotificationSettingsViewController ()
@property (nonatomic, copy) NSString *permission;
@property (nonatomic) BOOL allowed;
@property (nonatomic) BOOL denied;
@end

@implementation SFNotificationSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = SFL(@"Notifications");
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.permission = SFL(@"Checking…");
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshPermission) name:UIApplicationWillEnterForegroundNotification object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshPermission];
}

- (void)refreshPermission {
    [[SFNotificationManager sharedInstance] fetchPermissionSummary:^(NSString *summary, BOOL allowed, BOOL denied) {
        self.permission = summary;
        self.allowed = allowed;
        self.denied = denied;
        [self.tableView reloadData];
    }];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 4;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return self.allowed ? 1 : 2;
    if (section == 1) return 3;
    if (section == 2) return 2;
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[SFL(@"Permission"), SFL(@"Notify me when"), SFL(@"While Sevenfold is open"), @""][section];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        if (self.denied) return SFL(@"Notifications for Sevenfold are off in iOS Settings, so nothing can appear on the lock screen.");
        if (!self.allowed) return SFL(@"Sevenfold hasn't been allowed to send notifications yet.");
        if ([self.permission containsString:@"lock screen off"]) return @"Turn on Lock Screen for Sevenfold in iOS Settings › Notifications to see results there.";
        return nil;
    }
    if (section == 1) return SFL(@"Sent after automatic runs, and after manual runs when Sevenfold isn't open.");
    if (section == 2) return [SFPopup deviceHasDynamicIsland]
        ? SFL(@"Results pop out of the Dynamic Island while you're using Sevenfold.")
        : SFL(@"Results slide down from the top of the screen while you're using Sevenfold.");
    return SFL(@"Arrives after 5 seconds, so you can lock your iPhone first and check the lock screen.");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            UITableViewCell *cell = [self valueCellWithTitle:SFL(@"Status") value:self.permission];
            UIListContentConfiguration *config = (UIListContentConfiguration *)cell.contentConfiguration;
            config.secondaryTextProperties.color = self.allowed && ![self.permission containsString:@"off"] ? [SFTheme success] : [SFTheme warning];
            cell.contentConfiguration = config;
            return cell;
        }
        return [self buttonCellWithTitle:self.denied ? SFL(@"Open iOS Settings") : SFL(@"Allow notifications") color:nil];
    }
    if (indexPath.section == 2) {
        if (indexPath.row == 0) return [self switchCellWithTitle:SFL(@"Show pop-up") subtitle:[SFPopup deviceHasDynamicIsland] ? SFL(@"From the Dynamic Island") : SFL(@"At the top of the screen")
                                                              on:[SFSettings showInAppPopups] action:@selector(popupChanged:)];
        return [self buttonCellWithTitle:SFL(@"Preview pop-up") color:nil];
    }
    if (indexPath.section == 3) return [self buttonCellWithTitle:SFL(@"Send a test notification") color:nil];
    switch (indexPath.row) {
        case 0: return [self switchCellWithTitle:SFL(@"Signing succeeded") subtitle:SFL(@"\"Signed 4 apps · valid until Nov 29\"") on:[SFSettings notifyOnSuccess] action:@selector(successChanged:)];
        case 1: return [self switchCellWithTitle:SFL(@"Signing failed") subtitle:SFL(@"Which app failed and why") on:[SFSettings notifyOnFailure] action:@selector(failureChanged:)];
        default: return [self switchCellWithTitle:SFL(@"Expiring soon") subtitle:SFL(@"When an app has under a day left") on:[SFSettings notifyOnExpiry] action:@selector(expiryChanged:)];
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0 && indexPath.row == 1) {
        if (self.denied) {
            [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString] options:@{} completionHandler:nil];
        } else {
            [[UNUserNotificationCenter currentNotificationCenter] requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge)
                                                                                completionHandler:^(BOOL granted, NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{ [self refreshPermission]; });
            }];
        }
        return;
    }
    if (indexPath.section == 2 && indexPath.row == 1) {
        static BOOL failureNext = NO;
        if (failureNext) {
            [SFPopup showWithTitle:SFL(@"Couldn't sign Sevenfold") subtitle:SFL(@"Preview · tap Preview again for success") style:SFPopupStyleFailure
                              icon:nil retry:^{ [SFPopup showWithTitle:SFL(@"Retry tapped") subtitle:SFL(@"In a real failure this signs the app again") style:SFPopupStyleInfo]; }];
        } else {
            [SFPopup showWithTitle:SFL(@"Signed Sevenfold") subtitle:SFL(@"Valid for 7 days") style:SFPopupStyleSuccess];
        }
        failureNext = !failureNext;
        return;
    }
    if (indexPath.section != 3) return;
    [[SFNotificationManager sharedInstance] sendSevenfoldNotificationWithTitle:SFL(@"Signed 1 app")
                                                                           body:SFL(@"This is a test from Sevenfold. Real results look like this.")
                                                                     identifier:@"sf.test"
                                                                          delay:5];
    [self showMessage:SFL(@"Lock your iPhone now. The test notification arrives in 5 seconds.") title:SFL(@"Test sent")];
}

- (void)popupChanged:(UISwitch *)sender { [SFSettings setShowInAppPopups:sender.on]; }
- (void)successChanged:(UISwitch *)sender { [SFSettings setNotifyOnSuccess:sender.on]; }
- (void)failureChanged:(UISwitch *)sender { [SFSettings setNotifyOnFailure:sender.on]; }
- (void)expiryChanged:(UISwitch *)sender { [SFSettings setNotifyOnExpiry:sender.on]; }

@end

#pragma mark - Diagnostics

@interface SFDiagnosticsViewController ()
@property (nonatomic, strong) NSArray<NSDictionary *> *entries;
@property (nonatomic, strong) NSArray<NSDictionary *> *daemonEntries;
@property (nonatomic) BOOL testRunning;
@end

@implementation SFDiagnosticsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = SFL(@"Diagnostics");
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(shareLog)];
    [self reload];
}

+ (NSArray<NSDictionary *> *)daemonLogEntries:(NSUInteger)limit {
    NSString *text = [NSString stringWithContentsOfFile:@"/var/mobile/Library/Application Support/Sevenfold/daemon.log" encoding:NSUTF8StringEncoding error:nil];
    NSMutableArray *entries = [NSMutableArray array];
    for (NSString *line in [[text componentsSeparatedByString:@"\n"] reverseObjectEnumerator]) {
        NSRange tab = [line rangeOfString:@"\t"];
        if (tab.location == NSNotFound) continue;
        [entries addObject:@{ @"date": [NSDate dateWithTimeIntervalSince1970:[[line substringToIndex:tab.location] doubleValue]],
                              @"message": [line substringFromIndex:tab.location + 1] }];
        if (entries.count >= limit) break;
    }
    return entries;
}

+ (NSDate *)daemonNextRun {
    CFPropertyListRef value = CFPreferencesCopyValue(CFSTR("nextFireDate"), CFSTR("com.t4mag0.sevenfold"), kCFPreferencesCurrentUser, kCFPreferencesCurrentHost);
    id object = CFBridgingRelease(value);
    return [object isKindOfClass:[NSDate class]] ? object : nil;
}

- (void)reload {
    self.entries = [SFLog recentEntries:80];
    self.daemonEntries = [SFDiagnosticsViewController daemonLogEntries:60];
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 4;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 6;
    if (section == 1) return 2;   // background test, clear activity
    if (section == 2) return MAX(self.entries.count, 1);
    return MAX(self.daemonEntries.count, 1);
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[SFL(@"Status"), SFL(@"Tests"), SFL(@"App activity"), SFL(@"Background service activity")][section];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 3) return SFL(@"What the background service did: when it planned the next run, when the time came, and whether it opened Sevenfold to sign.");
    return nil;
}

- (UITableViewCell *)statusCell:(NSString *)title detail:(NSString *)detail ok:(BOOL)ok {
    UITableViewCell *cell = [self subtitleCellWithTitle:title subtitle:detail];
    UIListContentConfiguration *config = (UIListContentConfiguration *)cell.contentConfiguration;
    config.image = [UIImage systemImageNamed:ok ? @"checkmark.circle.fill" : @"exclamationmark.circle.fill"];
    config.imageProperties.tintColor = ok ? [SFTheme success] : [SFTheme warning];
    cell.contentConfiguration = config;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        switch (indexPath.row) {
            case 0: {
                BOOL connected = [(AppDelegate *)[UIApplication sharedApplication].delegate daemonConnected];
                return [self statusCell:SFL(@"Background service") detail:connected ? SFL(@"Running") : SFL(@"Not connected. Reinstall Sevenfold or reboot.") ok:connected];
            }
            case 1: {
                NSDictionary *run = [SFSettings lastRun];
                if (!run) return [self statusCell:SFL(@"Last run") detail:SFL(@"No runs yet") ok:YES];
                NSString *detail = [NSString stringWithFormat:SFL(@"%@ · %@ · %@ signed%@"),
                                    [SFTheme shortDateTime:run[@"date"]], [run[@"automatic"] boolValue] ? @"automatic" : @"manual",
                                    run[@"signed"], [run[@"failed"] integerValue] > 0 ? [NSString stringWithFormat:SFL(@", %@ failed"), run[@"failed"]] : @""];
                return [self statusCell:SFL(@"Last run") detail:detail ok:[run[@"failed"] integerValue] == 0];
            }
            case 2: {
                BOOL signedIn = [SFSettings isSignedIn];
                return [self statusCell:SFL(@"Apple ID") detail:signedIn ? ([SFSettings displayEmail] ?: SFL(@"Signed in")) : SFL(@"Not signed in") ok:signedIn];
            }
            case 3: {
                NSString *server = [SFAnisetteServers lastGoodServer];
                return [self statusCell:SFL(@"Anisette server") detail:server ? [NSString stringWithFormat:SFL(@"%@ · last worked"), [SFAnisetteServers nameForServer:server]] : SFL(@"Not used yet") ok:server != nil];
            }
            case 5: {
                NSDate *planned = [SFDiagnosticsViewController daemonNextRun];
                if (![SFSettings automaticSigning]) return [self statusCell:SFL(@"Next automatic run") detail:SFL(@"Automatic signing is off") ok:YES];
                if (!planned) return [self statusCell:SFL(@"Next automatic run") detail:SFL(@"Background service hasn't planned one yet") ok:NO];
                BOOL matches = fabs([planned timeIntervalSinceDate:[SFSettings nextScheduledRun]]) < 90;
                NSString *detail = [NSString stringWithFormat:@"%@%@", [SFTheme shortDateTime:planned],
                                    matches ? @"" : [NSString stringWithFormat:SFL(@" · schedule says %@"), [SFTheme shortDateTime:[SFSettings nextScheduledRun]]]];
                return [self statusCell:SFL(@"Next automatic run") detail:detail ok:matches || [planned timeIntervalSinceNow] < 0];
            }
            default: {
                BOOL key = [SFCertificateStore hasPrivateKey];
                return [self statusCell:SFL(@"Signing key") detail:key ? SFL(@"Stored on this iPhone") : SFL(@"Created at first signing") ok:YES];
            }
        }
    }
    if (indexPath.section == 1) {
        if (indexPath.row == 0) return [self buttonCellWithTitle:self.testRunning ? SFL(@"Running background test…") : SFL(@"Run a background test now") color:nil];
        return [self buttonCellWithTitle:SFL(@"Clear activity") color:[SFTheme danger]];
    }
    if (indexPath.section == 3) {
        if (self.daemonEntries.count == 0) return [self subtitleCellWithTitle:SFL(@"No activity yet") subtitle:SFL(@"Appears after the background service restarts with this version")];
        NSDictionary *entry = self.daemonEntries[indexPath.row];
        NSDateFormatter *formatter = [NSDateFormatter new];
        formatter.dateFormat = @"MMM d  HH:mm:ss";
        UITableViewCell *cell = [self subtitleCellWithTitle:entry[@"message"] subtitle:[formatter stringFromDate:entry[@"date"]]];
        UIListContentConfiguration *config = (UIListContentConfiguration *)cell.contentConfiguration;
        config.textProperties.font = [SFTheme monoFontOfSize:13];
        config.secondaryTextProperties.font = [SFTheme monoFontOfSize:11];
        cell.contentConfiguration = config;
        return cell;
    }
    if (self.entries.count == 0) return [self subtitleCellWithTitle:SFL(@"No activity yet") subtitle:nil];
    NSDictionary *entry = self.entries[indexPath.row];
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateFormat = @"MMM d  HH:mm:ss";
    UITableViewCell *cell = [self subtitleCellWithTitle:entry[@"message"] subtitle:[formatter stringFromDate:entry[@"date"]]];
    UIListContentConfiguration *config = (UIListContentConfiguration *)cell.contentConfiguration;
    config.textProperties.font = [SFTheme monoFontOfSize:13];
    NSInteger level = [entry[@"level"] integerValue];
    config.textProperties.color = level == SFLogLevelError ? [SFTheme danger] : level == SFLogLevelWarning ? [SFTheme warning] : level == SFLogLevelOK ? [SFTheme success] : [UIColor labelColor];
    config.secondaryTextProperties.font = [SFTheme monoFontOfSize:11];
    cell.contentConfiguration = config;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 1) return;
    if (indexPath.row == 1) {
        [SFLog clear];
        [self reload];
        return;
    }
    if (self.testRunning) return;
    self.testRunning = YES;
    [self.tableView reloadData];
    [(AppDelegate *)[UIApplication sharedApplication].delegate requestDebuggingBackgroundSigningWithCompletion:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.testRunning = NO;
            [self reload];
            BOOL nothingDue = [error.localizedDescription containsString:@"No applications"];
            if (error && !nothingDue) [self showError:error title:SFL(@"Background test")];
            else [self showMessage:nothingDue ? SFL(@"The background service works. No apps needed signing right now.") : SFL(@"The background service signed your apps.") title:SFL(@"Background test passed")];
        });
    }];
}

- (void)shareLog {
    NSMutableString *text = [[SFLog exportText] mutableCopy];
    [text appendString:@"\n--- Background service ---\n"];
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    for (NSDictionary *entry in [[SFDiagnosticsViewController daemonLogEntries:500] reverseObjectEnumerator])
        [text appendFormat:@"%@  %@\n", [formatter stringFromDate:entry[@"date"]], entry[@"message"]];
    NSURL *url = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:@"Sevenfold-activity.txt"];
    [text writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil];
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    share.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    [self presentViewController:share animated:YES completion:nil];
}

@end
