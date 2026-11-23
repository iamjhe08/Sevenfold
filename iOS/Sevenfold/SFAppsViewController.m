//
//  SFAppsViewController.m
//  Sevenfold
//
//  Main screen: status card, "Sign all apps now", and the list of apps.
//

#import "SFAppsViewController.h"
#import "SFTableViewController.h"
#import "SFLocalization.h"
#import "SFTheme.h"
#import "SFLog.h"
#import "SFSettings.h"
#import "SFSigningSession.h"
#import "SFProgressBar.h"
#import "SFRootController.h"
#import "SFAppDetailViewController.h"
#import "SFCertificateStore.h"
#import "SFApplication.h"
#import "SFApplicationDatabase.h"
#import "SFResources.h"
#import "SFAppIDBudget.h"
#import "SFLanguageViewController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

// LaunchServices (private) for opening and deleting apps.
@protocol SFWorkspace <NSObject>
- (BOOL)openApplicationWithBundleID:(NSString *)bundleID;
- (BOOL)uninstallApplication:(NSString *)bundleID withOptions:(nullable NSDictionary *)options;
@end

static id<SFWorkspace> SFWorkspaceShared(void) {
    Class cls = NSClassFromString(@"LSApplicationWorkspace");
    return [cls respondsToSelector:@selector(defaultWorkspace)] ? [cls performSelector:@selector(defaultWorkspace)] : nil;
}

#pragma mark - App row

@interface SFAppCell : UITableViewCell
@property (nonatomic, strong) UIImageView *icon;
@property (nonatomic, strong) UILabel *name;
@property (nonatomic, strong) UILabel *bundle;
@property (nonatomic, strong) UILabel *daysValue;
@property (nonatomic, strong) UILabel *daysCaption;
@property (nonatomic, strong) SFProgressBar *progress;
@property (nonatomic, strong) UIButton *retryButton;
@property (nonatomic, copy) void (^onRetry)(void);
@property (nonatomic) BOOL showsSigningDots;
@end

@implementation SFAppCell

- (void)retryTapped { if (self.onRetry) self.onRetry(); }

- (void)prepareForReuse {
    [super prepareForReuse];
    self.onRetry = nil;
    self.contentView.alpha = 1;
    self.contentView.backgroundColor = nil;
    self.progress.hidden = YES;
    self.retryButton.hidden = YES;
    self.daysValue.hidden = NO;
    self.daysCaption.hidden = NO;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [SFTheme card];
        self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        _icon = [UIImageView new];
        _icon.translatesAutoresizingMaskIntoConstraints = NO;
        _icon.layer.cornerRadius = 10;
        _icon.layer.cornerCurve = kCACornerCurveContinuous;
        _icon.clipsToBounds = YES;
        _name = [SFTheme labelWithSize:16 weight:UIFontWeightSemibold color:[UIColor labelColor]];
        _name.numberOfLines = 1;
        _bundle = [SFTheme labelWithSize:13 weight:UIFontWeightRegular color:[SFTheme secondaryText]];
        _bundle.numberOfLines = 1;
        _bundle.lineBreakMode = NSLineBreakByTruncatingMiddle;
        _daysValue = [SFTheme labelWithSize:17 weight:UIFontWeightBold color:[SFTheme success]];
        _daysValue.numberOfLines = 1;
        _daysValue.textAlignment = [SFLanguage isRightToLeft] ? NSTextAlignmentLeft : NSTextAlignmentRight;
        _daysCaption = [SFTheme labelWithSize:11 weight:UIFontWeightMedium color:[SFTheme secondaryText]];
        _daysCaption.numberOfLines = 1;
        _daysCaption.textAlignment = [SFLanguage isRightToLeft] ? NSTextAlignmentLeft : NSTextAlignmentRight;

        UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[_name, _bundle]];
        text.axis = UILayoutConstraintAxisVertical;
        text.spacing = 3;
        UIButtonConfiguration *retry = [UIButtonConfiguration filledButtonConfiguration];
        retry.title = SFL(@"Retry");
        retry.baseBackgroundColor = [SFTheme amber];
        retry.baseForegroundColor = [UIColor colorWithRed:0.10 green:0.07 blue:0.02 alpha:1];
        retry.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
        retry.contentInsets = NSDirectionalEdgeInsetsMake(7, 14, 7, 14);
        retry.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *attrs) {
            NSMutableDictionary *m = [attrs mutableCopy];
            m[NSFontAttributeName] = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
            return m;
        };
        _retryButton = [UIButton buttonWithConfiguration:retry primaryAction:nil];
        [_retryButton addTarget:self action:@selector(retryTapped) forControlEvents:UIControlEventTouchUpInside];
        _retryButton.hidden = YES;

        UIStackView *days = [[UIStackView alloc] initWithArrangedSubviews:@[_daysValue, _daysCaption, _retryButton]];
        days.axis = UILayoutConstraintAxisVertical;
        days.alignment = UIStackViewAlignmentTrailing;
        days.spacing = 1;
        [days setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [days setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_daysValue setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_daysCaption setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[_icon, text, days]];
        row.spacing = 14;
        row.alignment = UIStackViewAlignmentCenter;
        _progress = [SFProgressBar new];
        [_progress.heightAnchor constraintEqualToConstant:5].active = YES;
        _progress.hidden = YES;

        UIStackView *outer = [[UIStackView alloc] initWithArrangedSubviews:@[row, _progress]];
        outer.axis = UILayoutConstraintAxisVertical;
        outer.spacing = 10;
        outer.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:outer];
        UILayoutGuide *m = self.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [_icon.widthAnchor constraintEqualToConstant:46],
            [_icon.heightAnchor constraintEqualToConstant:46],
            [outer.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
            [outer.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
            [outer.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12],
            [outer.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-12],
        ]];
    }
    return self;
}

