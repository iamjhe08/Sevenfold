#import <objc/runtime.h>
//
//  SFCertificatesViewController.m
//  Sevenfold
//
//  Shows each certificate on the Apple ID: which tool and iPhone model
//  created it, which iPhones use it, when it expires, and lets you share
//  or revoke it. Also lists the iPhones registered to the Apple ID.
//

#import "SFCertificatesViewController.h"
#import "SFCertificateReminder.h"
#import "SFLog.h"
#import "SFLocalization.h"
#import "SFCertificateStore.h"
#import "SFShareCertificateViewController.h"
#import "SFProgressBar.h"
#import "SFSettings.h"
#import "SFTheme.h"
#import "SFDevice.h"
#import "SFRootController.h"
#import "SFSigningSession.h"

@interface SFCertificatesViewController ()
@property (nonatomic, strong) NSArray<SFCertificate *> *certificates;
@property (nonatomic, strong) NSArray<SFRegisteredDevice *> *devices;
@property (nonatomic, strong) NSError *loadError;
@property (nonatomic) BOOL loading;
/// Revoked in this session; kept off the list even if Apple still returns them for a moment.
@property (nonatomic, strong) NSSet<NSString *> *revokedIdentifiers;
@end

#pragma mark - Revoke confirmation sheet

@interface SFRevokeSheetController : UIViewController
@property (nonatomic, strong) SFCertificate *certificate;
@property (nonatomic, weak) UITabBarController *presenterTabBar;
@property (nonatomic, copy) void (^completion)(BOOL revoked);
@property (nonatomic, strong) UIButton *revokeButton;
@property (nonatomic, strong) UILabel *errorLabel;
@property (nonatomic) BOOL finished;
- (instancetype)initWithCertificate:(SFCertificate *)certificate;
@end

@implementation SFRevokeSheetController

- (instancetype)initWithCertificate:(SFCertificate *)certificate {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _certificate = certificate;
        self.modalPresentationStyle = UIModalPresentationPageSheet;
        UISheetPresentationController *sheet = self.sheetPresentationController;
        sheet.prefersGrabberVisible = YES;
        sheet.preferredCornerRadius = 28;
        sheet.detents = @[[UISheetPresentationControllerDetent largeDetent]];
    }
    return self;
}

