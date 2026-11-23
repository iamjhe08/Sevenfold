//
//  SFShareCertificateViewController.m
//  Sevenfold
//

#import "SFShareCertificateViewController.h"
#import "SFLocalization.h"
#import "SFCertificateStore.h"
#import "SFTheme.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface SFShareCertificateViewController () <UIDocumentPickerDelegate>
@property (nonatomic, strong) UIView *header;
@property (nonatomic, strong) UISegmentedControl *modePicker;
@property (nonatomic, strong) UITextField *passwordField;
@property (nonatomic, strong) UITextField *confirmField;
@end

@implementation SFShareCertificateViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = SFL(@"Share certificate");
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    if (self.navigationController.viewControllers.firstObject == self)
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(close)];

    self.modePicker = [[UISegmentedControl alloc] initWithItems:@[SFL(@"Send"), SFL(@"Receive")]];
    self.modePicker.selectedSegmentIndex = self.pendingImportURL ? 1 : 0;
    [self.modePicker addTarget:self action:@selector(modeChanged) forControlEvents:UIControlEventValueChanged];
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 375, 120)];
    UILabel *intro = [SFTheme labelWithSize:15 weight:UIFontWeightRegular color:[SFTheme secondaryText]];
    intro.text = SFL(@"Use one certificate on both iPhones so they stop revoking each other and only use one slot.");
    self.modePicker.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:intro];
    [header addSubview:self.modePicker];
    [NSLayoutConstraint activateConstraints:@[
        [intro.topAnchor constraintEqualToAnchor:header.topAnchor constant:8],
        [intro.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:24],
        [intro.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-24],
        [self.modePicker.topAnchor constraintEqualToAnchor:intro.bottomAnchor constant:16],
        [self.modePicker.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20],
        [self.modePicker.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20],
        [self.modePicker.heightAnchor constraintEqualToConstant:36],
        [self.modePicker.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-8],
    ]];
    self.header = header;
    self.tableView.tableHeaderView = header;

    self.passwordField = [self secureField:SFL(@"Password")];
    self.confirmField = [self secureField:SFL(@"Repeat password")];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.pendingImportURL) {
        NSURL *url = self.pendingImportURL;
        self.pendingImportURL = nil;
        [self askPasswordAndImport:url];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.tableView.bounds.size.width;
    if (width <= 0 || !self.header) return;
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

- (UITextField *)secureField:(NSString *)placeholder {
    UITextField *field = [UITextField new];
    field.placeholder = placeholder;
    field.secureTextEntry = YES;
    field.textContentType = UITextContentTypeNewPassword;
    field.translatesAutoresizingMaskIntoConstraints = NO;
    return field;
}

- (BOOL)sending {
    return self.modePicker.selectedSegmentIndex == 0;
}

- (void)modeChanged {
    [self.view endEditing:YES];
    [self.tableView reloadData];
}

// MARK: - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.sending ? 3 : 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.sending && section == 0) return 2;
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (self.sending) {
        if (section == 0) return SFL(@"1. Protect the file");
        if (section == 1) return SFL(@"2. Send it to your other iPhone");
        return nil;
    }
    return section == 0 ? SFL(@"Import a shared certificate") : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (self.sending) {
        if (section == 0) return SFL(@"You'll type this password on the other iPhone.");
        if (section == 1) return SFL(@"Send it with AirDrop or save it to Files. On the other iPhone, open the file with Sevenfold, or go to Certificates › Share › Receive.");
        return SFL(@"The file contains your private signing key. Only send it to your own devices.");
    }
    return SFL(@"Both iPhones must be signed in to the same Apple ID. After importing, this iPhone signs with the shared certificate, and you can revoke its old one in Certificates to free a slot.");
}

- (UITableViewCell *)fieldCell:(UITextField *)field {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.backgroundColor = [SFTheme card];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    [field removeFromSuperview];
    [cell.contentView addSubview:field];
    UILayoutGuide *m = cell.contentView.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [field.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
        [field.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
        [field.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor],
        [field.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor],
        [field.heightAnchor constraintGreaterThanOrEqualToConstant:48],
    ]];
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.sending) {
        if (indexPath.section == 0) return [self fieldCell:indexPath.row == 0 ? self.passwordField : self.confirmField];
        if (indexPath.section == 1) return [self buttonCellWithTitle:SFL(@"Create file and share") color:nil];
        UITableViewCell *warning = [self subtitleCellWithTitle:SFL(@"Keep it private") subtitle:nil];
        UIListContentConfiguration *config = (UIListContentConfiguration *)warning.contentConfiguration;
        config.image = [SFTheme symbol:@"exclamationmark.shield.fill" size:18 weight:UIImageSymbolWeightSemibold];
        config.imageProperties.tintColor = [SFTheme warning];
        warning.contentConfiguration = config;
        return warning;
    }
    return [self buttonCellWithTitle:SFL(@"Choose .sevenfold-cert file") color:nil];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.sending && indexPath.section == 1) [self exportFile];
    else if (!self.sending && indexPath.section == 0) [self pickFile];
}

// MARK: - Send

- (void)exportFile {
    [self.view endEditing:YES];
    if (![self.passwordField.text isEqualToString:self.confirmField.text ?: @""]) {
        [self showMessage:SFL(@"The two passwords don't match.") title:SFL(@"Check the password")];
        return;
    }
    NSError *error = nil;
    NSURL *url = [SFCertificateStore exportCertificateWithPassword:self.passwordField.text ?: @"" error:&error];
    if (!url) { [self showError:error title:SFL(@"Can't share yet")]; return; }
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    share.popoverPresentationController.sourceView = self.view;
    share.completionWithItemsHandler = ^(UIActivityType type, BOOL completed, NSArray *items, NSError *activityError) {
        [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
    };
    [self presentViewController:share animated:YES completion:nil];
}

// MARK: - Receive

- (void)pickFile {
    UTType *type = [UTType typeWithFilenameExtension:@"sevenfold-cert"] ?: UTTypeData;
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[type, UTTypeData, UTTypeJSON] asCopy:YES];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (url) dispatch_async(dispatch_get_main_queue(), ^{ [self askPasswordAndImport:url]; });
}

- (void)askPasswordAndImport:(NSURL *)url {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:SFL(@"File password") message:SFL(@"Enter the password you chose on the other iPhone.") preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.secureTextEntry = YES;
        field.placeholder = SFL(@"Password");
    }];
    [alert addAction:[UIAlertAction actionWithTitle:SFL(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:SFL(@"Import and use") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSError *error = nil;
        NSString *summary = nil;
        if ([SFCertificateStore importCertificateAtURL:url password:alert.textFields.firstObject.text ?: @"" summary:&summary error:&error]) {
            [self showMessage:summary ?: SFL(@"Certificate imported.") title:SFL(@"Certificate imported")];
        } else {
            [self showError:error title:SFL(@"Couldn't import")];
        }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