@end

@interface SFAppsViewController () <UIDocumentPickerDelegate>
@property (nonatomic, strong) NSArray<SFApplication *> *apps;
@property (nonatomic, strong) NSTimer *tickTimer;
@property (nonatomic, strong) UIView *header;
@property (nonatomic, strong) UILabel *statusTitle;
@property (nonatomic, strong) UILabel *statusSubtitle;
@property (nonatomic, strong) UILabel *emailLine;
@property (nonatomic, strong) UILabel *nextRunValue;
@property (nonatomic, strong) UILabel *certificateValue;
@property (nonatomic, strong) UIButton *signButton;
@property (nonatomic, strong) SFProgressBar *runBar;
@property (nonatomic, strong) NSTimer *dotsTimer;
@property (nonatomic, strong) UIView *statusCard;
@property (nonatomic, strong) UIStackView *statsRow;
@property (nonatomic, strong) UILabel *budgetCount;
@property (nonatomic, strong) UIView *budgetFill;
@property (nonatomic, strong) UIStackView *budgetView;
@property (nonatomic, strong) UIImageView *successCheck;
@property (nonatomic, strong) UIView *successLine;
@property (nonatomic, strong) UIView *successTrack;
@property (nonatomic, strong, nullable) NSDate *successUntil;   // green "all signed" card shows until then
@property (nonatomic) BOOL wasRunning;
@property (nonatomic) NSInteger dotStep;
@end

@implementation SFAppsViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.backgroundColor = [SFTheme background];
    self.tableView.separatorColor = [SFTheme separator];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 72;

    UIBarButtonItem *install = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"plus.circle.fill"]
                                                                style:UIBarButtonItemStylePlain target:self action:@selector(installIPA)];
    install.accessibilityLabel = SFL(@"Install an IPA file");
    // Language: a quieter button left of the +, so someone who can't read English finds it.
    UIBarButtonItem *language = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"globe"]
                                                                 style:UIBarButtonItemStylePlain target:self action:@selector(openLanguage)];
    language.accessibilityLabel = SFL(@"Language");
    language.tintColor = [UIColor systemBlueColor];
    self.navigationItem.rightBarButtonItems = @[install, language];

    self.refreshControl = [UIRefreshControl new];
    [self.refreshControl addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];

    [self buildHeader];

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(sessionChanged) name:SFSigningSessionDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(reload) name:SFSettingsDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(reload) name:@"com.t4mag0.sevenfold/userDidSignIn" object:nil];
    [center addObserver:self selector:@selector(reload) name:UIApplicationWillEnterForegroundNotification object:nil];
    [center addObserver:self selector:@selector(updateBudget) name:SFAppIDBudgetDidChangeNotification object:nil];
    [self reload];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
    [self updateBudget];
    if (![SFSigningSession shared].running) [[SFAppIDBudget shared] refreshForce:NO];
    // Keep the time left ticking while the list is on screen.
    [self.tickTimer invalidate];
    __weak typeof(self) weakSelf = self;
    self.tickTimer = [NSTimer scheduledTimerWithTimeInterval:60 repeats:YES block:^(NSTimer *timer) {
        [weakSelf.tableView reloadRowsAtIndexPaths:weakSelf.tableView.indexPathsForVisibleRows withRowAnimation:UITableViewRowAnimationNone];
    }];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    self.successUntil = nil;   // leaving the screen ends the green card
    [self.tickTimer invalidate];
    self.tickTimer = nil;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    SFApplyReadableColumn(self.tableView);
    // Size the header to fit its content.
    CGFloat width = self.tableView.bounds.size.width;
    CGSize size = [self.header systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                             withHorizontalFittingPriority:UILayoutPriorityRequired
                                   verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    if (fabs(self.header.frame.size.height - size.height) > 0.5 || fabs(self.header.frame.size.width - width) > 0.5) {
        self.header.frame = CGRectMake(0, 0, width, size.height);
        self.tableView.tableHeaderView = self.header;
    }
}

// MARK: - Header

- (UILabel *)smallCaption:(NSString *)text {
    UILabel *label = [SFTheme labelWithSize:12 weight:UIFontWeightMedium color:[UIColor colorWithRed:0.79 green:0.82 blue:0.92 alpha:1]];
    label.text = text;
    return label;
}

