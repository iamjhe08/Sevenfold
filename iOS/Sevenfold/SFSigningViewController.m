//
//  SFSigningViewController.m
//  Sevenfold
//

#import "SFSigningViewController.h"
#import "SFLocalization.h"
#import "SFTheme.h"
#import "SFSettings.h"
#import "SFSigningSession.h"
#import "SFProgressBar.h"
#import "SFAnisetteServers.h"

#pragma mark - Row

@interface SFSigningCell : UITableViewCell
@property (nonatomic, strong) UIImageView *icon;
@property (nonatomic, strong) UILabel *name;
@property (nonatomic, strong) UILabel *status;
@property (nonatomic, strong) UILabel *step;
@property (nonatomic, strong) SFProgressBar *bar;
@end

@implementation SFSigningCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [SFTheme card];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _icon = [UIImageView new];
        _icon.translatesAutoresizingMaskIntoConstraints = NO;
        _icon.layer.cornerRadius = 10;
        _icon.layer.cornerCurve = kCACornerCurveContinuous;
        _icon.clipsToBounds = YES;
        _name = [SFTheme labelWithSize:16 weight:UIFontWeightSemibold color:[UIColor labelColor]];
        _name.numberOfLines = 1;
        _status = [SFTheme labelWithSize:13 weight:UIFontWeightSemibold color:[SFTheme secondaryText]];
        _status.numberOfLines = 1;
        [_status setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_status setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        _step = [SFTheme labelWithSize:12 weight:UIFontWeightRegular color:[SFTheme secondaryText]];
        _step.numberOfLines = 2;
        _bar = [SFProgressBar new];
        [_bar.heightAnchor constraintEqualToConstant:6].active = YES;

        UIStackView *top = [[UIStackView alloc] initWithArrangedSubviews:@[_name, _status]];
        top.spacing = 8;
        top.alignment = UIStackViewAlignmentFirstBaseline;
        UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[top, _bar, _step]];
        text.axis = UILayoutConstraintAxisVertical;
        text.spacing = 7;
        text.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_icon];
        [self.contentView addSubview:text];
        [NSLayoutConstraint activateConstraints:@[
            [_icon.widthAnchor constraintEqualToConstant:44],
            [_icon.heightAnchor constraintEqualToConstant:44],
            [_icon.leadingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.leadingAnchor],
            [_icon.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [text.leadingAnchor constraintEqualToAnchor:_icon.trailingAnchor constant:14],
            [text.trailingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.trailingAnchor],
            [text.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:14],
            [text.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-14],
        ]];
    }
    return self;
}

- (void)configureWithItem:(SFSigningItem *)item {
    self.icon.image = item.icon ?: [SFTheme placeholderIconForName:item.name size:44];
    self.name.text = item.name;
    self.step.text = item.stepText;
    self.bar.complete = item.state == SFSigningItemDone;
    self.bar.failed = item.state == SFSigningItemFailed;
    switch (item.state) {
        case SFSigningItemWaiting:
            self.status.text = SFL(@"Waiting");
            self.status.textColor = [SFTheme secondaryText];
            [self.bar setProgress:0 animated:NO];
            break;
        case SFSigningItemActive:
            self.status.text = [NSString stringWithFormat:@"%d%%", item.progress];
            self.status.textColor = [SFTheme accent];
            [self.bar setProgress:item.progress / 100.0 animated:YES];
            break;
        case SFSigningItemDone:
            self.status.text = SFL(@"Done");
            self.status.textColor = [SFTheme success];
            [self.bar setProgress:1 animated:YES];
            break;
        case SFSigningItemFailed:
            self.status.text = SFL(@"Failed");
            self.status.textColor = [SFTheme danger];
            [self.bar setProgress:1 animated:NO];
            break;
    }
}

@end

#pragma mark - Screen

@interface SFSigningViewController ()
@property (nonatomic, strong) UIView *header;
@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, strong) UILabel *percentLabel;
@property (nonatomic, strong) UILabel *nowLabel;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) SFProgressBar *overallBar;
@property (nonatomic, strong) UILabel *noteLabel;
@property (nonatomic, strong) UIView *noteView;
@property (nonatomic, strong) UIButton *footerButton;
@property (nonatomic, strong) NSTimer *clock;
@property (nonatomic, copy) NSArray<SFSigningItem *> *items;
@end