- (UIView *)bulletWithText:(NSString *)text bold:(NSArray<NSString *> *)boldParts color:(UIColor *)dot {
    UIView *row = [UIView new];
    UIView *bullet = [UIView new];
    bullet.backgroundColor = dot;
    bullet.layer.cornerRadius = 4;
    bullet.translatesAutoresizingMaskIntoConstraints = NO;
    UILabel *label = [SFTheme labelWithSize:15 weight:UIFontWeightRegular color:[UIColor labelColor]];
    label.numberOfLines = 0;
    NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] initWithString:text attributes:@{ NSFontAttributeName: [UIFont systemFontOfSize:15] }];
    for (NSString *part in boldParts) {
        NSRange range = [text rangeOfString:part];
        if (range.location != NSNotFound) [attr addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:15 weight:UIFontWeightBold] range:range];
    }
    label.attributedText = attr;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:bullet];
    [row addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [bullet.widthAnchor constraintEqualToConstant:8],
        [bullet.heightAnchor constraintEqualToConstant:8],
        [bullet.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:16],
        [bullet.topAnchor constraintEqualToAnchor:label.topAnchor constant:6],
        [label.leadingAnchor constraintEqualToAnchor:bullet.trailingAnchor constant:12],
        [label.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-16],
        [label.topAnchor constraintEqualToAnchor:row.topAnchor constant:13],
        [label.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-13],
    ]];
    return row;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [SFTheme background];
    SFCertificate *certificate = self.certificate;
    NSArray<NSString *> *apps = certificate.appsSignedHere ?: @[];

    // Header
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"xmark.shield.fill"
                                                                  withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:28 weight:UIImageSymbolWeightSemibold]]];
    icon.tintColor = [SFTheme danger];
    icon.contentMode = UIViewContentModeCenter;
    icon.backgroundColor = [[SFTheme danger] colorWithAlphaComponent:0.14];
    icon.layer.cornerRadius = 30;
    [icon.widthAnchor constraintEqualToConstant:60].active = YES;
    [icon.heightAnchor constraintEqualToConstant:60].active = YES;
    UILabel *title = [SFTheme labelWithSize:22 weight:UIFontWeightHeavy color:[UIColor labelColor]];
    title.text = SFL(@"Revoke this certificate?");
    title.textAlignment = NSTextAlignmentCenter;
    UILabel *subtitle = [SFTheme labelWithSize:14 weight:UIFontWeightRegular color:[SFTheme secondaryText]];
    NSMutableArray *bits = [NSMutableArray arrayWithObject:[NSString stringWithFormat:@"%@ · %@", certificate.toolName, certificate.creatorName]];
    if (certificate.expirationDate) {
        NSDateFormatter *f = [NSDateFormatter new];
        f.dateFormat = @"MMM yyyy";
        [bits addObject:[NSString stringWithFormat:SFL(@"expires %@"), [f stringFromDate:certificate.expirationDate]]];
    }
    subtitle.text = [bits componentsJoinedByString:@" · "];
    subtitle.textAlignment = NSTextAlignmentCenter;
    subtitle.numberOfLines = 2;

    // What happens
    UIStackView *list = [UIStackView new];
    list.axis = UILayoutConstraintAxisVertical;
    list.backgroundColor = [SFTheme card];
    list.layer.cornerRadius = 18;
    list.layer.cornerCurve = kCACornerCurveContinuous;
    UIColor *red = [SFTheme danger];
    if (apps.count > 0) {
        NSString *names = [apps componentsJoinedByString:@", "];
        [list addArrangedSubview:[self bulletWithText:[NSString stringWithFormat:(apps.count == 1 ? SFL(@"%@ on this iPhone stops opening until it's signed again.") : SFL(@"%@ on this iPhone stop opening until they're signed again.")), names]
                                                 bold:@[names] color:red]];
    } else if (certificate.usedByThisDevice) {
        [list addArrangedSubview:[self bulletWithText:SFL(@"Apps this iPhone signed stop opening until they're signed again.") bold:@[] color:red]];
    } else {
        [list addArrangedSubview:[self bulletWithText:SFL(@"No apps on this iPhone use it.") bold:@[] color:[SFTheme success]]];
    }
    NSArray *users = certificate.usedByDescriptions ?: @[];
    NSArray *others = certificate.usedByThisDevice && users.count > 1 ? [users subarrayWithRange:NSMakeRange(1, users.count - 1)]
                                                                       : (certificate.usedByThisDevice ? @[] : users);
    if (others.count > 0) {
        NSString *names = [others componentsJoinedByString:@", "];
        [list addArrangedSubview:[self bulletWithText:[NSString stringWithFormat:(others.count == 1 ? SFL(@"%@ also uses it. Its apps stop too until you share a new certificate.") : SFL(@"%@ also use it. Their apps stop too until you share a new certificate.")), names]
                                                 bold:@[names] color:red]];
    } else if (!certificate.usedByThisDevice) {
        [list addArrangedSubview:[self bulletWithText:[NSString stringWithFormat:SFL(@"If another device (%@) still uses it, its apps stop until they're signed again."), certificate.creatorName]
                                                 bold:@[] color:red]];
    }
    [list addArrangedSubview:[self bulletWithText:SFL(@"It's removed from the Certificates list right away. Sevenfold makes a new one the next time you sign.") bold:@[] color:[SFTheme amber]]];
    for (NSUInteger i = 1; i < list.arrangedSubviews.count; i++) {
        UIView *line = [UIView new];
        line.backgroundColor = [SFTheme separator];
        line.translatesAutoresizingMaskIntoConstraints = NO;
        UIView *row = list.arrangedSubviews[i];
        [row addSubview:line];
        [NSLayoutConstraint activateConstraints:@[
            [line.heightAnchor constraintEqualToConstant:1 / UIScreen.mainScreen.scale],
            [line.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:16],
            [line.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
            [line.topAnchor constraintEqualToAnchor:row.topAnchor],
        ]];
    }


    self.errorLabel = [SFTheme labelWithSize:14 weight:UIFontWeightRegular color:[SFTheme danger]];
    self.errorLabel.numberOfLines = 0;
    self.errorLabel.textAlignment = NSTextAlignmentCenter;
    self.errorLabel.hidden = YES;

    UIButtonConfiguration *revoke = [UIButtonConfiguration filledButtonConfiguration];
    revoke.title = SFL(@"Revoke certificate");
    revoke.baseBackgroundColor = [UIColor systemRedColor];
    revoke.baseForegroundColor = [UIColor whiteColor];
    revoke.cornerStyle = UIButtonConfigurationCornerStyleLarge;
    revoke.contentInsets = NSDirectionalEdgeInsetsMake(16, 16, 16, 16);
    revoke.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *attrs) {
        NSMutableDictionary *m = [attrs mutableCopy];
        m[NSFontAttributeName] = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
        return m;
    };
    self.revokeButton = [UIButton buttonWithConfiguration:revoke primaryAction:nil];
    [self.revokeButton addTarget:self action:@selector(revokeTapped) forControlEvents:UIControlEventTouchUpInside];

    UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem];
    [cancel setTitle:SFL(@"Cancel") forState:UIControlStateNormal];
    cancel.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    cancel.tintColor = [SFTheme accent];
    [cancel addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];
    [cancel.heightAnchor constraintEqualToConstant:44].active = YES;

    UIStackView *head = [[UIStackView alloc] initWithArrangedSubviews:@[icon, title, subtitle]];
    head.axis = UILayoutConstraintAxisVertical;
    head.alignment = UIStackViewAlignmentCenter;
    head.spacing = 8;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[head, list, self.errorLabel, self.revokeButton, cancel]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 16;
    [stack setCustomSpacing:6 afterView:self.revokeButton];
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = NO;
    [self.view addSubview:scroll];
    [scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.trailingAnchor constant:-20],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:28],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-20],
    ]];

    // Fit the sheet to its content where iOS allows it (iOS 16+).
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
    if ([UISheetPresentationControllerDetent respondsToSelector:@selector(customDetentWithIdentifier:resolver:)]) {
        __weak typeof(self) weakSelf = self;
        UISheetPresentationControllerDetent *fit = [UISheetPresentationControllerDetent customDetentWithIdentifier:@"fit" resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> context) {
            CGFloat width = weakSelf.view.bounds.size.width ?: 390;
            CGSize size = [stack systemLayoutSizeFittingSize:CGSizeMake(width - 40, 0) withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
            return MIN(size.height + 48 + weakSelf.view.safeAreaInsets.bottom, context.maximumDetentValue);
        }];
        self.sheetPresentationController.detents = @[fit];
    } else {
        self.sheetPresentationController.detents = @[[UISheetPresentationControllerDetent mediumDetent], [UISheetPresentationControllerDetent largeDetent]];
    }