- (void)buildHeader {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 375, 230)];
    // iPad: the card follows the table's centred reading column.
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) header.preservesSuperviewLayoutMargins = YES;
    self.header = header;

    UIView *card = [UIView new];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = [SFTheme midnight];
    self.statusCard = card;
    card.layer.cornerRadius = 22;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    [header addSubview:card];

    self.statusTitle = [SFTheme labelWithSize:22 weight:UIFontWeightBold color:[UIColor whiteColor]];
    self.statusSubtitle = [SFTheme labelWithSize:14 weight:UIFontWeightRegular color:[UIColor colorWithRed:0.79 green:0.82 blue:0.92 alpha:1]];

    self.runBar = [SFProgressBar new];
    self.runBar.trackColor = [UIColor colorWithWhite:1 alpha:0.14];
    [self.runBar.heightAnchor constraintEqualToConstant:8].active = YES;
    self.runBar.hidden = YES;
    BOOL success = [self showSuccess];
    self.successCheck.hidden = !success;
    self.successTrack.hidden = !success;
    self.statsRow.hidden = success;
    self.statusSubtitle.textColor = success ? [UIColor colorWithRed:0.72 green:0.91 blue:0.79 alpha:1] : [UIColor colorWithRed:0.79 green:0.82 blue:0.92 alpha:1];
    [UIView animateWithDuration:0.35 animations:^{
        self.statusCard.backgroundColor = success ? [UIColor colorWithRed:0.06 green:0.22 blue:0.14 alpha:1] : [SFTheme midnight];
    }];
    self.statusCard.layer.borderWidth = success ? 1 : 0;
    self.statusCard.layer.borderColor = [UIColor colorWithRed:0.29 green:0.87 blue:0.50 alpha:0.45].CGColor;

    UIStackView *(^stat)(NSString *, UILabel *) = ^UIStackView *(NSString *caption, UILabel *value) {
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[[self smallCaption:caption], value]];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 3;
        return stack;
    };
    self.nextRunValue = [SFTheme labelWithSize:15 weight:UIFontWeightSemibold color:[SFTheme amberLight]];
    self.certificateValue = [SFTheme labelWithSize:15 weight:UIFontWeightSemibold color:[SFTheme amberLight]];
    UIStackView *stats = [[UIStackView alloc] initWithArrangedSubviews:@[stat(SFL(@"Next auto-sign"), self.nextRunValue), stat(SFL(@"Certificate"), self.certificateValue)]];
    stats.distribution = UIStackViewDistributionFillEqually;
    stats.spacing = 12;

    self.statsRow = stats;
    // Success state: a check beside the title and a line that counts down before the card returns to normal.
    self.successCheck = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.circle.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:40 weight:UIImageSymbolWeightBold]]];
    self.successCheck.tintColor = [UIColor colorWithRed:0.13 green:0.77 blue:0.37 alpha:1];
    self.successCheck.hidden = YES;
    [self.successCheck setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *titleTexts = [[UIStackView alloc] initWithArrangedSubviews:@[self.statusTitle, self.statusSubtitle]];
    titleTexts.axis = UILayoutConstraintAxisVertical;
    titleTexts.spacing = 6;
    // App IDs used this week (free accounts get 10).
    self.budgetCount = [SFTheme labelWithSize:26 weight:UIFontWeightHeavy color:[UIColor whiteColor]];
    UILabel *budgetCaption = [SFTheme labelWithSize:12 weight:UIFontWeightRegular color:[UIColor colorWithRed:0.79 green:0.82 blue:0.92 alpha:1]];
    budgetCaption.text = SFL(@"App IDs");
    UIView *budgetTrack = [UIView new];
    budgetTrack.backgroundColor = [UIColor colorWithWhite:1 alpha:0.14];
    budgetTrack.layer.cornerRadius = 2;
    budgetTrack.clipsToBounds = YES;
    [budgetTrack.heightAnchor constraintEqualToConstant:4].active = YES;
    [budgetTrack.widthAnchor constraintEqualToConstant:64].active = YES;
    self.budgetFill = [[UIView alloc] initWithFrame:CGRectZero];
    self.budgetFill.layer.cornerRadius = 2;
    [budgetTrack addSubview:self.budgetFill];
    UIStackView *budget = [[UIStackView alloc] initWithArrangedSubviews:@[self.budgetCount, budgetCaption, budgetTrack]];
    budget.axis = UILayoutConstraintAxisVertical;
    budget.alignment = UIStackViewAlignmentTrailing;
    budget.spacing = 2;
    [budget setCustomSpacing:6 afterView:budgetCaption];
    [budget setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [budget setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    self.budgetView = budget;
    UIStackView *titleRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.successCheck, titleTexts, budget]];
    titleRow.spacing = 14;
    titleRow.alignment = UIStackViewAlignmentCenter;
    self.successTrack = [UIView new];
    self.successTrack.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
    self.successTrack.layer.cornerRadius = 2;
    self.successTrack.hidden = YES;
    [self.successTrack.heightAnchor constraintEqualToConstant:4].active = YES;
    self.successLine = [UIView new];
    self.successLine.backgroundColor = [UIColor colorWithRed:0.29 green:0.87 blue:0.50 alpha:1];
    self.successLine.layer.cornerRadius = 2;
    [self.successTrack addSubview:self.successLine];

    // Email: its own full-width line under the title row, one line, font shrinks to fit its length.
    self.emailLine = [SFTheme labelWithSize:15 weight:UIFontWeightRegular color:[UIColor colorWithRed:0.79 green:0.82 blue:0.92 alpha:1]];
    self.emailLine.numberOfLines = 1;
    self.emailLine.adjustsFontSizeToFitWidth = YES;
    self.emailLine.minimumScaleFactor = 0.35;
    self.emailLine.lineBreakMode = NSLineBreakByClipping;
    self.emailLine.baselineAdjustment = UIBaselineAdjustmentAlignCenters;
    self.emailLine.hidden = YES;
    UIStackView *cardStack = [[UIStackView alloc] initWithArrangedSubviews:@[titleRow, self.emailLine, self.runBar, stats, self.successTrack]];
    cardStack.axis = UILayoutConstraintAxisVertical;
    cardStack.spacing = 6;
    [cardStack setCustomSpacing:16 afterView:titleRow];
    [cardStack setCustomSpacing:14 afterView:self.emailLine];
    [cardStack setCustomSpacing:16 afterView:self.runBar];
    cardStack.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:cardStack];

    self.signButton = [SFTheme primaryButtonWithTitle:SFL(@"Sign all apps now")];
    [self.signButton addTarget:self action:@selector(signAll) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:self.signButton];

    UILayoutGuide *margins = header.layoutMarginsGuide;
    header.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(8, 20, 8, 20);
    [NSLayoutConstraint activateConstraints:@[
        [card.topAnchor constraintEqualToAnchor:header.topAnchor constant:8],
        [card.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
        [card.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
        [cardStack.topAnchor constraintEqualToAnchor:card.topAnchor constant:20],
        [cardStack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20],
        [cardStack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20],
        [cardStack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-20],
        [self.signButton.topAnchor constraintEqualToAnchor:card.bottomAnchor constant:14],
        [self.signButton.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
        [self.signButton.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
        [self.signButton.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-6],
    ]];
    self.tableView.tableHeaderView = header;
}

- (void)openLanguage {
    [self.navigationController pushViewController:[SFLanguageViewController new] animated:YES];
}

/// "4/10 App IDs": white, amber from 8, red at 10. Hidden for paid accounts or when unknown.
- (void)updateBudget {
    SFAppIDBudget *budget = [SFAppIDBudget shared];
    BOOL show = [SFSettings isSignedIn] && !budget.unlimited && budget.used >= 0;
    self.budgetView.hidden = !show;
    if (!show) return;
    NSInteger used = budget.used;
    UIColor *color = used >= 10 ? [SFTheme danger] : used >= 8 ? [SFTheme warning] : [UIColor whiteColor];
    NSMutableAttributedString *text = [[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"%ld", (long)used] attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:26 weight:UIFontWeightHeavy], NSForegroundColorAttributeName: color }];
    [text appendAttributedString:[[NSAttributedString alloc] initWithString:@"/10" attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold],
        NSForegroundColorAttributeName: [UIColor colorWithRed:0.56 green:0.59 blue:0.72 alpha:1] }]];
    self.budgetCount.attributedText = text;
    CGFloat width = 64.0 * MIN(MAX(used, 0), 10) / 10.0;
    BOOL rightToLeft = self.view.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    self.budgetFill.frame = CGRectMake(rightToLeft ? 64 - width : 0, 0, width, 4);
    self.budgetFill.backgroundColor = color;
}

