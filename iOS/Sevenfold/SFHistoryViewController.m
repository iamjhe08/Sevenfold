//
//  SFHistoryViewController.m
//  Sevenfold
//

#import "SFHistoryViewController.h"
#import "SFLocalization.h"
#import "SFHistory.h"
#import "SFTheme.h"

typedef NS_ENUM(NSInteger, SFRunOutcome) { SFRunSuccess, SFRunPartial, SFRunFailed, SFRunNothing };

static SFRunOutcome SFOutcome(NSDictionary *run) {
    if ([run[@"nothingToDo"] boolValue]) return SFRunNothing;
    NSInteger signedCount = [run[@"signed"] integerValue], failed = [run[@"failed"] integerValue];
    if (signedCount > 0 && failed == 0 && !run[@"reason"]) return SFRunSuccess;
    if (signedCount > 0) return SFRunPartial;
    return SFRunFailed;
}

static NSString *SFRunTitle(NSDictionary *run) {
    NSInteger signedCount = [run[@"signed"] integerValue], failed = [run[@"failed"] integerValue];
    NSArray *apps = run[@"apps"];
    switch (SFOutcome(run)) {
        case SFRunNothing: return SFL(@"No apps needed signing");
        case SFRunSuccess:
            if (signedCount == 1 && apps.count == 1) return [NSString stringWithFormat:SFL(@"Signed %@"), apps.firstObject[@"name"]];
            return [NSString stringWithFormat:SFL(@"Signed %ld apps"), (long)signedCount];
        case SFRunPartial: return [NSString stringWithFormat:SFL(@"Signed %ld, %ld failed"), (long)signedCount, (long)failed];
        case SFRunFailed:
            if (apps.count == 1) return [NSString stringWithFormat:SFL(@"Couldn't sign %@"), apps.firstObject[@"name"]];
            return apps.count > 1 ? [NSString stringWithFormat:SFL(@"Couldn't sign %lu apps"), (unsigned long)apps.count] : SFL(@"Signing failed");
    }
    return @"";
}

static NSString *SFRunSubtitle(NSDictionary *run) {
    NSDateFormatter *time = [NSDateFormatter new];
    time.dateStyle = NSDateFormatterNoStyle;
    time.timeStyle = NSDateFormatterShortStyle;
    NSMutableArray *parts = [NSMutableArray arrayWithObject:[time stringFromDate:run[@"date"]]];
    [parts addObject:[run[@"automatic"] boolValue] ? SFL(@"Automatic") : SFL(@"Manual")];
    double seconds = [run[@"seconds"] doubleValue];
    if (seconds > 0) [parts addObject:seconds < 60 ? [NSString stringWithFormat:@"%.0fs", MAX(seconds, 1)] : [NSString stringWithFormat:@"%.0fm %02.0fs", floor(seconds / 60), fmod(seconds, 60)]];
    NSString *line = [parts componentsJoinedByString:@" · "];
    if (SFOutcome(run) == SFRunFailed && run[@"reason"]) line = [line stringByAppendingFormat:@"\n%@", run[@"reason"]];
    else if (SFOutcome(run) != SFRunNothing && SFOutcome(run) != SFRunSuccess) {
        for (NSDictionary *app in run[@"apps"]) if (![app[@"ok"] boolValue] && app[@"reason"]) { line = [line stringByAppendingFormat:@"\n%@", app[@"reason"]]; break; }
    }
    return line;
}

static UIImage *SFOutcomeIcon(SFRunOutcome outcome, UIColor **tint) {
    switch (outcome) {
        case SFRunSuccess: *tint = [SFTheme success]; return [UIImage systemImageNamed:@"checkmark.circle.fill"];
        case SFRunPartial: *tint = [SFTheme warning]; return [UIImage systemImageNamed:@"exclamationmark.circle.fill"];
        case SFRunFailed: *tint = [SFTheme danger]; return [UIImage systemImageNamed:@"xmark.circle.fill"];
        case SFRunNothing: *tint = [SFTheme secondaryText]; return [UIImage systemImageNamed:@"minus.circle.fill"];
    }
    return nil;
}