#pragma clang diagnostic pop
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (!self.finished && self.completion) { self.finished = YES; self.completion(NO); }
}

- (void)cancelTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)revokeTapped {
    self.errorLabel.hidden = YES;
    UIButtonConfiguration *config = self.revokeButton.configuration;
    config.title = SFL(@"Revoking…");
    config.showsActivityIndicator = YES;
    self.revokeButton.configuration = config;
    self.revokeButton.enabled = NO;
    self.modalInPresentation = YES;
    [SFCertificateStore revokeCertificate:self.certificate completion:^(NSError *error) {
        if (error) {
            UIButtonConfiguration *again = self.revokeButton.configuration;
            again.title = SFL(@"Try again");
            again.showsActivityIndicator = NO;
            self.revokeButton.configuration = again;
            self.revokeButton.enabled = YES;
            self.modalInPresentation = NO;
            self.errorLabel.text = [NSString stringWithFormat:SFL(@"Couldn't revoke: %@"), error.localizedDescription];
            self.errorLabel.hidden = NO;
            return;
        }
        self.finished = YES;
        void (^completion)(BOOL) = self.completion;
        [self dismissViewControllerAnimated:YES completion:^{
            if (completion) completion(YES);
        }];
    }];
}

@end

static BOOL SFSerialHidden = NO;
static char SFSerialKey;