@implementation SFSigningViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = SFL(@"Signing apps");
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:SFL(@"Hide") style:UIBarButtonItemStylePlain target:self action:@selector(close)];
    self.tableView.backgroundColor = [SFTheme background];
    self.tableView.separatorColor = [SFTheme separator];
    [self.tableView registerClass:[SFSigningCell class] forCellReuseIdentifier:@"item"];
    [self buildHeader];
    [self buildFooter];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:SFSigningSessionDidChangeNotification object:nil];
    [self refresh];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    self.clock = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(tick) userInfo:nil repeats:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.clock invalidate];
    self.clock = nil;
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)buildHeader {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 375, 200)];
    UIView *card = [UIView new];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = [SFTheme midnight];
    card.layer.cornerRadius = 20;
    card.layer.cornerCurve = kCACornerCurveContinuous;

    UIColor *mist = [UIColor colorWithRed:0.79 green:0.82 blue:0.92 alpha:1];
    self.countLabel = [SFTheme labelWithSize:15 weight:UIFontWeightSemibold color:[UIColor whiteColor]];
    self.percentLabel = [SFTheme labelWithSize:32 weight:UIFontWeightHeavy color:[SFTheme amberLight]];
    self.percentLabel.textAlignment = [SFLanguage isRightToLeft] ? NSTextAlignmentLeft : NSTextAlignmentRight;
    self.percentLabel.font = [UIFont monospacedDigitSystemFontOfSize:32 weight:UIFontWeightHeavy];
    UIStackView *top = [[UIStackView alloc] initWithArrangedSubviews:@[self.countLabel, self.percentLabel]];
    top.alignment = UIStackViewAlignmentLastBaseline;

    self.overallBar = [SFProgressBar new];
    self.overallBar.trackColor = [UIColor colorWithWhite:1 alpha:0.14];
    [self.overallBar.heightAnchor constraintEqualToConstant:10].active = YES;

    self.nowLabel = [SFTheme labelWithSize:13 weight:UIFontWeightRegular color:mist];
    self.nowLabel.numberOfLines = 1;
    self.timeLabel = [SFTheme labelWithSize:13 weight:UIFontWeightRegular color:mist];
    self.timeLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightRegular];
    self.timeLabel.textAlignment = [SFLanguage isRightToLeft] ? NSTextAlignmentLeft : NSTextAlignmentRight;
    [self.timeLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *bottom = [[UIStackView alloc] initWithArrangedSubviews:@[self.nowLabel, self.timeLabel]];
    bottom.spacing = 8;

    UIStackView *cardStack = [[UIStackView alloc] initWithArrangedSubviews:@[top, self.overallBar, bottom]];
    cardStack.axis = UILayoutConstraintAxisVertical;
    cardStack.spacing = 12;
    cardStack.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:cardStack];
    [header addSubview:card];

    // Server switch note
    self.noteView = [UIView new];
    self.noteView.translatesAutoresizingMaskIntoConstraints = NO;
    self.noteView.backgroundColor = [[SFTheme amber] colorWithAlphaComponent:0.14];
    self.noteView.layer.cornerRadius = 14;
    self.noteLabel = [SFTheme labelWithSize:13 weight:UIFontWeightRegular color:[SFTheme warning]];
    [self.noteView addSubview:self.noteLabel];
    [header addSubview:self.noteView];

    [NSLayoutConstraint activateConstraints:@[
        [card.topAnchor constraintEqualToAnchor:header.topAnchor constant:8],
        [card.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20],
        [card.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20],
        [cardStack.topAnchor constraintEqualToAnchor:card.topAnchor constant:18],
        [cardStack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-18],
        [cardStack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18],
        [cardStack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-18],
        [self.noteView.topAnchor constraintEqualToAnchor:card.bottomAnchor constant:12],
        [self.noteView.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [self.noteView.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [self.noteView.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-4],
        [self.noteLabel.topAnchor constraintEqualToAnchor:self.noteView.topAnchor constant:11],
        [self.noteLabel.bottomAnchor constraintEqualToAnchor:self.noteView.bottomAnchor constant:-11],
        [self.noteLabel.leadingAnchor constraintEqualToAnchor:self.noteView.leadingAnchor constant:14],
        [self.noteLabel.trailingAnchor constraintEqualToAnchor:self.noteView.trailingAnchor constant:-14],
    ]];
    self.header = header;
    self.tableView.tableHeaderView = header;
}

- (void)buildFooter {
    UIView *footer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 375, 90)];
    self.footerButton = [SFTheme secondaryButtonWithTitle:SFL(@"Stop after this app")];
    [self.footerButton addTarget:self action:@selector(footerTapped) forControlEvents:UIControlEventTouchUpInside];
    [footer addSubview:self.footerButton];
    [NSLayoutConstraint activateConstraints:@[
        [self.footerButton.topAnchor constraintEqualToAnchor:footer.topAnchor constant:12],
        [self.footerButton.leadingAnchor constraintEqualToAnchor:footer.leadingAnchor constant:20],
        [self.footerButton.trailingAnchor constraintEqualToAnchor:footer.trailingAnchor constant:-20],
    ]];
    self.tableView.tableFooterView = footer;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.tableView.bounds.size.width;
    CGSize size = [self.header systemLayoutSizeFittingSize:CGSizeMake(width, 0)
                             withHorizontalFittingPriority:UILayoutPriorityRequired
                                   verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    if (fabs(self.header.frame.size.height - size.height) > 0.5 || fabs(self.header.frame.size.width - width) > 0.5) {
        self.header.frame = CGRectMake(0, 0, width, size.height);
        self.tableView.tableHeaderView = self.header;
    }
}

