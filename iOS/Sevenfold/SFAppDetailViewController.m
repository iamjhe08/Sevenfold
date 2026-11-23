//
//  SFAppDetailViewController.m
//  Sevenfold
//

#import "SFAppDetailViewController.h"
#import "SFLocalization.h"
#import "SFTheme.h"
#import "SFSettings.h"
#import "SFSigningSession.h"
#import "SFRootController.h"
#import "SFApplication.h"
#import "SFApplicationDatabase.h"
#import "SFProgressBar.h"

@interface SFAppDetailViewController ()
@property (nonatomic, strong) UIView *header;
@property (nonatomic, strong) SFApplication *application;
@property (nonatomic) BOOL installMode;
// Signing progress shown on this page
@property (nonatomic, strong) UILabel *expiryTitle;
@property (nonatomic, strong) UILabel *expiryValue;
@property (nonatomic, strong) UILabel *expiryDate;
@property (nonatomic, strong) UIButton *actionButton;
@property (nonatomic, strong) UIView *statusCard;
@property (nonatomic, strong) UIImageView *statusIcon;
@property (nonatomic, strong) UILabel *statusTitle;
@property (nonatomic, strong) UILabel *statusPercent;
@property (nonatomic, strong) UILabel *statusDetail;
@property (nonatomic, strong) SFProgressBar *statusBar;
@property (nonatomic, strong) UIButton *retryButton;
@property (nonatomic, strong) NSTimer *dotsTimer;
@property (nonatomic) NSInteger dotStep;
@property (nonatomic) BOOL watching;      // a run that includes this app started while the page is open
@end

@implementation SFAppDetailViewController

- (instancetype)initWithApplication:(SFApplication *)application installMode:(BOOL)installMode {
    self = [super init];
    if (self) {
        _application = application;
        _installMode = installMode;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.title = self.installMode ? SFL(@"Install app") : @"";
    if (self.installMode)
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(close)];
    self.header = [self buildHeader];
    self.tableView.tableHeaderView = self.header;
    if (!self.installMode) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionChanged) name:SFSigningSessionDidChangeNotification object:nil];
        // Already being signed (e.g. Sign all was tapped before opening this page)?
        if ([SFSigningSession shared].running && [self myItem]) self.watching = YES;
        [self sessionChanged];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_dotsTimer invalidate];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.dotsTimer invalidate];
    self.dotsTimer = nil;
}

// MARK: - Progress on this page

- (SFSigningItem *)myItem {
    for (SFSigningItem *item in [SFSigningSession shared].items)
        if ([item.bundleIdentifier isEqualToString:self.application.bundleIdentifier]) return item;
    return nil;
}

- (void)refreshExpiry {
    SFApplication *fresh = [[SFApplicationDatabase sharedInstance] getApplicationWithBundleIdentifier:self.application.bundleIdentifier];
    if (fresh) self.application = fresh;
    NSDate *date = self.application.applicationExpiryDate;
    self.expiryTitle.text = [date timeIntervalSinceNow] > 0 ? SFL(@"Expires in") : SFL(@"Status");
    self.expiryValue.text = [SFTheme relativeExpiry:date];
    self.expiryValue.textColor = [SFTheme colorForExpiry:date];
    self.expiryDate.text = [SFTheme shortDateTime:date];
}

- (void)setActionTitle:(NSString *)title enabled:(BOOL)enabled {
    UIButtonConfiguration *config = self.actionButton.configuration;
    config.title = title;
    self.actionButton.configuration = config;
    self.actionButton.enabled = enabled;
}

- (void)startDots {
    if (self.dotsTimer) return;
    __weak typeof(self) weakSelf = self;
    self.dotsTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) {
        weakSelf.dotStep = (weakSelf.dotStep + 1) % 4;
        [weakSelf sessionChanged];
    }];
}

- (void)stopDots {
    [self.dotsTimer invalidate];
    self.dotsTimer = nil;
}