@implementation SFCertificatesViewController

- (void)serialHeld:(UILongPressGestureRecognizer *)hold {
    if (hold.state != UIGestureRecognizerStateBegan) return;
    NSString *serial = objc_getAssociatedObject(hold, &SFSerialKey);
    if (!serial.length) return;
    [UIPasteboard generalPasteboard].string = serial;
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    UIView *cell = hold.view;
    [UIView animateWithDuration:0.12 animations:^{ cell.transform = CGAffineTransformMakeScale(1.03, 1.03); }
                     completion:^(BOOL done) { [UIView animateWithDuration:0.2 animations:^{ cell.transform = CGAffineTransformIdentity; }]; }];
    [self showCopiedToast:SFL(@"Serial copied")];
}

- (void)showCopiedToast:(NSString *)text {
    UIView *host = self.view.window ?: self.view;
    UIView *toast = [UIView new];
    toast.backgroundColor = [UIColor colorWithRed:0.17 green:0.19 blue:0.25 alpha:0.97];
    toast.layer.cornerRadius = 22;
    toast.layer.cornerCurve = kCACornerCurveContinuous;
    UIImageView *check = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightBold]]];
    check.tintColor = [UIColor systemGreenColor];
    UILabel *label = [SFTheme labelWithSize:15 weight:UIFontWeightSemibold color:[UIColor whiteColor]];
    label.text = text;
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[check, label]];
    stack.spacing = 8;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    toast.translatesAutoresizingMaskIntoConstraints = NO;
    [toast addSubview:stack];
    [host addSubview:toast];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:toast.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:toast.trailingAnchor constant:-20],
        [stack.topAnchor constraintEqualToAnchor:toast.topAnchor constant:12],
        [stack.bottomAnchor constraintEqualToAnchor:toast.bottomAnchor constant:-12],
        [toast.centerXAnchor constraintEqualToAnchor:host.centerXAnchor],
        [toast.bottomAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.bottomAnchor constant:-96],
    ]];
    toast.alpha = 0;
    [UIView animateWithDuration:0.2 animations:^{ toast.alpha = 1; } completion:^(BOOL done) {
        [UIView animateWithDuration:0.25 delay:1.5 options:0 animations:^{ toast.alpha = 0; } completion:^(BOOL d) { [toast removeFromSuperview]; }];
    }];
}

- (void)toggleSerial {
    SFSerialHidden = !SFSerialHidden;
    [self.tableView reloadData];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.refreshControl = [UIRefreshControl new];
    [self.refreshControl addTarget:self action:@selector(load) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"square.and.arrow.up.on.square"]
                                                                              style:UIBarButtonItemStylePlain target:self action:@selector(openShare)];
    self.navigationItem.rightBarButtonItem.accessibilityLabel = SFL(@"Share with another iPhone");
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(load) name:@"com.t4mag0.sevenfold/userDidSignIn" object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self load];
}

- (void)load {
    if (![SFSettings isSignedIn]) {
        self.certificates = @[];
        self.devices = @[];
        [self.tableView reloadData];
        [self.refreshControl endRefreshing];
        return;
    }
    if (self.loading) return;
    self.loading = YES;
    if (!self.certificates) [self.tableView reloadData];
    [SFCertificateStore fetchCertificatesWithCompletion:^(NSArray<SFCertificate *> *certificates, NSError *error) {
        self.loadError = error;
        if (certificates) {
            NSMutableArray *kept = [NSMutableArray array];
            for (SFCertificate *c in certificates) if (![self.revokedIdentifiers containsObject:c.identifier]) [kept addObject:c];
            self.certificates = kept;
        }
        [SFCertificateStore fetchRegisteredDevicesWithCompletion:^(NSArray<SFRegisteredDevice *> *devices, NSError *deviceError) {
            self.loading = NO;
            // The iPhone you're looking from is always listed first; the rest keep Apple's order.
            if (devices) {
                NSMutableArray *sorted = [NSMutableArray arrayWithCapacity:devices.count];
                for (SFRegisteredDevice *d in devices) if (d.isThisDevice) [sorted addObject:d];
                for (SFRegisteredDevice *d in devices) if (!d.isThisDevice) [sorted addObject:d];
                self.devices = sorted;
            }
            // The iPhone that shared a certificate never hears back from the one that imported it, so
            // name the shared-with iPhones from this Apple ID's other registered iPhones.
            NSMutableArray *otherModels = [NSMutableArray array];
            for (SFRegisteredDevice *device in self.devices)
                if (!device.isThisDevice && device.model.length > 0) [otherModels addObject:device.model];
            for (SFCertificate *certificate in self.certificates) certificate.otherRegisteredModels = otherModels;
            [self.refreshControl endRefreshing];
            [self.tableView reloadData];
        }];
    }];
}

