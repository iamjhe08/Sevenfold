//
//  SFSignInViewController.m
//  Sevenfold
//

#import "SFSignInViewController.h"
#import "SFLocalization.h"
#import "SFTheme.h"
#import "SFSettings.h"
#import "SFLog.h"
#import "SFDevice.h"
#import "SFAccountChecker.h"
#import "SFResources.h"
#import "SFAppleServices.h"
#import "SFNetworkAccess.h"
#import "SFLanguageViewController.h"
#import "SFSettingsViewController.h"

static UITextField *SFField(NSString *placeholder) {
    UITextField *field = [UITextField new];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.placeholder = placeholder;
    field.font = [SFTheme fontOfSize:17 weight:UIFontWeightRegular];
    field.backgroundColor = [SFTheme card];
    field.layer.cornerRadius = 14;
    field.layer.cornerCurve = kCACornerCurveContinuous;
    field.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 16, 10)];
    field.leftViewMode = UITextFieldViewModeAlways;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    [field.heightAnchor constraintEqualToConstant:54].active = YES;
    return field;
}

static void SFPickTeam(UIViewController *presenter, NSArray *teams, void (^picked)(NSString *teamID)) {
    if (teams.count <= 1) { picked([teams.firstObject objectForKey:@"teamId"]); return; }
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:SFL(@"Choose a team") message:SFL(@"This Apple ID belongs to more than one team.") preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSDictionary *team in teams) {
        NSString *title = [NSString stringWithFormat:@"%@ (%@)", team[@"name"] ?: SFL(@"Team"), team[@"teamId"] ?: @""];
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            picked(team[@"teamId"]);
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:SFL(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = presenter.view;
    [presenter presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - Sign in

@interface SFSignInViewController () <UITextFieldDelegate>
@property (nonatomic, weak) UITextField *activeField;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UITextField *emailField;
@property (nonatomic, strong) UITextField *passwordField;
@property (nonatomic, strong) UIButton *continueButton;
@property (nonatomic, strong) UILabel *errorLabel;
@property (nonatomic) BOOL busy;
@end

@implementation SFSignInViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [SFTheme background];
    self.navigationItem.backButtonTitle = SFL(@"Back");

    // Reachable while signed out, so a wrong language or a down Anisette server can't trap the user here.
    UIImage *globe = [[UIImage systemImageNamed:@"globe"] imageWithTintColor:[UIColor systemBlueColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
    UIImage *gear = [[UIImage systemImageNamed:@"gearshape"] imageWithTintColor:[SFTheme accent] renderingMode:UIImageRenderingModeAlwaysOriginal];
    UIBarButtonItem *languageItem = [[UIBarButtonItem alloc] initWithImage:globe style:UIBarButtonItemStylePlain target:self action:@selector(openLanguage)];
    languageItem.accessibilityLabel = SFL(@"Language");
    UIBarButtonItem *serverItem = [[UIBarButtonItem alloc] initWithImage:gear style:UIBarButtonItemStylePlain target:self action:@selector(openAnisetteServers)];
    serverItem.accessibilityLabel = SFL(@"Anisette servers");
    // rightBarButtonItems[0] is the rightmost icon: gear on the right, globe just left of it.
    self.navigationItem.rightBarButtonItems = @[serverItem, languageItem];

    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    scroll.alwaysBounceVertical = YES;
    [self.view addSubview:scroll];
    self.scrollView = scroll;

    UIImageView *logo = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"SevenfoldLogo"]];
    logo.translatesAutoresizingMaskIntoConstraints = NO;
    logo.contentMode = UIViewContentModeScaleAspectFit;
    logo.layer.cornerRadius = 22;
    logo.layer.cornerCurve = kCACornerCurveContinuous;
    logo.clipsToBounds = YES;

    UILabel *by = [SFTheme labelWithSize:12 weight:UIFontWeightBold color:[SFTheme secondaryText]];
    by.text = @"BY: T4MAG0";
    by.textAlignment = NSTextAlignmentCenter;
    NSMutableAttributedString *byText = [[NSMutableAttributedString alloc] initWithString:@"BY: T4MAG0"];
    [byText addAttribute:NSKernAttributeName value:@2 range:NSMakeRange(0, byText.length)];
    by.attributedText = byText;

    UILabel *title = [SFTheme labelWithSize:28 weight:UIFontWeightBold color:[UIColor labelColor]];
    title.text = SFL(@"Sign in to Sevenfold");
    title.textAlignment = NSTextAlignmentCenter;
    UILabel *subtitle = [SFTheme labelWithSize:15 weight:UIFontWeightRegular color:[SFTheme secondaryText]];
    subtitle.text = SFL(@"Your Apple ID is only used to get signing certificates from Apple. A separate Apple ID just for sideloading is safest.");
    subtitle.textAlignment = NSTextAlignmentCenter;

    self.emailField = SFField(SFL(@"Apple ID"));
    self.emailField.keyboardType = UIKeyboardTypeEmailAddress;
    self.emailField.textContentType = UITextContentTypeUsername;
    self.emailField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.emailField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.emailField.returnKeyType = UIReturnKeyNext;
    self.emailField.delegate = self;
    self.emailField.text = [SFSettings appleIDEmail];
    self.passwordField = SFField(SFL(@"Password"));
    self.passwordField.secureTextEntry = YES;
    self.passwordField.textContentType = UITextContentTypePassword;
    self.passwordField.returnKeyType = UIReturnKeyGo;
    self.passwordField.delegate = self;
    [self.emailField addTarget:self action:@selector(textChanged) forControlEvents:UIControlEventEditingChanged];
    [self.passwordField addTarget:self action:@selector(textChanged) forControlEvents:UIControlEventEditingChanged];

    self.errorLabel = [SFTheme labelWithSize:14 weight:UIFontWeightMedium color:[SFTheme danger]];
    self.errorLabel.textAlignment = NSTextAlignmentCenter;
    self.errorLabel.hidden = YES;

    self.continueButton = [SFTheme primaryButtonWithTitle:SFL(@"Continue")];
    [self.continueButton addTarget:self action:@selector(signIn) forControlEvents:UIControlEventTouchUpInside];

    UIButton *networkLink = [UIButton buttonWithType:UIButtonTypeSystem];
    [networkLink setTitle:SFL(@"Can't connect? Allow network access") forState:UIControlStateNormal];
    networkLink.titleLabel.font = [SFTheme fontOfSize:14 weight:UIFontWeightMedium];
    networkLink.tintColor = [SFTheme accent];
    [networkLink addTarget:self action:@selector(allowNetwork) forControlEvents:UIControlEventTouchUpInside];

    UILabel *note = [SFTheme labelWithSize:13 weight:UIFontWeightRegular color:[SFTheme secondaryText]];
    note.text = SFL(@"Stored only in this iPhone's keychain. Sign-in uses the anisette servers in Settings, and switches automatically if one is down.");
    note.textAlignment = NSTextAlignmentCenter;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[logo, by, title, subtitle, self.emailField, self.passwordField, self.errorLabel, self.continueButton, networkLink, note]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    [stack setCustomSpacing:8 afterView:logo];
    [stack setCustomSpacing:22 afterView:by];
    [stack setCustomSpacing:8 afterView:title];
    [stack setCustomSpacing:26 afterView:subtitle];
    [stack setCustomSpacing:6 afterView:self.continueButton];
    [stack setCustomSpacing:10 afterView:networkLink];
    stack.alignment = UIStackViewAlignmentFill;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];

    UILayoutGuide *content = scroll.contentLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:content.topAnchor constant:40],
        [stack.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-24],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.leadingAnchor constant:24],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.trailingAnchor constant:-24],
        [logo.heightAnchor constraintEqualToConstant:96],
    ]];
    [self textChanged];
}

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    self.activeField = textField;
    [self revealTypingArea];
}