- (void)sessionChanged {
    if (self.installMode) return;
    SFSigningSession *session = [SFSigningSession shared];
    SFSigningItem *item = self.watching ? [self myItem] : nil;
    BOOL wasHidden = self.statusCard.hidden;
    if (!item) {
        self.statusCard.hidden = YES;
        [self stopDots];
        [self setActionTitle:SFL(@"Sign now") enabled:!session.running];
    } else {
        self.statusCard.hidden = NO;
        self.statusCard.layer.borderWidth = 0;
        self.retryButton.hidden = YES;
        self.statusBar.hidden = YES;
        self.statusPercent.hidden = YES;
        self.statusIcon.hidden = YES;
        switch (item.state) {
            case SFSigningItemWaiting:
            case SFSigningItemActive: {
                BOOL active = item.state == SFSigningItemActive;
                self.statusCard.backgroundColor = [SFTheme card];
                self.statusCard.layer.borderWidth = 1;
                self.statusCard.layer.borderColor = [[SFTheme amber] colorWithAlphaComponent:0.45].CGColor;
                self.statusTitle.text = active ? [SFL(@"Signing the app") stringByAppendingString:@[@".", @"..", @"...", @""][self.dotStep % 4]] : SFL(@"Waiting for its turn");
                self.statusTitle.textColor = [UIColor colorWithRed:0.96 green:0.73 blue:0.44 alpha:1];
                self.statusPercent.hidden = !active;
                self.statusPercent.text = [NSString stringWithFormat:@"%d%%", MAX(item.progress, 1)];
                self.statusBar.hidden = NO;
                [self.statusBar setProgress:active ? item.progress / 100.0 : 0 animated:YES];
                self.statusDetail.text = SFL(@"You can stay on this page. Going back keeps it signing.");
                [self startDots];
                [self setActionTitle:SFL(@"Signing…") enabled:NO];
                break;
            }
            case SFSigningItemDone: {
                [self stopDots];
                self.statusCard.backgroundColor = [[SFTheme success] colorWithAlphaComponent:0.12];
                self.statusIcon.hidden = NO;
                self.statusIcon.image = [UIImage systemImageNamed:@"checkmark.circle.fill"];
                self.statusIcon.tintColor = [SFTheme success];
                self.statusTitle.text = SFL(@"Signed just now");
                self.statusTitle.textColor = [UIColor labelColor];
                NSTimeInterval took = session.startDate && session.endDate ? [session.endDate timeIntervalSinceDate:session.startDate] : 0;
                self.statusDetail.text = took > 0 ? [NSString stringWithFormat:SFL(@"Took %.1f s"), took] : SFL(@"Done");
                [self refreshExpiry];
                [self setActionTitle:SFL(@"Sign now") enabled:!session.running];
                break;
            }
            case SFSigningItemFailed: {
                [self stopDots];
                self.statusCard.backgroundColor = [[SFTheme danger] colorWithAlphaComponent:0.12];
                self.statusIcon.hidden = NO;
                self.statusIcon.image = [UIImage systemImageNamed:@"xmark.circle.fill"];
                self.statusIcon.tintColor = [SFTheme danger];
                self.statusTitle.text = SFL(@"Couldn't sign this app");
                self.statusTitle.textColor = [UIColor labelColor];
                self.statusDetail.text = item.errorMessage ?: session.runError ?: SFL(@"Something went wrong.");
                self.retryButton.hidden = session.running;
                [self setActionTitle:SFL(@"Sign now") enabled:!session.running];
                break;
            }
        }
    }
    if (wasHidden != self.statusCard.hidden) [self.view setNeedsLayout];
    else [self.header setNeedsLayout];
    [self.view setNeedsLayout];
}