- (void)updateHeader {
    [self updateBudget];
    SFSigningSession *session = [SFSigningSession shared];
    BOOL signedIn = [SFSettings isSignedIn];

    NSUInteger soon = 0;
    NSUInteger expired = 0;
    int threshold = [SFSettings expiryThresholdDays];
    for (SFApplication *app in self.apps) {
        NSTimeInterval left = [app.applicationExpiryDate timeIntervalSinceNow];
        if (left <= 0) expired++;
        else if (left < threshold * 24 * 3600) soon++;
    }

    self.statusSubtitle.hidden = NO;
    self.emailLine.hidden = YES;

    if (!signedIn) {
        self.statusTitle.text = SFL(@"Sign in to start");
        self.statusSubtitle.text = SFL(@"Sevenfold needs your Apple ID to sign apps.");
    } else if (session.running) {
        // Progress itself shows on the rows; the card just says how far along it is.
        NSArray<SFSigningItem *> *items = session.items;
        NSUInteger finished = 0;
        for (SFSigningItem *item in items) if (item.state == SFSigningItemDone || item.state == SFSigningItemFailed) finished++;
        BOOL together = items.count > 1 && [SFSettings parallelSigning];
        NSString *count;
        if (together) {
            self.statusTitle.text = session.stopRequested ? SFL(@"Stopping after these apps")
                                  : items.count <= 3 ? [NSString stringWithFormat:SFL(@"Signing %lu apps at once"), (unsigned long)items.count]
                                                     : [NSString stringWithFormat:SFL(@"Signing %lu apps, 3 at a time"), (unsigned long)items.count];
            count = [NSString stringWithFormat:SFL(@"%lu done"), (unsigned long)finished];
        } else {
            self.statusTitle.text = session.stopRequested ? SFL(@"Stopping after this app") : SFL(@"Signing in progress");
            count = [NSString stringWithFormat:(items.count == 1 ? SFL(@"%lu of %lu app") : SFL(@"%lu of %lu apps")), (unsigned long)MIN(finished + 1, items.count), (unsigned long)items.count];
        }
        NSTimeInterval elapsed = session.startDate ? -[session.startDate timeIntervalSinceNow] : 0;
        if (finished > 0 && finished < items.count && elapsed > 0) {
            NSTimeInterval remaining = elapsed / finished * (items.count - finished);
            count = [count stringByAppendingFormat:SFL(@" · about %@ left"), remaining < 60 ? [NSString stringWithFormat:@"%.0f s", MAX(remaining, 1)] : [NSString stringWithFormat:SFL(@"%.0f min"), ceil(remaining / 60)]];
        }
        self.statusSubtitle.text = count;
    } else if ([self showSuccess]) {
        NSUInteger done = session.doneCount;
        self.statusTitle.text = done == 1 ? [NSString stringWithFormat:SFL(@"%@ signed"), session.items.firstObject.name ?: SFL(@"1 app")]
                                          : [NSString stringWithFormat:SFL(@"All %lu apps signed"), (unsigned long)done];
        NSTimeInterval seconds = session.startDate && session.endDate ? [session.endDate timeIntervalSinceDate:session.startDate] : 0;
        self.statusSubtitle.text = [NSString stringWithFormat:SFL(@"Just now · took %.1f s · good for 7 days"), seconds];
    } else if ([self showRunResult]) {
        NSUInteger done = session.doneCount, failed = session.failedCount;
        if (done == 0 && failed == 0) self.statusTitle.text = SFL(@"Nothing needed signing");
        else if (failed == 0) self.statusTitle.text = done == 1 ? SFL(@"1 app signed") : [NSString stringWithFormat:SFL(@"%lu apps signed"), (unsigned long)done];
        else self.statusTitle.text = [NSString stringWithFormat:SFL(@"%lu signed · %lu failed"), (unsigned long)done, (unsigned long)failed];
        NSTimeInterval seconds = session.startDate && session.endDate ? [session.endDate timeIntervalSinceDate:session.startDate] : 0;
        self.statusSubtitle.text = failed ? SFL(@"Tap a failed app to see why, or Retry it.") : [NSString stringWithFormat:SFL(@"Just now · %.1f s"), seconds];
    } else if (self.apps.count == 0) {
        self.statusTitle.text = SFL(@"No apps yet");
        self.statusSubtitle.text = SFL(@"Tap + to install an .ipa file.");
    } else if (expired > 0) {
        self.statusTitle.text = expired == 1 ? SFL(@"1 app has expired") : [NSString stringWithFormat:SFL(@"%lu apps have expired"), (unsigned long)expired];
        self.statusSubtitle.text = SFL(@"Sign now to use them again.");
    } else if (soon > 0) {
        self.statusTitle.text = soon == 1 ? SFL(@"1 app expires soon") : [NSString stringWithFormat:SFL(@"%lu apps expire soon"), (unsigned long)soon];
        self.statusSubtitle.text = [SFSettings automaticSigning] ? SFL(@"It will be signed at the next automatic run.") : SFL(@"Automatic signing is off.");
    } else {
        self.statusTitle.text = SFL(@"All apps are signed");
        NSString *email = [SFSettings displayEmail];
        if (email.length) {
            self.statusSubtitle.hidden = YES;
            self.emailLine.text = email;
            self.emailLine.hidden = NO;
        } else {
            self.statusSubtitle.text = SFL(@"Signed in");
        }
    }

    self.runBar.hidden = YES;

    self.nextRunValue.text = [SFSettings automaticSigning] ? [SFTheme shortDateTime:[SFSettings nextScheduledRun]] : SFL(@"Off");
    if (!signedIn) self.certificateValue.text = @"—";
    else if ([SFCertificateStore hasPrivateKey]) self.certificateValue.text = [SFCertificateStore sharedWithCount] > 0 ? SFL(@"Shared · ready") : SFL(@"Ready");
    else self.certificateValue.text = SFL(@"Created on first sign");

    UIButtonConfiguration *config = self.signButton.configuration;
    if (!signedIn) config.title = SFL(@"Sign in");
    else if (session.running) config.title = session.stopRequested ? SFL(@"Stopping…")
                                           : (session.items.count > 1 && [SFSettings parallelSigning]) ? SFL(@"Stop after these apps") : SFL(@"Stop after this app");
    else config.title = SFL(@"Sign all apps now");
    self.signButton.configuration = config;
    self.signButton.enabled = !signedIn || (session.running && !session.stopRequested) || (!session.running && self.apps.count > 0);
}