#pragma mark - History list

@interface SFHistoryViewController ()
@property (nonatomic, strong) NSArray<NSDictionary *> *sections; // { title, runs }
@property (nonatomic, strong) UISegmentedControl *filter;
@end

@implementation SFHistoryViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.filter = [[UISegmentedControl alloc] initWithItems:@[SFL(@"All"), SFL(@"Signed"), SFL(@"Failed")]];
    self.filter.selectedSegmentIndex = 0;
    [self.filter addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 375, 52)];
    self.filter.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:self.filter];
    [NSLayoutConstraint activateConstraints:@[
        [self.filter.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20],
        [self.filter.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20],
        [self.filter.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [self.filter.heightAnchor constraintEqualToConstant:34],
    ]];
    self.tableView.tableHeaderView = header;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"trash"] style:UIBarButtonItemStylePlain target:self action:@selector(clearTapped)];
    self.navigationItem.rightBarButtonItem.accessibilityLabel = SFL(@"Clear history");
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload) name:SFHistoryDidChangeNotification object:nil];
    [self reload];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

- (void)reload {
    NSInteger mode = self.filter.selectedSegmentIndex;
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateFormatter *dayFormatter = [NSDateFormatter new];
    dayFormatter.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"EEEE MMM d" options:0 locale:[NSLocale currentLocale]];
    NSMutableArray *sections = [NSMutableArray array];
    NSMutableArray *current = nil;
    NSDate *currentDay = nil;
    for (NSDictionary *run in [SFHistory runs]) {
        SFRunOutcome outcome = SFOutcome(run);
        if (mode == 1 && outcome != SFRunSuccess && outcome != SFRunPartial) continue;
        if (mode == 2 && outcome != SFRunFailed && outcome != SFRunPartial) continue;
        NSDate *day = [calendar startOfDayForDate:run[@"date"]];
        if (!currentDay || ![day isEqualToDate:currentDay]) {
            currentDay = day;
            current = [NSMutableArray array];
            NSString *title = [calendar isDateInToday:day] ? SFL(@"Today") : [calendar isDateInYesterday:day] ? SFL(@"Yesterday") : [dayFormatter stringFromDate:day];
            [sections addObject:@{ @"title": title, @"runs": current }];
        }
        [current addObject:run];
    }
    self.sections = sections;
    [self.tableView reloadData];
}

- (void)clearTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:SFL(@"Clear history?") message:SFL(@"This removes the list of past signing runs. Your apps aren't affected.") preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SFL(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:SFL(@"Clear") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [SFHistory clear];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return MAX(self.sections.count, 1);
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.sections.count == 0) return 1;
    return [self.sections[section][@"runs"] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.sections.count ? self.sections[section][@"title"] : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.sections.count == 0) {
        NSString *text = self.filter.selectedSegmentIndex == 0 ? SFL(@"No signing runs yet") : SFL(@"Nothing here");
        UITableViewCell *cell = [self subtitleCellWithTitle:text subtitle:SFL(@"Every manual and automatic run appears here.")];
        return cell;
    }
    NSDictionary *run = self.sections[indexPath.section][@"runs"][indexPath.row];
    UITableViewCell *cell = [self subtitleCellWithTitle:SFRunTitle(run) subtitle:SFRunSubtitle(run)];
    UIListContentConfiguration *config = (UIListContentConfiguration *)cell.contentConfiguration;
    UIColor *tint = nil;
    config.image = SFOutcomeIcon(SFOutcome(run), &tint);
    config.imageProperties.tintColor = tint;
    config.textProperties.font = [SFTheme fontOfSize:16 weight:UIFontWeightSemibold];
    config.secondaryTextProperties.numberOfLines = 2;
    cell.contentConfiguration = config;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.sections.count == 0) return;
    NSDictionary *run = self.sections[indexPath.section][@"runs"][indexPath.row];
    [self.navigationController pushViewController:[[SFHistoryRunViewController alloc] initWithRun:run] animated:YES];
}