// Keep the field being typed in, and the Continue button, above the keyboard.
- (void)revealTypingArea {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self.view layoutIfNeeded];
        UIView *field = self.activeField ?: self.emailField;
        CGRect fieldRect = [self.scrollView convertRect:field.bounds fromView:field];
        CGRect buttonRect = [self.scrollView convertRect:self.continueButton.bounds fromView:self.continueButton];
        // Keep the field being typed in on screen. Show it through to the Continue button when
        // that fits; otherwise keep the active field visible with a little room beneath it
        // (so focusing Apple ID no longer jumps past it to the button).
        CGRect wanted = CGRectUnion(fieldRect, buttonRect);
        if (wanted.size.height > self.scrollView.bounds.size.height - 24) {
            wanted = fieldRect;
            wanted.size.height += 72;
        }
        [self.scrollView scrollRectToVisible:CGRectInset(wanted, 0, -12) animated:YES];
    });
}

- (void)openLanguage {
    [self presentPanel:[SFLanguageViewController new]];
}

- (void)openAnisetteServers {
    [self presentPanel:[SFServersViewController new]];
}

// Present over the login page (not pushed): the login page stays mounted underneath and
// reliably reappears when the panel is closed. Pushing instead collapsed the sign-in view
// on the way back (its scroll view tracks the keyboard layout guide).
- (void)presentPanel:(UIViewController *)controller {
    controller.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(dismissPanel)];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:controller];
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)dismissPanel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == self.emailField) [self.passwordField becomeFirstResponder];
    else [self signIn];
    return YES;
}