- (void)openShare {
    [self.navigationController pushViewController:[SFShareCertificateViewController new] animated:YES];
}

// MARK: - Renew (last 14 days of this iPhone's certificate)

/// This iPhone's certificate when it's in its last two weeks, else nil.
- (SFCertificate *)renewCertificate {
    for (SFCertificate *certificate in self.certificates) {
        if (!certificate.usedByThisDevice || !certificate.expirationDate) continue;
        NSTimeInterval left = certificate.expirationDate.timeIntervalSinceNow;
        if (left > 0 && left < [SFCertificateReminder bannerDays] * 24 * 3600) return certificate;
    }
    return nil;
}

- (UITableViewCell *)renewCell:(SFCertificate *)certificate {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
        return t.userInterfaceStyle == UIUserInterfaceStyleDark ? [UIColor colorWithRed:0.23 green:0.16 blue:0.07 alpha:1] : [UIColor colorWithRed:1 green:0.95 blue:0.86 alpha:1];
    }];
    NSInteger days = MAX(1, (NSInteger)ceil(certificate.expirationDate.timeIntervalSinceNow / 86400.0));
    NSDateFormatter *formatter = [NSDateFormatter new];
    [formatter setLocalizedDateFormatFromTemplate:@"d MMM"];
    UILabel *title = [SFTheme labelWithSize:15 weight:UIFontWeightBold color:[SFTheme warning]];
    title.text = [NSString stringWithFormat:SFL(@"Expires in %ld days · %@"), (long)days, [formatter stringFromDate:certificate.expirationDate]];
    title.numberOfLines = 0;
    UILabel *body = [SFTheme labelWithSize:14 weight:UIFontWeightRegular color:[UIColor labelColor]];
    body.text = SFL(@"Renewing replaces this certificate with a new one, then signs all your apps again so they keep working.");
    body.numberOfLines = 0;
    UIButtonConfiguration *config = [UIButtonConfiguration filledButtonConfiguration];
    config.title = SFL(@"Renew and sign all apps");
    config.baseBackgroundColor = [SFTheme amber];
    config.baseForegroundColor = [UIColor colorWithWhite:0.07 alpha:1];
    config.cornerStyle = UIButtonConfigurationCornerStyleLarge;
    UIButton *button = [UIButton buttonWithConfiguration:config primaryAction:nil];
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    [button addTarget:self action:@selector(renewTapped:) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[title, body, button]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 10;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:stack];
    UILayoutGuide *m = cell.contentView.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:14],
        [stack.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-14],
        [stack.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
    ]];
    return cell;
}