@end

#pragma mark - One run

@interface SFHistoryRunViewController ()
@property (nonatomic, strong) NSDictionary *run;
@end

@implementation SFHistoryRunViewController

- (instancetype)initWithRun:(NSDictionary *)run {
    self = [super init];
    if (self) _run = run;
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = SFRunTitle(self.run);
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
}

- (NSArray *)apps {
    return [self.run[@"apps"] isKindOfClass:[NSArray class]] ? self.run[@"apps"] : @[];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.run[@"error"] ? 3 : 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 3;
    if (section == 1) return MAX(self.apps.count, 1);
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[SFL(@"Run"), SFL(@"Apps"), SFL(@"Error from Apple")][section];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        switch (indexPath.row) {
            case 0: {
                NSDateFormatter *formatter = [NSDateFormatter new];
                formatter.dateStyle = NSDateFormatterMediumStyle;
                formatter.timeStyle = NSDateFormatterMediumStyle;
                return [self valueCellWithTitle:SFL(@"When") value:[formatter stringFromDate:self.run[@"date"]]];
            }
            case 1: return [self valueCellWithTitle:SFL(@"Started by") value:[self.run[@"automatic"] boolValue] ? SFL(@"Schedule (automatic)") : SFL(@"You (manual)")];
            default: return [self valueCellWithTitle:SFL(@"Took") value:[NSString stringWithFormat:SFL(@"%.1f seconds"), [self.run[@"seconds"] doubleValue]]];
        }
    }
    if (indexPath.section == 2) {
        UITableViewCell *cell = [self subtitleCellWithTitle:self.run[@"error"] subtitle:SFL(@"Tap to copy")];
        UIListContentConfiguration *config = (UIListContentConfiguration *)cell.contentConfiguration;
        config.textProperties.font = [SFTheme monoFontOfSize:13];
        cell.contentConfiguration = config;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        return cell;
    }
    if (self.apps.count == 0) return [self subtitleCellWithTitle:[self.run[@"nothingToDo"] boolValue] ? SFL(@"No app was close enough to expiring") : SFL(@"No apps") subtitle:nil];
    NSDictionary *app = self.apps[indexPath.row];
    BOOL ok = [app[@"ok"] boolValue];
    NSString *subtitle = ok ? SFL(@"Signed · valid 7 days") : (app[@"reason"] ?: SFL(@"Failed"));
    UITableViewCell *cell = [self subtitleCellWithTitle:app[@"name"] subtitle:subtitle];
    UIListContentConfiguration *config = (UIListContentConfiguration *)cell.contentConfiguration;
    config.image = [UIImage systemImageNamed:ok ? @"checkmark.circle.fill" : @"xmark.circle.fill"];
    config.imageProperties.tintColor = ok ? [SFTheme success] : [SFTheme danger];
    cell.contentConfiguration = config;
    if (!ok && app[@"error"]) {
        cell.accessoryType = UITableViewCellAccessoryDetailButton;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }
    return cell;
}

- (void)showErrorText:(NSString *)text title:(NSString *)title {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:text preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SFL(@"Copy") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [UIPasteboard generalPasteboard].string = text;
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:SFL(@"OK") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 2) {
        [UIPasteboard generalPasteboard].string = self.run[@"error"];
        [self showMessage:SFL(@"The error was copied.") title:SFL(@"Copied")];
        return;
    }
    if (indexPath.section == 1 && indexPath.row < (NSInteger)self.apps.count) {
        NSDictionary *app = self.apps[indexPath.row];
        if (app[@"error"]) [self showErrorText:app[@"error"] title:[NSString stringWithFormat:SFL(@"%@ failed"), app[@"name"]]];
    }
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath {
    [self tableView:tableView didSelectRowAtIndexPath:indexPath];
}

@end
