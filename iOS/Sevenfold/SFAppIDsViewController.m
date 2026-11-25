//
//  SFAppIDsViewController.m
//  Sevenfold
//
//  BY: T4MAG0
//

#import "SFAppIDsViewController.h"
#import "SFAppIDBudget.h"
#import "SFLocalization.h"
#import "SFTheme.h"

@implementation SFAppIDsViewController

/// "Thu" within the coming week, "4 Dec" further out, "today" for today.
+ (NSString *)dayName:(NSDate *)day {
    NSCalendar *calendar = [NSCalendar currentCalendar];
    if ([calendar isDateInToday:day]) return SFL(@"today");
    NSDateFormatter *formatter = [NSDateFormatter new];
    NSInteger days = [calendar components:NSCalendarUnitDay fromDate:[calendar startOfDayForDate:[NSDate date]] toDate:day options:0].day;
    [formatter setLocalizedDateFormatFromTemplate:days < 7 ? @"EEE" : @"d MMM"];
    return [formatter stringFromDate:day];
}

+ (NSString *)nextFreeUpSummary {
    NSDictionary *next = [SFAppIDBudget shared].freeUps.firstObject;
    if (!next) return nil;
    return [NSString stringWithFormat:SFL(@"+%ld free on %@"), (long)[next[@"count"] integerValue], [self dayName:next[@"date"]]];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = SFL(@"App IDs this week");
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];
    [[NSNotificationCenter defaultCenter] addObserver:self.tableView selector:@selector(reloadData) name:SFAppIDBudgetDidChangeNotification object:nil];
    [[SFAppIDBudget shared] refreshForce:NO];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self.tableView];
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return MAX(1, (NSInteger)[SFAppIDBudget shared].freeUps.count);
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    SFAppIDBudget *budget = [SFAppIDBudget shared];
    return budget.used >= 0 ? [NSString stringWithFormat:SFL(@"%ld of 10 in use"), (long)budget.used] : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return SFL(@"Free Apple IDs can create 10 App IDs. Each one frees up 7 days after it was made. Apple doesn't say which app an App ID belonged to, so only dates are shown.");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSArray *ups = [SFAppIDBudget shared].freeUps;
    if (ups.count == 0) return [self valueCellWithTitle:SFL(@"Nothing waiting to free up") value:nil];
    NSDictionary *up = ups[indexPath.row];
    NSDateFormatter *formatter = [NSDateFormatter new];
    [formatter setLocalizedDateFormatFromTemplate:@"EEE d MMM"];
    NSString *date = [[NSCalendar currentCalendar] isDateInToday:up[@"date"]] ? SFL(@"Today") : [formatter stringFromDate:up[@"date"]];
    UITableViewCell *cell = [self valueCellWithTitle:date value:[NSString stringWithFormat:SFL(@"+%ld free"), (long)[up[@"count"] integerValue]]];
    if ([cell.contentConfiguration isKindOfClass:[UIListContentConfiguration class]]) {
        UIListContentConfiguration *config = (UIListContentConfiguration *)cell.contentConfiguration;
        config.secondaryTextProperties.color = [SFTheme success];
        config.secondaryTextProperties.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        cell.contentConfiguration = config;
    }
    return cell;
}

@end