- (void)textChanged {
    self.continueButton.enabled = !self.busy && self.emailField.text.length > 3 && self.passwordField.text.length > 0;
}

- (void)setBusy:(BOOL)busy {
    _busy = busy;
    UIButtonConfiguration *config = self.continueButton.configuration;
    config.showsActivityIndicator = busy;
    config.title = busy ? SFL(@"Signing in…") : SFL(@"Continue");
    self.continueButton.configuration = config;
    self.emailField.enabled = !busy;
    self.passwordField.enabled = !busy;
    [self textChanged];
}

- (void)showError:(NSString *)message {
    self.errorLabel.text = message;
    self.errorLabel.hidden = message.length == 0;
}

- (void)allowNetwork {
    BOOL ok = [SFNetworkAccess allowWiFiAndCellular];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:ok ? SFL(@"Network access allowed") : SFL(@"Not changed")
        message:ok ? SFL(@"Sevenfold is set to WLAN & Cellular Data. Try signing in again.") : SFL(@"Couldn't change it automatically. Open Settings › Cellular on your iPhone and allow Sevenfold, then try again.")
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SFL(@"OK") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)signIn {
    if (self.busy || !self.continueButton.enabled) return;
    [self.view endEditing:YES];
    [self showError:nil];
    self.busy = YES;
    NSString *email = [self.emailField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    SFLogEvent(SFLogLevelInfo, @"sign-in started");
    [[SFAccountChecker sharedInstance] checkUsername:email withPassword:self.passwordField.text andCompletionHandler:^(NSString *failureReason, NSString *resultCode, NSArray *teams, NSURLCredential *credential) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.busy = NO;
            if (teams.count > 0 && credential) {
                [self continueWithEmail:email teams:teams credential:credential];
            } else if ([resultCode isEqualToString:@"appSpecificRequired"]) {
                SFTwoFactorViewController *twoFactor = [SFTwoFactorViewController new];
                twoFactor.email = email;
                twoFactor.onFinish = self.onFinish;
                [self.navigationController pushViewController:twoFactor animated:YES];
            } else {
                SFLogEvent(SFLogLevelError, @"sign-in failed · %@", failureReason ?: @"unknown");
                NSString *lower = failureReason.lowercaseString ?: @"";
                BOOL connection = [lower containsString:@"internet"] || [lower containsString:@"offline"] || [lower containsString:@"network"] ||
                                  [lower containsString:@"timed out"] || [lower containsString:@"could not connect"] || [lower containsString:@"anisette"];
                if (connection && [SFNetworkAccess allowWiFiAndCellular]) {
                    [self showError:SFL(@"Sevenfold couldn't connect, so it just allowed itself WLAN & cellular data. Tap Continue to try again.")];
                } else {
                    [self showError:failureReason.length > 0 ? failureReason : SFL(@"Sign-in failed. Check your Apple ID and password.")];
                }
                self.passwordField.text = @"";
                [self textChanged];
            }
        });
    }];
}

- (void)continueWithEmail:(NSString *)email teams:(NSArray *)teams credential:(NSURLCredential *)credential {
    SFPickTeam(self, teams, ^(NSString *teamID) {
        SFAccountSetupViewController *setup = [[SFAccountSetupViewController alloc] initWithEmail:email identity:credential.user token:credential.password teamID:teamID];
        setup.onFinish = self.onFinish;
        [self.navigationController pushViewController:setup animated:YES];
    });
}

@end

#pragma mark - Two-factor

