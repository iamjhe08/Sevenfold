//
//  SFLanguageViewController.m
//  Sevenfold
//
//  BY: T4MAG0
//

#import "SFLanguageViewController.h"
#import "SFLocalization.h"
#import "SFTheme.h"

@implementation SFLanguageViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = SFL(@"Language");
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 1 : (NSInteger)[SFLanguage available].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 1 ? SFL(@"Languages") : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *selected = [SFLanguage selectedCode];
    UITableViewCell *cell;
    NSString *code;
    if (indexPath.section == 0) {
        cell = [self subtitleCellWithTitle:SFL(@"Auto (System Language)") subtitle:SFL(@"Follows your system language")];
        code = @"auto";
    } else {
        NSDictionary *language = [SFLanguage available][indexPath.row];
        code = language[@"code"];
        // Each language in its own script; the English name underneath (none for English itself).
        NSString *english = [language[@"english"] length] ? language[@"english"] : nil;
        cell = [self subtitleCellWithTitle:language[@"native"] subtitle:english];
    }
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.tintColor = [SFTheme accent];
    cell.accessoryType = [code isEqualToString:selected] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *code = indexPath.section == 0 ? @"auto" : [SFLanguage available][indexPath.row][@"code"];
    if ([code isEqualToString:[SFLanguage selectedCode]]) return;
    [SFLanguage setSelectedCode:code];   // the app redraws its screens in the new language
}

@end