// MARK: - Data

- (void)reload {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *teamID = [SFResources getTeamID];
        NSArray *apps = teamID.length > 0 ? [[SFApplicationDatabase sharedInstance] getAllApplicationsForTeamID:teamID] : @[];
        apps = [apps sortedArrayUsingComparator:^NSComparisonResult(SFApplication *a, SFApplication *b) {
            return [a.applicationExpiryDate ?: [NSDate distantFuture] compare:b.applicationExpiryDate ?: [NSDate distantFuture]];
        }];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.apps = apps;
            [self.refreshControl endRefreshing];
            [self updateHeader];
            [self.tableView reloadData];
            [self.view setNeedsLayout];
        });
    });
}

/// Green "all signed" card for a few seconds after a run with no failures.
- (BOOL)showSuccess {
    return self.successUntil && [self.successUntil timeIntervalSinceNow] > 0;
}

- (void)startSuccessWindow {
    NSTimeInterval length = 6;
    self.successUntil = [NSDate dateWithTimeIntervalSinceNow:length];
    [self updateHeader];
    [self.view layoutIfNeeded];
    // The line empties over the window, then the card goes back to normal.
    CGRect full = self.successTrack.bounds;
    self.successLine.frame = full;
    [UIView animateWithDuration:length delay:0 options:UIViewAnimationOptionCurveLinear animations:^{
        self.successLine.frame = CGRectMake(0, 0, 0, full.size.height);
    } completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(length * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if ([self showSuccess]) return;   // a newer window took over
        self.successUntil = nil;
        [UIView transitionWithView:self.tableView duration:0.35 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
            [self updateHeader];
            [self.tableView reloadData];
        } completion:^(BOOL done) { [self.view setNeedsLayout]; }];
    });
}