@interface SFTwoFactorViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UITextField *codeField;
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, strong) UIButton *verifyButton;
@property (nonatomic, strong) UIButton *resendButton;
@property (nonatomic) BOOL busy;
@property (nonatomic) BOOL requested;
@end

@implementation SFTwoFactorViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [SFTheme background];
    self.title = SFL(@"Verification");

    UIImageView *glyph = [[UIImageView alloc] initWithImage:[SFTheme symbol:@"lock.shield.fill" size:44 weight:UIImageSymbolWeightSemibold]];
    glyph.tintColor = [SFTheme accent];
    glyph.contentMode = UIViewContentModeCenter;
    UILabel *title = [SFTheme labelWithSize:26 weight:UIFontWeightBold color:[UIColor labelColor]];
    title.text = SFL(@"Enter the code");
    title.textAlignment = NSTextAlignmentCenter;
    self.messageLabel = [SFTheme labelWithSize:15 weight:UIFontWeightRegular color:[SFTheme secondaryText]];
    self.messageLabel.text = SFL(@"Apple is sending a six-digit code to your trusted devices.");
    self.messageLabel.textAlignment = NSTextAlignmentCenter;

    self.codeField = SFField(@"••••••");
    self.codeField.textAlignment = NSTextAlignmentCenter;
    self.codeField.font = [UIFont monospacedDigitSystemFontOfSize:28 weight:UIFontWeightSemibold];
    self.codeField.keyboardType = UIKeyboardTypeNumberPad;
    self.codeField.textContentType = UITextContentTypeOneTimeCode;
    self.codeField.leftView = nil;
    self.codeField.clearButtonMode = UITextFieldViewModeNever;
    [self.codeField addTarget:self action:@selector(codeChanged) forControlEvents:UIControlEventEditingChanged];

    self.verifyButton = [SFTheme primaryButtonWithTitle:SFL(@"Verify")];
    [self.verifyButton addTarget:self action:@selector(verify) forControlEvents:UIControlEventTouchUpInside];
    self.resendButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.resendButton setTitle:SFL(@"Send a new code") forState:UIControlStateNormal];
    self.resendButton.tintColor = [SFTheme accent];
    [self.resendButton addTarget:self action:@selector(requestCode) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[glyph, title, self.messageLabel, self.codeField, self.verifyButton, self.resendButton]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 14;
    [stack setCustomSpacing:24 afterView:self.messageLabel];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:28],
        [stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24],
        [stack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24],
        [glyph.heightAnchor constraintEqualToConstant:60],
    ]];
    [self codeChanged];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.requested) [self requestCode];
}

- (void)setBusy:(BOOL)busy {
    _busy = busy;
    UIButtonConfiguration *config = self.verifyButton.configuration;
    config.showsActivityIndicator = busy;
    self.verifyButton.configuration = config;
    self.resendButton.enabled = !busy;
    [self codeChanged];
}

- (void)codeChanged {
    NSString *digits = [[self.codeField.text componentsSeparatedByCharactersInSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]] componentsJoinedByString:@""];
    if (digits.length > 6) digits = [digits substringToIndex:6];
    if (![digits isEqualToString:self.codeField.text ?: @""]) self.codeField.text = digits;
    self.verifyButton.enabled = !self.busy && digits.length == 6;
    if (digits.length == 6 && !self.busy && self.requested) [self verify];
}

- (void)requestCode {
    if (self.busy) return;
    if (![[SFAccountChecker sharedInstance] hasActiveTwoFactorSession]) {
        self.messageLabel.text = SFL(@"This verification session ended. Go back and sign in again.");
        self.messageLabel.textColor = [SFTheme danger];
        return;
    }
    self.busy = YES;
    self.codeField.text = @"";
    [[SFAccountChecker sharedInstance] requestLoginCodeWithCompletionHandler:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.busy = NO;
            self.requested = error == nil;
            if (error) {
                self.messageLabel.text = error.localizedDescription.length > 0 ? error.localizedDescription : SFL(@"Couldn't request a code. Try again.");
                self.messageLabel.textColor = [SFTheme danger];
                return;
            }
            self.messageLabel.text = SFL(@"Enter the newest six-digit code Apple sent. Requesting another code makes older codes stop working.");
            self.messageLabel.textColor = [SFTheme secondaryText];
            [self.codeField becomeFirstResponder];
        });
    }];
}