- (NSString *)elapsedText {
    SFSigningSession *session = [SFSigningSession shared];
    if (!session.startDate) return @"";
    NSDate *end = session.endDate ?: [NSDate date];
    NSInteger seconds = (NSInteger)[end timeIntervalSinceDate:session.startDate];
    NSString *clock = [NSString stringWithFormat:@"%ld:%02ld", (long)(seconds / 60), (long)(seconds % 60)];
    return session.running ? [NSString stringWithFormat:SFL(@"%@ elapsed"), clock] : [NSString stringWithFormat:SFL(@"Took %@"), clock];
}

- (void)tick {
    self.timeLabel.text = [self elapsedText];
}

- (void)refresh {
    SFSigningSession *session = [SFSigningSession shared];
    self.items = session.items;
    NSUInteger total = self.items.count;
    NSUInteger done = session.doneCount;
    NSUInteger failed = session.failedCount;
    NSUInteger finishedCount = done + failed;
    float progress = session.overallProgress;
    BOOL finished = session.finished && !session.running;

    if (finished) {
        if (session.runError && done == 0) self.title = SFL(@"Signing failed");
        else if (failed > 0) self.title = [NSString stringWithFormat:SFL(@"%lu of %lu signed"), (unsigned long)done, (unsigned long)total];
        else if (total == 0) self.title = SFL(@"Nothing to sign");
        else self.title = total == 1 ? SFL(@"App signed") : [NSString stringWithFormat:SFL(@"All %lu apps signed"), (unsigned long)total];
    } else {
        self.title = SFL(@"Signing apps");
    }

    NSUInteger current = MIN(finishedCount + (session.running ? 1 : 0), total);
    self.countLabel.text = finished ? [NSString stringWithFormat:SFL(@"%lu of %lu apps"), (unsigned long)done, (unsigned long)total]
                                    : [NSString stringWithFormat:SFL(@"%lu of %lu apps"), (unsigned long)MAX(current, (NSUInteger)(total ? 1 : 0)), (unsigned long)total];
    self.percentLabel.text = [NSString stringWithFormat:@"%d%%", (int)roundf(progress * 100)];
    self.percentLabel.textColor = finished && failed == 0 && !session.runError ? [UIColor colorWithRed:0.49 green:0.89 blue:0.66 alpha:1] : [SFTheme amberLight];
    self.overallBar.complete = finished && failed == 0 && !session.runError;
    self.overallBar.failed = finished && done == 0 && (failed > 0 || session.runError);
    [self.overallBar setProgress:finished ? 1 : progress animated:YES];

    if (finished) {
        if (session.runError && done == 0) self.nowLabel.text = session.runError;
        else if (done > 0) {
            NSDateFormatter *formatter = [NSDateFormatter new];
            formatter.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"EEE MMM d" options:0 locale:[NSLocale currentLocale]];
            self.nowLabel.text = [NSString stringWithFormat:SFL(@"Valid until %@"), [formatter stringFromDate:[NSDate dateWithTimeIntervalSinceNow:7 * 24 * 3600]]];
        } else self.nowLabel.text = SFL(@"No apps needed signing");
    } else {
        SFSigningItem *active = session.activeItem;
        self.nowLabel.text = active ? [NSString stringWithFormat:SFL(@"Now: %@"), active.name] : SFL(@"Signing in to Apple…");
    }
    self.timeLabel.text = [self elapsedText];

    // Show a note when sign-in is using a fallback server.
    NSArray *servers = [SFAnisetteServers servers];
    NSString *lastGood = [SFAnisetteServers lastGoodServer];
    NSString *first = servers.count ? [servers.firstObject[@"url"] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]] : nil;
    BOOL usingFallback = lastGood && first && ![lastGood hasPrefix:first] && ![first hasPrefix:lastGood];
    self.noteView.hidden = !usingFallback;
    if (usingFallback)
        self.noteLabel.text = [NSString stringWithFormat:SFL(@"%@ wasn't responding, so Sevenfold is using %@'s server."),
                               servers.firstObject[@"name"] ?: SFL(@"The first server"), [SFAnisetteServers nameForServer:lastGood]];

    UIButtonConfiguration *config;
    if (finished) {
        config = [UIButtonConfiguration filledButtonConfiguration];
        config.baseBackgroundColor = [SFTheme accent];
        config.title = SFL(@"Done");
    } else {
        config = [UIButtonConfiguration tintedButtonConfiguration];
        config.baseBackgroundColor = [SFTheme accent];
        config.baseForegroundColor = [SFTheme accent];
        config.title = session.stopRequested ? SFL(@"Stopping after this app…") : SFL(@"Stop after this app");
    }
    config.cornerStyle = UIButtonConfigurationCornerStyleLarge;
    config.contentInsets = NSDirectionalEdgeInsetsMake(15, 16, 15, 16);
    self.footerButton.configuration = config;
    self.footerButton.enabled = finished || !session.stopRequested;

    [self.tableView reloadData];
    [self.view setNeedsLayout];
}