- (void)renewTapped:(UIButton *)sender {
    SFCertificate *certificate = [self renewCertificate];
    if (!certificate) return;
    NSString *message = SFL(@"Sevenfold revokes this certificate, makes a new one and signs all your apps again. Keep the app open until it finishes.");
    if ([SFCertificateStore sharedWithCount] > 0) message = [message stringByAppendingFormat:@"\n\n%@", SFL(@"You shared this certificate with another iPhone. Afterwards, share the new one again from Certificates › Share with another iPhone.")];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:SFL(@"Renew certificate?")
        message:message
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SFL(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:SFL(@"Renew") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        sender.enabled = NO;
        [SFCertificateStore revokeCertificate:certificate completion:^(NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                sender.enabled = YES;
                if (error) { [self showError:error title:SFL(@"Couldn't renew")]; return; }
                SFLogEvent(SFLogLevelInfo, @"certificate · renewed by revoking the old one; signing all apps");
                NSMutableSet *revoked = [self.revokedIdentifiers mutableCopy] ?: [NSMutableSet set];
                [revoked addObject:certificate.identifier];
                self.revokedIdentifiers = revoked;
                [[NSNotificationCenter defaultCenter] postNotificationName:SFSignAllRequestedNotification object:nil];
            });
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

// MARK: - Sections: 0 slots, 1…n certificates, last = devices

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2 + self.certificates.count;
}

- (BOOL)isDevicesSection:(NSInteger)section {
    return section == 1 + (NSInteger)self.certificates.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return [self renewCertificate] ? 2 : 1;
    if ([self isDevicesSection:section]) return MAX(self.devices.count, 1);
    // header, created by, used by, apps here, expires, serial, then Share (if this iPhone uses it) and Revoke
    SFCertificate *certificate = self.certificates[section - 1];
    return certificate.usedByThisDevice ? 8 : 7;
}

- (BOOL)isShareRow:(NSIndexPath *)indexPath certificate:(SFCertificate *)certificate {
    return certificate.usedByThisDevice && indexPath.row == 6;
}

- (BOOL)isRevokeRow:(NSIndexPath *)indexPath certificate:(SFCertificate *)certificate {
    return indexPath.row == (certificate.usedByThisDevice ? 7 : 6);
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if ([self isDevicesSection:section]) return SFL(@"Registered iPhones");
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        if (![SFSettings isSignedIn]) return SFL(@"Sign in to see your certificates.");
        if (self.loadError) return [NSString stringWithFormat:SFL(@"Couldn't load certificates: %@"), self.loadError.localizedDescription];
        return SFL(@"Free Apple IDs allow two certificates. Share one certificate between your iPhones so they don't use up both slots or revoke each other.");
    }
    if ([self isDevicesSection:section]) return SFL(@"Every iPhone that signs with this Apple ID is registered here by Apple.");
    return nil;
}

- (UITableViewCell *)slotsCell {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.backgroundColor = [SFTheme card];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    UILabel *title = [SFTheme labelWithSize:15 weight:UIFontWeightMedium color:[SFTheme secondaryText]];
    title.text = SFL(@"Slots used");
    UILabel *value = [SFTheme labelWithSize:22 weight:UIFontWeightBold color:[UIColor labelColor]];
    NSUInteger used = self.certificates.count;
    value.text = self.loading && !self.certificates ? @"…" : [NSString stringWithFormat:SFL(@"%lu of 2"), (unsigned long)used];
    value.textAlignment = [SFLanguage isRightToLeft] ? NSTextAlignmentLeft : NSTextAlignmentRight;
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[title, value]];
    row.alignment = UIStackViewAlignmentCenter;
    SFProgressBar *bar = [SFProgressBar new];
    [bar.heightAnchor constraintEqualToConstant:8].active = YES;
    bar.complete = used < 2;
    [bar setProgress:MIN(used / 2.0, 1.0) animated:NO];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[row, bar]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 10;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:stack];
    UILayoutGuide *m = cell.contentView.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:14],
        [stack.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-14],
        [stack.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
    ]];
    return cell;
}