- (UIView *)buildStatusCard {
    UIView *card = [UIView new];
    card.layer.cornerRadius = 18;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.hidden = YES;

    self.statusIcon = [[UIImageView alloc] init];
    self.statusIcon.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:26 weight:UIImageSymbolWeightSemibold];
    [self.statusIcon setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    self.statusTitle = [SFTheme labelWithSize:16 weight:UIFontWeightSemibold color:[UIColor labelColor]];
    self.statusPercent = [SFTheme labelWithSize:22 weight:UIFontWeightHeavy color:[SFTheme amber]];
    [self.statusPercent setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    self.statusDetail = [SFTheme labelWithSize:13 weight:UIFontWeightRegular color:[SFTheme secondaryText]];
    self.statusDetail.numberOfLines = 0;
    self.statusBar = [SFProgressBar new];
    [self.statusBar.heightAnchor constraintEqualToConstant:8].active = YES;

    UIButtonConfiguration *retry = [UIButtonConfiguration filledButtonConfiguration];
    retry.title = SFL(@"Retry");
    retry.baseBackgroundColor = [SFTheme amber];
    retry.baseForegroundColor = [UIColor colorWithRed:0.10 green:0.07 blue:0.02 alpha:1];
    retry.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    self.retryButton = [UIButton buttonWithConfiguration:retry primaryAction:nil];
    [self.retryButton addTarget:self action:@selector(signNow) forControlEvents:UIControlEventTouchUpInside];
    [self.retryButton setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    UIStackView *titles = [[UIStackView alloc] initWithArrangedSubviews:@[self.statusTitle, self.statusDetail]];
    titles.axis = UILayoutConstraintAxisVertical;
    titles.spacing = 2;
    UIStackView *top = [[UIStackView alloc] initWithArrangedSubviews:@[self.statusIcon, titles, self.statusPercent, self.retryButton]];
    top.spacing = 12;
    top.alignment = UIStackViewAlignmentCenter;
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[top, self.statusBar]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:14],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14],
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
    ]];
    self.statusCard = card;
    return card;
}