- (void)footerTapped {
    SFSigningSession *session = [SFSigningSession shared];
    if (session.finished && !session.running) [self close];
    else [session requestStopAfterCurrent];
}

// MARK: - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.items.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    SFSigningSession *session = [SFSigningSession shared];
    if (session.finished && !session.running && [SFSettings automaticSigning])
        return [NSString stringWithFormat:SFL(@"Next automatic run: %@."), [SFTheme shortDateTime:[SFSettings nextScheduledRun]]];
    if (session.running) return SFL(@"You can hide this screen. Signing continues in the background.");
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SFSigningCell *cell = [tableView dequeueReusableCellWithIdentifier:@"item" forIndexPath:indexPath];
    SFSigningItem *item = self.items[indexPath.row];
    [cell configureWithItem:item];
    BOOL hasDetails = item.state == SFSigningItemFailed && item.fullError.length > 0;
    cell.accessoryType = hasDetails ? UITableViewCellAccessoryDetailButton : UITableViewCellAccessoryNone;
    cell.selectionStyle = hasDetails ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    return cell;
}

- (void)showDetailsForRow:(NSInteger)row {
    if (row >= (NSInteger)self.items.count) return;
    SFSigningItem *item = self.items[row];
    if (item.fullError.length == 0) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:SFL(@"%@ failed"), item.name]
                                                                   message:item.fullError
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SFL(@"Copy") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [UIPasteboard generalPasteboard].string = item.fullError;
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:SFL(@"OK") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self showDetailsForRow:indexPath.row];
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath {
    [self showDetailsForRow:indexPath.row];
}

@end