/// After a successful run the list goes straight back to normal (status card with the Apple ID).
/// Only when something failed does the result stay for 10 minutes, so failed rows keep Retry.
- (BOOL)showRunResult {
    SFSigningSession *session = [SFSigningSession shared];
    return session.finished && !session.running && !session.automatic && session.failedCount > 0
        && session.endDate && -[session.endDate timeIntervalSinceNow] < 600;
}

- (SFSigningItem *)itemForApp:(SFApplication *)app {
    SFSigningSession *session = [SFSigningSession shared];
    if (!session.running && ![self showRunResult] && ![self showSuccess]) return nil;
    for (SFSigningItem *item in session.items) if ([item.bundleIdentifier isEqualToString:app.bundleIdentifier]) return item;
    return nil;
}

- (NSString *)signingTextWithDots {
    return [SFL(@"Signing the app") stringByAppendingString:@[@".", @"..", @"...", @""][self.dotStep % 4]];
}

- (void)updateDotsTimer {
    BOOL running = [SFSigningSession shared].running;
    if (running && !self.dotsTimer) {
        self.dotStep = 0;
        __weak typeof(self) weakSelf = self;
        self.dotsTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) {
            weakSelf.dotStep = (weakSelf.dotStep + 1) % 4;
            for (SFAppCell *cell in weakSelf.tableView.visibleCells)
                if ([cell isKindOfClass:[SFAppCell class]] && cell.showsSigningDots) cell.bundle.text = [weakSelf signingTextWithDots];
        }];
    } else if (!running && self.dotsTimer) {
        [self.dotsTimer invalidate];
        self.dotsTimer = nil;
    }
}

- (void)sessionChanged {
    SFSigningSession *session = [SFSigningSession shared];
    [self updateDotsTimer];
    // A run just ended with everything signed: show the green card.
    if (self.wasRunning && !session.running && session.finished && session.failedCount == 0 && session.doneCount > 0)
        self.successUntil = [NSDate dateWithTimeIntervalSinceNow:6];
    BOOL justFinishedOK = self.wasRunning && !session.running && self.successUntil != nil;
    if (self.wasRunning && !session.running) [[SFAppIDBudget shared] refreshForce:YES];   // the run may have created App IDs
    self.wasRunning = session.running;
    if (justFinishedOK) {
        [self startSuccessWindow];
        [self reload];
        return;
    }
    [self updateHeader];
    if (session.finished && !session.running) { [self reload]; return; }
    for (NSIndexPath *indexPath in self.tableView.indexPathsForVisibleRows) {
        SFAppCell *cell = (SFAppCell *)[self.tableView cellForRowAtIndexPath:indexPath];
        if ([cell isKindOfClass:[SFAppCell class]] && indexPath.row < (NSInteger)self.apps.count)
            [self configureCell:cell forApp:self.apps[indexPath.row]];
    }
    // Row heights change when a progress bar appears or goes away.
    [UIView performWithoutAnimation:^{
        [self.tableView beginUpdates];
        [self.tableView endUpdates];
    }];
}

// MARK: - Actions

- (void)signAll {
    SFRootController *root = (SFRootController *)self.tabBarController;
    if (![SFSettings isSignedIn]) { [root presentSignIn]; return; }
    SFSigningSession *session = [SFSigningSession shared];
    if (session.running) {
        [session requestStopAfterCurrent];
        return;
    }
    // Signing happens right here: each row shows its own progress.
    [session signApplications:self.apps];
    [self.tableView setContentOffset:CGPointMake(0, -self.tableView.adjustedContentInset.top) animated:YES];
}

- (void)installIPA {
    UTType *ipa = [UTType typeWithFilenameExtension:@"ipa"] ?: UTTypeData;
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[ipa, UTTypeData] asCopy:YES];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [(SFRootController *)self.tabBarController presentInstallForIPAURL:url];
    });
}

// MARK: - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.apps.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.apps.count > 0 ? SFL(@"Sideloaded apps") : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (self.apps.count == 0) return nil;
    if ([SFSettings signAllEachRun]) return SFL(@"All apps are signed at every scheduled run.");
    return [NSString stringWithFormat:([SFSettings expiryThresholdDays] == 1 ? SFL(@"Apps expiring within %d day are signed automatically.") : SFL(@"Apps expiring within %d days are signed automatically.")), [SFSettings expiryThresholdDays]];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SFAppCell *cell = [tableView dequeueReusableCellWithIdentifier:@"app"];
    if (!cell) cell = [[SFAppCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"app"];
    [self configureCell:cell forApp:self.apps[indexPath.row]];
    return cell;
}