- (void)verify {
    if (self.busy || self.codeField.text.length != 6) return;
    self.busy = YES;
    [[SFAccountChecker sharedInstance] validateLoginCode:self.codeField.text withCompletionHandler:^(NSString *failureReason, NSString *resultCode, NSArray *teams, NSURLCredential *credential) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.busy = NO;
            if (teams.count > 0 && credential) {
                SFPickTeam(self, teams, ^(NSString *teamID) {
                    SFAccountSetupViewController *setup = [[SFAccountSetupViewController alloc] initWithEmail:self.email identity:credential.user token:credential.password teamID:teamID];
                    setup.onFinish = self.onFinish;
                    [self.navigationController pushViewController:setup animated:YES];
                });
                return;
            }
            self.codeField.text = @"";
            self.messageLabel.text = failureReason.length > 0 ? failureReason : SFL(@"Apple didn't accept that code. Send a new code and try again.");
            self.messageLabel.textColor = [SFTheme danger];
        });
    }];
}

@end

#pragma mark - Account setup

@interface SFAccountSetupViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *email;
@property (nonatomic, copy) NSString *identity;
@property (nonatomic, copy) NSString *token;
@property (nonatomic, copy) NSString *teamID;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UITableView *certificateTable;
@property (nonatomic, strong) NSMutableArray *certificates;
@property (nonatomic, strong) UIButton *doneButton;
@end

@implementation SFAccountSetupViewController

- (instancetype)initWithEmail:(NSString *)email identity:(NSString *)identity token:(NSString *)token teamID:(NSString *)teamID {
    self = [super init];
    if (self) {
        _email = email; _identity = identity; _token = token; _teamID = teamID;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [SFTheme background];
    self.navigationItem.hidesBackButton = YES;

    self.titleLabel = [SFTheme labelWithSize:26 weight:UIFontWeightBold color:[UIColor labelColor]];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.detailLabel = [SFTheme labelWithSize:15 weight:UIFontWeightRegular color:[SFTheme secondaryText]];
    self.detailLabel.textAlignment = NSTextAlignmentCenter;
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.spinner.color = [SFTheme accent];
    [self.spinner startAnimating];

    self.certificateTable = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.certificateTable.translatesAutoresizingMaskIntoConstraints = NO;
    self.certificateTable.dataSource = self;
    self.certificateTable.delegate = self;
    self.certificateTable.backgroundColor = [UIColor clearColor];
    self.certificateTable.hidden = YES;

    self.doneButton = [SFTheme primaryButtonWithTitle:SFL(@"Start using Sevenfold")];
    self.doneButton.hidden = YES;
    [self.doneButton addTarget:self action:@selector(finish) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[self.spinner, self.titleLabel, self.detailLabel]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    [self.view addSubview:self.certificateTable];
    [self.view addSubview:self.doneButton];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:40],
        [stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24],
        [stack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24],
        [self.certificateTable.topAnchor constraintEqualToAnchor:stack.bottomAnchor constant:12],
        [self.certificateTable.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.certificateTable.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.certificateTable.bottomAnchor constraintEqualToAnchor:self.doneButton.topAnchor constant:-12],
        [self.doneButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24],
        [self.doneButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24],
        [self.doneButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-16],
    ]];
    [self checkCertificates];
}

- (void)setStep:(NSString *)title detail:(NSString *)detail {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.titleLabel.text = title;
        self.detailLabel.text = detail;
    });
}

- (void)checkCertificates {
    [self setStep:SFL(@"Checking certificates") detail:SFL(@"Free Apple IDs can have two signing certificates at once.")];
    [[SFAppleServices sharedInstance] ensureSessionWithIdentity:self.identity gsToken:self.token andCompletionHandler:^(NSError *sessionError, NSDictionary *plist) {
        [[SFAppleServices sharedInstance] listTeamsWithCompletionHandler:^(NSError *error, NSDictionary *dictionary) {
            BOOL paid = NO;
            for (NSDictionary *team in dictionary[@"teams"]) {
                if (![team[@"teamId"] isEqualToString:self.teamID]) continue;
                for (NSDictionary *membership in team[@"memberships"])
                    if ([membership[@"name"] containsString:@"Apple Developer Program"] && [membership[@"platform"] isEqualToString:@"ios"]) paid = YES;
            }
            if (paid) { [self registerDevice]; return; }
            [[SFAppleServices sharedInstance] listAllDevelopmentCertificatesForTeamID:self.teamID systemType:SFSystemTypeiOS withCompletionHandler:^(NSError *error, NSDictionary *certs) {
                NSArray *list = certs[@"data"];
                if (list.count >= 2) {
                    dispatch_async(dispatch_get_main_queue(), ^{ [self askToFreeSlot:list]; });
                } else {
                    [self registerDevice];
                }
            }];
        }];
    }];
}