// Size the header to its content once the screen width is known.
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.tableView.bounds.size.width;
    if (width <= 0) return;
    CGSize size = [self.header systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                             withHorizontalFittingPriority:UILayoutPriorityRequired
                                   verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    if (fabs(self.header.frame.size.height - size.height) > 0.5 || fabs(self.header.frame.size.width - width) > 0.5) {
        self.header.frame = CGRectMake(0, 0, width, size.height);
        self.tableView.tableHeaderView = self.header;
    }
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (UIView *)buildHeader {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 375, self.installMode ? 250 : 300)];

    UIImageView *icon = [[UIImageView alloc] initWithImage:self.application.applicationIcon ?: [SFTheme placeholderIconForName:self.application.applicationName size:84]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.layer.cornerRadius = 19;
    icon.layer.cornerCurve = kCACornerCurveContinuous;
    icon.clipsToBounds = YES;

    UILabel *name = [SFTheme labelWithSize:24 weight:UIFontWeightBold color:[UIColor labelColor]];
    name.text = self.application.applicationName ?: SFL(@"App");
    name.textAlignment = NSTextAlignmentCenter;
    UILabel *version = [SFTheme labelWithSize:14 weight:UIFontWeightRegular color:[SFTheme secondaryText]];
    version.text = [NSString stringWithFormat:SFL(@"Version %@"), self.application.applicationVersion ?: @"—"];
    version.textAlignment = NSTextAlignmentCenter;

    UIView *card = [SFTheme cardView];
    UILabel *expiryTitle = [SFTheme labelWithSize:13 weight:UIFontWeightMedium color:[SFTheme secondaryText]];
    UILabel *expiryValue = [SFTheme labelWithSize:20 weight:UIFontWeightBold color:[UIColor labelColor]];
    if (self.installMode) {
        expiryTitle.text = SFL(@"After installing");
        expiryValue.text = SFL(@"Valid for 7 days");
        expiryValue.textColor = [SFTheme success];
    } else {
        NSDate *date = self.application.applicationExpiryDate;
        expiryTitle.text = [date timeIntervalSinceNow] > 0 ? SFL(@"Expires in") : SFL(@"Status");
        expiryValue.text = [SFTheme relativeExpiry:date];
        expiryValue.textColor = [SFTheme colorForExpiry:date];
    }
    self.expiryTitle = expiryTitle;
    self.expiryValue = expiryValue;
    UILabel *expiryDate = [SFTheme labelWithSize:14 weight:UIFontWeightMedium color:[SFTheme secondaryText]];
    self.expiryDate = expiryDate;
    expiryDate.text = self.installMode ? @"" : [SFTheme shortDateTime:self.application.applicationExpiryDate];
    expiryDate.textAlignment = [SFLanguage isRightToLeft] ? NSTextAlignmentLeft : NSTextAlignmentRight;
    UIStackView *left = [[UIStackView alloc] initWithArrangedSubviews:@[expiryTitle, expiryValue]];
    left.axis = UILayoutConstraintAxisVertical;
    left.spacing = 2;
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[left, expiryDate]];
    row.alignment = UIStackViewAlignmentCenter;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:row];

    UIButton *action = [SFTheme primaryButtonWithTitle:self.installMode ? SFL(@"Install") : SFL(@"Sign now")];
    [action addTarget:self action:@selector(signNow) forControlEvents:UIControlEventTouchUpInside];
    self.actionButton = action;
    UIView *status = [self buildStatusCard];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[icon, name, version, card, status, action]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 6;
    [stack setCustomSpacing:14 afterView:icon];
    [stack setCustomSpacing:18 afterView:version];
    [stack setCustomSpacing:12 afterView:card];
    [stack setCustomSpacing:12 afterView:status];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [icon.widthAnchor constraintEqualToConstant:84],
        [icon.heightAnchor constraintEqualToConstant:84],
        [stack.topAnchor constraintEqualToAnchor:header.topAnchor constant:12],
        [stack.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20],
        [stack.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-16],
        [card.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [status.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [action.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [row.topAnchor constraintEqualToAnchor:card.topAnchor constant:14],
        [row.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14],
        [row.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [row.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
    ]];
    return header;
}

- (void)signNow {
    if (![SFSettings isSignedIn]) {
        [self showMessage:SFL(@"Sign in with your Apple ID first.") title:SFL(@"Not signed in")];
        return;
    }
    if ([SFSigningSession shared].running) {
        [self showMessage:SFL(@"Another signing run is in progress. Try again when it finishes.") title:SFL(@"Busy")];
        return;
    }
    UIViewController *presenterRoot = self.presentingViewController ?: self.tabBarController;
    SFRootController *root = (SFRootController *)([presenterRoot isKindOfClass:[SFRootController class]] ? presenterRoot : self.view.window.rootViewController);
    if (self.installMode) {
        [[SFSigningSession shared] signApplications:@[self.application]];
        [self dismissViewControllerAnimated:YES completion:^{ [root presentSigningProgress]; }];
        return;
    }
    // Stay on this page; the progress card shows the signing.
    self.watching = YES;
    self.dotStep = 0;
    if (![[SFSigningSession shared] signApplications:@[self.application]]) self.watching = NO;
    [self sessionChanged];
}

- (void)toggleAuto:(UISwitch *)sender {
    [SFSettings setExcluded:!sender.on forBundleIdentifier:self.application.bundleIdentifier];
}

// MARK: - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.installMode ? 1 : 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 3 : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 1) return SFL(@"When off, this app is only signed when you tap Sign now.");
    if (self.installMode) return SFL(@"Sevenfold signs the app with your Apple ID and installs it. Free Apple IDs can create 10 App IDs per week.");
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1)
        return [self switchCellWithTitle:SFL(@"Include in auto-signing") subtitle:SFL(@"Signed on your schedule")
                                      on:![SFSettings isExcluded:self.application.bundleIdentifier] action:@selector(toggleAuto:)];
    switch (indexPath.row) {
        case 0: return [self valueCellWithTitle:SFL(@"Bundle ID") value:self.application.bundleIdentifier];
        case 1: {
            NSNumber *size = self.application.applicationInstalledSize;
            NSString *text = size ? [NSByteCountFormatter stringFromByteCount:size.longLongValue countStyle:NSByteCountFormatterCountStyleFile] : @"—";
            return [self valueCellWithTitle:SFL(@"Size") value:text];
        }
        default: return [self valueCellWithTitle:SFL(@"Signed with") value:self.installMode ? SFL(@"Your certificate") : SFL(@"Your Apple ID's certificate")];
    }
}

@end