- (void)configureCell:(SFAppCell *)cell forApp:(SFApplication *)app {
    cell.icon.image = app.applicationIcon ?: [SFTheme placeholderIconForName:app.applicationName size:46];
    cell.name.text = app.applicationName;
    cell.name.font = [SFTheme fontOfSize:17 weight:UIFontWeightSemibold];
    cell.bundle.text = nil;
    cell.bundle.hidden = YES;
    cell.bundle.textColor = [SFTheme secondaryText];
    cell.showsSigningDots = NO;
    cell.contentView.alpha = 1;
    cell.contentView.backgroundColor = nil;
    cell.progress.hidden = YES;
    cell.retryButton.hidden = YES;
    cell.daysValue.hidden = NO;
    cell.daysCaption.hidden = NO;
    cell.onRetry = nil;

    // Time left, shown on every row.
    NSDate *date = app.applicationExpiryDate;
    NSTimeInterval left = [date timeIntervalSinceNow];
    NSString *value;
    NSString *caption;
    if (!date || left <= 0) {
        value = SFL(@"Expired");
        caption = SFL(@"sign now");
    } else if (left < 24 * 3600) {
        // Under a day: hours and minutes.
        NSInteger minutes = (NSInteger)(left / 60);
        NSInteger hours = minutes / 60;
        minutes %= 60;
        value = hours > 0 ? [NSString stringWithFormat:(hours == 1 ? SFL(@"%ld hr") : SFL(@"%ld hrs")), (long)hours]
                          : [NSString stringWithFormat:SFL(@"%ld min"), (long)MAX(minutes, (NSInteger)1)];
        caption = hours > 0 ? [NSString stringWithFormat:SFL(@"%ld min left"), (long)minutes] : SFL(@"left");
    } else {
        // Whole days, then the remaining hours ("6 days" / "18 hrs left"). Rounded to the
        // nearest hour, so a freshly signed app shows "7 days" instead of "6 days, 23 hrs".
        NSInteger totalHours = (NSInteger)lround(left / 3600.0);
        NSInteger days = totalHours / 24;
        NSInteger hours = totalHours % 24;
        value = [NSString stringWithFormat:(days == 1 ? SFL(@"%ld day") : SFL(@"%ld days")), (long)days];
        caption = hours == 0 ? SFL(@"left") : [NSString stringWithFormat:(hours == 1 ? SFL(@"%ld hr left") : SFL(@"%ld hrs left")), (long)hours];
    }
    if ([SFSettings isExcluded:app.bundleIdentifier]) caption = [caption stringByAppendingString:@" · manual"];
    cell.daysValue.text = value;
    cell.daysValue.textColor = [SFTheme colorForExpiry:date];
    cell.daysCaption.text = caption;
    cell.accessibilityLabel = [NSString stringWithFormat:@"%@, %@ %@", app.applicationName, value, caption];

    // Signing progress, right on the row.
    SFSigningItem *item = [self itemForApp:app];
    if (!item) return;
    cell.bundle.hidden = NO;
    SFSigningSession *session = [SFSigningSession shared];
    UIColor *amberText = [UIColor colorWithRed:0.96 green:0.73 blue:0.44 alpha:1];
    switch (item.state) {
        case SFSigningItemActive: {
            cell.contentView.backgroundColor = [[SFTheme amber] colorWithAlphaComponent:0.08];
            // "Signing the app" with dots: . .. ... then none, every half second.
            cell.showsSigningDots = YES;
            cell.bundle.text = [self signingTextWithDots];
            cell.bundle.textColor = amberText;
            cell.daysValue.text = [NSString stringWithFormat:@"%d%%", MAX(item.progress, 1)];
            cell.daysValue.textColor = [SFTheme amber];
            cell.daysCaption.hidden = YES;
            cell.progress.hidden = NO;
            [cell.progress setProgress:item.progress / 100.0 animated:YES];
            cell.accessibilityLabel = [NSString stringWithFormat:SFL(@"%@, signing, %d percent"), app.applicationName, item.progress];
            break;
        }
        case SFSigningItemWaiting: {
            if (!session.running) break;
            NSUInteger position = 0, index = 0;
            for (SFSigningItem *other in session.items) {
                if (other.state == SFSigningItemWaiting) index++;
                if (other == item) { position = index; break; }
            }
            cell.contentView.alpha = 0.55;
            cell.bundle.text = SFL(@"Waiting");
            cell.daysValue.text = position <= 1 ? SFL(@"Next") : [NSString stringWithFormat:@"#%lu", (unsigned long)position];
            cell.daysValue.textColor = [SFTheme secondaryText];
            cell.daysCaption.hidden = YES;
            cell.accessibilityLabel = [NSString stringWithFormat:SFL(@"%@, waiting"), app.applicationName];
            break;
        }
        case SFSigningItemDone:
            cell.bundle.text = SFL(@"Signed just now");
            cell.bundle.textColor = [SFTheme success];
            break;
        case SFSigningItemFailed: {
            cell.bundle.text = item.errorMessage ?: SFL(@"Failed");
            cell.bundle.textColor = [SFTheme danger];
            cell.daysValue.hidden = YES;
            cell.daysCaption.hidden = YES;
            cell.retryButton.hidden = session.running;
            __weak typeof(self) weakSelf = self;
            cell.onRetry = ^{
                if ([[SFSigningSession shared] signApplications:@[app]]) [weakSelf sessionChanged];
            };
            cell.accessibilityLabel = [NSString stringWithFormat:SFL(@"%@, failed: %@"), app.applicationName, cell.bundle.text];
            break;
        }
    }
}