- (void)askToFreeSlot:(NSArray *)certificates {
    self.certificates = [certificates mutableCopy];
    [self.spinner stopAnimating];
    self.titleLabel.text = SFL(@"Free a certificate slot");
    self.detailLabel.text = SFL(@"Both certificate slots on this Apple ID are in use. Remove one you no longer need, or tap Skip if you'll import a shared certificate from your other iPhone.");
    self.certificateTable.hidden = NO;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:SFL(@"Skip") style:UIBarButtonItemStylePlain target:self action:@selector(skipSlot)];
    [self.certificateTable reloadData];
}

- (void)skipSlot {
    self.navigationItem.rightBarButtonItem = nil;
    self.certificateTable.hidden = YES;
    [self.spinner startAnimating];
    [self registerDevice];
}

- (void)registerDevice {
    [self setStep:SFL(@"Registering this iPhone") detail:[NSString stringWithFormat:SFL(@"Adding your %@ to this Apple ID."), [SFDevice modelName]]];
    [[SFAccountChecker sharedInstance] registerCurrentDeviceForTeamID:self.teamID withIdentity:self.identity gsToken:self.token andCompletionHandler:^(NSError *error) {
        if ([SFResources hasActivePairedWatch]) {
            [[SFAccountChecker sharedInstance] registerCurrentWatchForTeamID:self.teamID withIdentity:self.identity gsToken:self.token andCompletionHandler:^(NSError *watchError) {
                [self store];
            }];
        } else {
            [self store];
        }
    }];
}

- (void)store {
    dispatch_async(dispatch_get_main_queue(), ^{
        [SFResources storeUsername:self.identity password:self.token andTeamID:self.teamID];
        [SFSettings setAppleIDEmail:self.email];
        SFLogEvent(SFLogLevelOK, @"signed in · team %@", self.teamID);
        [self.spinner stopAnimating];
        self.spinner.hidden = YES;
        self.titleLabel.text = SFL(@"You're all set");
        self.detailLabel.text = SFL(@"Sevenfold will keep your apps signed on your schedule. You can change it in Settings.");
        self.doneButton.hidden = NO;
        [[NSNotificationCenter defaultCenter] postNotificationName:@"com.t4mag0.sevenfold/userDidSignIn" object:nil];
    });
}

- (void)finish {
    if (self.onFinish) self.onFinish();
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.certificates.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.backgroundColor = [SFTheme card];
    NSDictionary *attributes = self.certificates[indexPath.row][@"attributes"];
    NSString *machine = [attributes[@"machineName"] isKindOfClass:[NSString class]] ? attributes[@"machineName"] : SFL(@"Unknown device");
    NSString *model = [SFDevice modelFromCertificateMachineName:machine];
    UIListContentConfiguration *config = [UIListContentConfiguration subtitleCellConfiguration];
    config.text = model ? [NSString stringWithFormat:SFL(@"Sevenfold · %@"), model] : machine;
    config.secondaryText = SFL(@"Swipe left to remove");
    config.secondaryTextProperties.color = [SFTheme secondaryText];
    cell.contentConfiguration = config;
    return cell;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    UIContextualAction *remove = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:SFL(@"Remove") handler:^(UIContextualAction *action, UIView *view, void (^done)(BOOL)) {
        NSDictionary *certificate = self.certificates[indexPath.row];
        [[SFAppleServices sharedInstance] revokeCertificateForIdentifier:certificate[@"id"] andTeamID:self.teamID systemType:SFSystemTypeiOS withCompletionHandler:^(NSError *error, NSDictionary *result) {
            dispatch_async(dispatch_get_main_queue(), ^{
                done(error == nil);
                if (error) return;
                [self.certificates removeObjectAtIndex:indexPath.row];
                [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
                if (self.certificates.count < 2) [self skipSlot];
            });
        }];
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[remove]];
}

@end