- (UITableViewCell *)certificateHeaderCell:(SFCertificate *)certificate {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.backgroundColor = [SFTheme card];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    BOOL signsHere = certificate.usedByThisDevice || certificate.appsSignedHere.count > 0;
    UIImageView *icon = [[UIImageView alloc] initWithImage:[SFTheme settingsIcon:@"checkmark.seal.fill" color:signsHere ? [SFTheme accent] : [UIColor systemGrayColor]]];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [icon.widthAnchor constraintEqualToConstant:30].active = YES;
    [icon.heightAnchor constraintEqualToConstant:30].active = YES;
    [icon setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [icon setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    UILabel *title = [SFTheme labelWithSize:17 weight:UIFontWeightSemibold color:[UIColor labelColor]];
    title.text = certificate.toolName;
    title.numberOfLines = 1;
    title.adjustsFontSizeToFitWidth = YES;
    title.minimumScaleFactor = 0.8;
    [title setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    UILabel *pill;
    if (certificate.usedByThisDevice) pill = [SFTheme pillWithText:SFL(@"This iPhone") color:[SFTheme success]];
    else if (certificate.appsSignedHere.count > 0) pill = [SFTheme pillWithText:SFL(@"Signs apps here") color:[SFTheme warning]];
    else pill = [SFTheme pillWithText:SFL(@"Not used here") color:[SFTheme secondaryText]];
    [pill setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [pill setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[icon, title, pill]];
    row.spacing = 12;
    row.alignment = UIStackViewAlignmentCenter;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:row];
    UILayoutGuide *m = cell.contentView.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [row.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:12],
        [row.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-12],
        [row.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
        [row.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
    ]];
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) return (indexPath.row == 0 && [self renewCertificate]) ? [self renewCell:[self renewCertificate]] : [self slotsCell];

    if ([self isDevicesSection:indexPath.section]) {
        if (self.devices.count == 0) return [self subtitleCellWithTitle:self.loading ? SFL(@"Loading…") : SFL(@"No iPhones registered yet") subtitle:nil];
        SFRegisteredDevice *device = self.devices[indexPath.row];
        NSString *model = device.model.length > 0 ? [SFDevice modelNameForIdentifier:device.model] : @"";
        NSString *subtitle = model.length > 0 ? model : @"iPhone";
        if (device.isThisDevice) subtitle = [subtitle stringByAppendingString:SFL(@" · this iPhone")];
        UITableViewCell *cell = [self subtitleCellWithTitle:device.name subtitle:subtitle];
        UIListContentConfiguration *config = (UIListContentConfiguration *)cell.contentConfiguration;
        config.image = [SFTheme symbol:@"iphone" size:20 weight:UIImageSymbolWeightRegular];
        config.imageProperties.tintColor = device.isThisDevice ? [SFTheme accent] : [SFTheme secondaryText];
        cell.contentConfiguration = config;
        return cell;
    }

    SFCertificate *certificate = self.certificates[indexPath.section - 1];
    switch (indexPath.row) {
        case 0: return [self certificateHeaderCell:certificate];
        case 1: return [self valueCellWithTitle:SFL(@"Created by") value:certificate.creatorName];
        case 2: {
            NSArray *users = certificate.usedByDescriptions;
            return [self valueCellWithTitle:SFL(@"Used by") value:users.count ? [users componentsJoinedByString:@"\n"] : SFL(@"No iPhone using Sevenfold")];
        }
        case 3: {
            NSArray *apps = certificate.appsSignedHere;
            NSString *value = apps.count == 0 ? SFL(@"None") : [NSString stringWithFormat:SFL(@"%lu: %@"), (unsigned long)apps.count, [apps componentsJoinedByString:@", "]];
            return [self valueCellWithTitle:SFL(@"Apps on this iPhone") value:value];
        }
        case 4: {
            // Exact date, with how long that is underneath (one line got cut off).
            if (!certificate.expirationDate) return [self valueCellWithTitle:SFL(@"Expires") value:SFL(@"Unknown")];
            NSDateFormatter *formatter = [NSDateFormatter new];
            formatter.dateStyle = NSDateFormatterMediumStyle;
            formatter.timeStyle = NSDateFormatterNoStyle;
            NSString *left = [SFTheme relativeExpiry:certificate.expirationDate];
            NSString *detail = certificate.expirationDate.timeIntervalSinceNow > 0 ? [NSString stringWithFormat:SFL(@"in %@"), left.lowercaseString] : left;
            return [self valueCellWithTitle:SFL(@"Expires") value:[formatter stringFromDate:certificate.expirationDate] detail:detail];
        }
        case 5: {
            // Full serial on its own line under the title; the eye button hides it.
            NSString *full = certificate.serialNumber ?: @"";
            NSString *shown = full.length == 0 ? SFL(@"Unknown")
                : (SFSerialHidden ? [@"••••••••" stringByAppendingString:(full.length > 4 ? [full substringFromIndex:full.length - 4] : full)] : full);
            // One line: "Serial" + value; the value's font shrinks to fit its length. Hold to copy.
            UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            UILabel *title = [SFTheme labelWithSize:15 weight:UIFontWeightRegular color:[SFTheme secondaryText]];
            title.text = SFL(@"Serial");
            [title setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
            [title setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
            UILabel *value = [UILabel new];
            value.text = shown;
            value.font = [UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightMedium];
            value.textColor = [UIColor labelColor];
            value.numberOfLines = 1;
            value.adjustsFontSizeToFitWidth = YES;
            value.minimumScaleFactor = 0.35;
            value.lineBreakMode = NSLineBreakByClipping;
            value.baselineAdjustment = UIBaselineAdjustmentAlignCenters;
            value.textAlignment = [SFLanguage isRightToLeft] ? NSTextAlignmentLeft : NSTextAlignmentRight;
            UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[title, value]];
            row.spacing = 12;
            row.alignment = UIStackViewAlignmentCenter;
            row.translatesAutoresizingMaskIntoConstraints = NO;
            [cell.contentView addSubview:row];
            [NSLayoutConstraint activateConstraints:@[
                [row.leadingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.leadingAnchor],
                [row.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],
                [row.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:6],
                [row.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-6],
                [row.heightAnchor constraintGreaterThanOrEqualToConstant:32],
            ]];
            if (full.length) {
                UIButton *eye = [UIButton buttonWithType:UIButtonTypeSystem];
                [eye setImage:[UIImage systemImageNamed:SFSerialHidden ? @"eye.slash" : @"eye"] forState:UIControlStateNormal];
                eye.tintColor = [UIColor systemBlueColor];
                eye.frame = CGRectMake(0, 0, 40, 40);
                eye.accessibilityLabel = SFSerialHidden ? SFL(@"Show") : SFL(@"Hide");
                [eye addTarget:self action:@selector(toggleSerial) forControlEvents:UIControlEventTouchUpInside];
                cell.accessoryView = eye;
                UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(serialHeld:)];
                hold.minimumPressDuration = 0.45;
                [cell addGestureRecognizer:hold];
                objc_setAssociatedObject(hold, &SFSerialKey, full, OBJC_ASSOCIATION_COPY_NONATOMIC);
            }
            return cell;
        }
        default:
            if ([self isShareRow:indexPath certificate:certificate]) return [self buttonCellWithTitle:SFL(@"Share with another iPhone") color:nil];
            return [self buttonCellWithTitle:SFL(@"Revoke") color:[SFTheme danger]];
    }
}

- (BOOL)tableView:(UITableView *)tableView shouldHighlightRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0 || [self isDevicesSection:indexPath.section]) return NO;
    return indexPath.row >= 5;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0 || [self isDevicesSection:indexPath.section]) return;
    SFCertificate *certificate = self.certificates[indexPath.section - 1];
    if ([self isShareRow:indexPath certificate:certificate]) { [self openShare]; return; }
    if (![self isRevokeRow:indexPath certificate:certificate]) return;
    [SFCertificatesViewController confirmRevokeCertificate:certificate from:self completion:^(BOOL revoked) {
        if (!revoked) return;
        // Take it off the list right away (Apple can take a moment to stop listing it).
        NSMutableArray *remaining = [NSMutableArray array];
        for (SFCertificate *other in self.certificates)
            if (![other.identifier isEqualToString:certificate.identifier]) [remaining addObject:other];
        self.revokedIdentifiers = [(self.revokedIdentifiers ?: [NSSet set]) setByAddingObject:certificate.identifier ?: @""];
        self.certificates = remaining;
        [self.tableView reloadData];
        [self load];
    }];
}

+ (void)confirmRevokeCertificate:(SFCertificate *)certificate from:(UIViewController *)presenter completion:(void (^)(BOOL revoked))completion {
    SFRevokeSheetController *sheet = [[SFRevokeSheetController alloc] initWithCertificate:certificate];
    sheet.presenterTabBar = presenter.tabBarController;
    sheet.completion = completion;
    [presenter presentViewController:sheet animated:YES completion:nil];
}

@end