// MARK: - Hold an app: Open / Delete

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point {
    if (indexPath.row >= (NSInteger)self.apps.count) return nil;
    SFApplication *app = self.apps[indexPath.row];
    __weak typeof(self) weakSelf = self;
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested) {
        UIAction *open = [UIAction actionWithTitle:SFL(@"Open") image:[UIImage systemImageNamed:@"arrow.up.forward.app"] identifier:nil handler:^(UIAction *action) {
            if (![SFWorkspaceShared() openApplicationWithBundleID:app.bundleIdentifier])
                [weakSelf showSimpleAlert:SFL(@"Couldn't open it") message:SFL(@"iOS didn't open the app. If it has expired, sign it first.")];
        }];
        UIAction *delete = [UIAction actionWithTitle:SFL(@"Delete") image:[UIImage systemImageNamed:@"trash"] identifier:nil handler:^(UIAction *action) {
            [weakSelf confirmDelete:app];
        }];
        delete.attributes = UIMenuElementAttributesDestructive;
        if ([SFSigningSession shared].running) delete.attributes |= UIMenuElementAttributesDisabled;
        return [UIMenu menuWithTitle:@"" children:@[open, delete]];
    }];
}

// MARK: - Swipe an app left: Delete (like Mail / Notes)

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row >= (NSInteger)self.apps.count) return nil;
    if ([SFSigningSession shared].running) return nil;   // same rule as the hold menu
    SFApplication *app = self.apps[indexPath.row];
    __weak typeof(self) weakSelf = self;
    UIContextualAction *delete = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                          title:SFL(@"Delete")
                                                                        handler:^(UIContextualAction *action, UIView *sourceView, void (^completion)(BOOL)) {
        // Slide the row back and ask first; "Yes, delete" removes the row itself.
        completion(NO);
        [weakSelf confirmDelete:app];
    }];
    delete.image = [UIImage systemImageNamed:@"trash"];
    delete.backgroundColor = [UIColor systemRedColor];
    UISwipeActionsConfiguration *config = [UISwipeActionsConfiguration configurationWithActions:@[delete]];
    config.performsFirstActionWithFullSwipe = YES;   // a full swipe opens the same confirmation
    return config;
}

- (void)showSimpleAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SFL(@"OK") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)confirmDelete:(SFApplication *)app {
    NSString *name = app.applicationName ?: SFL(@"this app");
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:SFL(@"Delete %@?"), name]
                                                                   message:SFL(@"The app and its data are removed from this iPhone, and Sevenfold stops signing it.")
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SFL(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:SFL(@"Yes, delete") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        NSString *bundleID = app.bundleIdentifier;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            BOOL ok = [SFWorkspaceShared() uninstallApplication:bundleID withOptions:nil];
            dispatch_async(dispatch_get_main_queue(), ^{
                SFLogEvent(ok ? SFLogLevelInfo : SFLogLevelError, @"%@ %@", ok ? @"deleted" : SFL(@"couldn't delete"), name);
                if (!ok) { [self showSimpleAlert:SFL(@"Couldn't delete") message:[NSString stringWithFormat:SFL(@"iOS didn't remove %@."), name]]; return; }
                // Slide the row out, then refresh.
                NSUInteger index = [self.apps indexOfObject:app];
                if (index != NSNotFound) {
                    NSMutableArray *apps = [self.apps mutableCopy];
                    [apps removeObjectAtIndex:index];
                    self.apps = apps;
                    [self.tableView deleteRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:index inSection:0]] withRowAnimation:UITableViewRowAnimationFade];
                }
                [self updateHeader];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self reload]; });
            });
        });
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    SFSigningItem *item = [self itemForApp:self.apps[indexPath.row]];
    if (item.state == SFSigningItemFailed) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:SFL(@"Couldn't sign %@"), item.name]
                                                                       message:item.fullError ?: item.errorMessage
                                                                preferredStyle:UIAlertControllerStyleAlert];
        SFApplication *app = self.apps[indexPath.row];
        [alert addAction:[UIAlertAction actionWithTitle:SFL(@"Retry") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            if ([[SFSigningSession shared] signApplications:@[app]]) [self sessionChanged];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:SFL(@"Copy error") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [UIPasteboard generalPasteboard].string = item.fullError ?: item.errorMessage ?: @"";
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:SFL(@"Close") style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    SFAppDetailViewController *detail = [[SFAppDetailViewController alloc] initWithApplication:self.apps[indexPath.row] installMode:NO];
    [self.navigationController pushViewController:detail animated:YES];
}

@end
