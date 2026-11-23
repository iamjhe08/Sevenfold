//
//  SFRootController.m
//  Sevenfold
//

#import "SFRootController.h"
#import "SFLocalization.h"
#import "SFTheme.h"
#import "SFSettings.h"
#import "SFAppsViewController.h"
#import "SFCertificatesViewController.h"
#import "SFSettingsViewController.h"
#import "SFHistoryViewController.h"
#import "SFSigningViewController.h"
#import "SFSignInViewController.h"
#import "SFAppDetailViewController.h"
#import "SFShareCertificateViewController.h"
#import "SFIpaBundleApplication.h"
#import "SFWelcomeViewController.h"

@interface SFRootController ()
@property (nonatomic) BOOL signInShowing;
@property (nonatomic, strong) UIView *sidebar;
@property (nonatomic, strong) NSArray<UIButton *> *sidebarButtons;
@property (nonatomic) BOOL sidebarShown;
@end

static const CGFloat SFSidebarWidth = 280;

@implementation SFRootController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [SFTheme background];

    UINavigationController *apps = [self navWithRoot:[SFAppsViewController new] title:SFL(@"Apps") symbol:@"square.grid.2x2.fill"];
    UINavigationController *certs = [self navWithRoot:[SFCertificatesViewController new] title:SFL(@"Certificates") symbol:@"checkmark.seal.fill"];
    UINavigationController *history = [self navWithRoot:[SFHistoryViewController new] title:SFL(@"History") symbol:@"clock.arrow.circlepath"];
    UINavigationController *settings = [self navWithRoot:[SFSettingsViewController new] title:SFL(@"Settings") symbol:@"gearshape.fill"];
    self.viewControllers = @[apps, certs, history, settings];
    [self buildSidebar];

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(signInRequested) name:@"com.t4mag0.sevenfold.show-sign-in" object:nil];
    [center addObserver:self selector:@selector(openApps) name:@"com.t4mag0.sevenfold/openApps" object:nil];
}

- (UINavigationController *)navWithRoot:(UIViewController *)root title:(NSString *)title symbol:(NSString *)symbol {
    root.title = title;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:root];
    nav.navigationBar.prefersLargeTitles = YES;
    nav.tabBarItem = [[UITabBarItem alloc] initWithTitle:title image:[UIImage systemImageNamed:symbol] tag:0];
    return nav;
}

#pragma mark - iPad sidebar

/// iPad at full or wide width: a sidebar on the left replaces the tab bar.
- (BOOL)wantsSidebar {
    return UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad
        && self.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassRegular
        && self.view.bounds.size.width >= 900;
}

- (void)buildSidebar {
    UIView *bar = [UIView new];
    bar.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
        return t.userInterfaceStyle == UIUserInterfaceStyleDark ? [UIColor colorWithRed:0.07 green:0.08 blue:0.10 alpha:1] : [UIColor secondarySystemBackgroundColor];
    }];
    bar.hidden = YES;
    UIView *line = [UIView new];
    line.backgroundColor = [SFTheme separator];
    line.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:line];

    UILabel *title = [SFTheme labelWithSize:28 weight:UIFontWeightHeavy color:[UIColor labelColor]];
    title.text = @"Sevenfold";
    NSMutableArray *buttons = [NSMutableArray array];
    NSMutableArray *rows = [NSMutableArray arrayWithObject:title];
    NSInteger index = 0;
    for (UINavigationController *nav in self.viewControllers) {
        UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
        config.title = nav.tabBarItem.title;
        config.image = nav.tabBarItem.image;
        config.imagePadding = 12;
        config.contentInsets = NSDirectionalEdgeInsetsMake(0, 14, 0, 14);
        config.background.cornerRadius = 12;
        UIButton *button = [UIButton buttonWithConfiguration:config primaryAction:nil];
        button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
        button.tag = index++;
        [button.heightAnchor constraintEqualToConstant:48].active = YES;
        [button addTarget:self action:@selector(sidebarTapped:) forControlEvents:UIControlEventTouchUpInside];
        [buttons addObject:button];
        [rows addObject:button];
    }
    self.sidebarButtons = buttons;
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:rows];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 6;
    [stack setCustomSpacing:18 afterView:title];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:bar.safeAreaLayoutGuide.topAnchor constant:24],
        [stack.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:14],
        [stack.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-14],
        [line.topAnchor constraintEqualToAnchor:bar.topAnchor],
        [line.bottomAnchor constraintEqualToAnchor:bar.bottomAnchor],
        [line.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor],
        [line.widthAnchor constraintEqualToConstant:1 / UIScreen.mainScreen.scale],
    ]];
    self.sidebar = bar;
    [self.view addSubview:bar];
    [self refreshSidebarSelection];
}

- (void)sidebarTapped:(UIButton *)button {
    if (self.selectedIndex == (NSUInteger)button.tag) {
        UINavigationController *nav = (UINavigationController *)self.selectedViewController;
        if ([nav isKindOfClass:[UINavigationController class]]) [nav popToRootViewControllerAnimated:YES];
    }
    self.selectedIndex = button.tag;
}

- (void)setSelectedIndex:(NSUInteger)selectedIndex {
    [super setSelectedIndex:selectedIndex];
    [self refreshSidebarSelection];
}

- (void)setSelectedViewController:(UIViewController *)selectedViewController {
    [super setSelectedViewController:selectedViewController];
    [self refreshSidebarSelection];
}

- (void)refreshSidebarSelection {
    for (UIButton *button in self.sidebarButtons) {
        BOOL on = (NSUInteger)button.tag == self.selectedIndex;
        UIButtonConfiguration *config = button.configuration;
        config.baseForegroundColor = on ? [SFTheme accent] : [UIColor labelColor];
        config.background.backgroundColor = on ? [SFTheme accentSoft] : [UIColor clearColor];
        UIFont *font = [UIFont systemFontOfSize:17 weight:on ? UIFontWeightSemibold : UIFontWeightRegular];
        config.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *attrs) {
            NSMutableDictionary *m = [attrs mutableCopy]; m[NSFontAttributeName] = font; return m;
        };
        button.configuration = config;
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    BOOL want = [self wantsSidebar];
    BOOL rtl = [SFLanguage isRightToLeft];
    CGRect bounds = self.view.bounds;
    self.sidebar.frame = CGRectMake(rtl ? bounds.size.width - SFSidebarWidth : 0, 0, SFSidebarWidth, bounds.size.height);
    [self.view bringSubviewToFront:self.sidebar];
    if (want == self.sidebarShown) return;
    self.sidebarShown = want;
    self.sidebar.hidden = !want;
    SEL hideSel = NSSelectorFromString(@"setTabBarHidden:animated:");   // iPadOS 18+ floating tab bar
    if ([self respondsToSelector:hideSel]) {
        ((void (*)(id, SEL, BOOL, BOOL))[self methodForSelector:hideSel])(self, hideSel, want, NO);
    } else {
        self.tabBar.hidden = want;
    }
    for (UIViewController *child in self.viewControllers) {
        child.additionalSafeAreaInsets = want ? UIEdgeInsetsMake(0, rtl ? 0 : SFSidebarWidth, 0, rtl ? SFSidebarWidth : 0) : UIEdgeInsetsZero;
    }
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [coordinator animateAlongsideTransition:^(id ctx) { [self.view setNeedsLayout]; [self.view layoutIfNeeded]; } completion:nil];
}

#pragma mark - Sign-in

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (![SFSettings isSignedIn]) [self presentSignIn];
}

- (UIViewController *)topPresenter {
    UIViewController *presenter = self;
    while (presenter.presentedViewController) presenter = presenter.presentedViewController;
    return presenter;
}

- (void)signInRequested {
    dispatch_async(dispatch_get_main_queue(), ^{ [self presentSignIn]; });
}

- (void)openApps {
    dispatch_async(dispatch_get_main_queue(), ^{ self.selectedIndex = 0; });
}

- (void)presentSignIn {
    if (self.signInShowing) return;
    self.signInShowing = YES;
    SFSignInViewController *signIn = [SFSignInViewController new];
    __weak SFRootController *weakSelf = self;
    signIn.onFinish = ^{ weakSelf.signInShowing = NO; [SFSettings setFirstRunDone:YES]; };
    UINavigationController *nav = nil;
    if (![SFSettings firstRunDone]) {
        // First launch: the welcome guide, then sign-in replaces it in the same sheet.
        SFWelcomeViewController *welcome = [SFWelcomeViewController new];
        nav = [[UINavigationController alloc] initWithRootViewController:welcome];
        __weak UINavigationController *weakNav = nav;
        welcome.onDone = ^{
            [SFSettings setFirstRunDone:YES];
            [weakNav setNavigationBarHidden:NO animated:NO];
            [weakNav setViewControllers:@[signIn] animated:YES];
        };
    } else {
        nav = [[UINavigationController alloc] initWithRootViewController:signIn];
    }
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    nav.modalInPresentation = YES;
    [[self topPresenter] presentViewController:nav animated:YES completion:nil];
}

- (void)showAppsList {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *presented = self.presentedViewController;
        void (^go)(void) = ^{
            self.selectedIndex = 0;
            UINavigationController *nav = (UINavigationController *)self.selectedViewController;
            if ([nav isKindOfClass:[UINavigationController class]]) [nav popToRootViewControllerAnimated:YES];
        };
        if (presented && !presented.isBeingDismissed) [self dismissViewControllerAnimated:YES completion:go];
        else go();
    });
}

- (void)presentSigningProgress {
    SFSigningViewController *signing = [SFSigningViewController new];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:signing];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    UISheetPresentationController *sheet = nav.sheetPresentationController;
    sheet.detents = @[[UISheetPresentationControllerDetent largeDetent]];
    sheet.prefersGrabberVisible = YES;
    sheet.preferredCornerRadius = 28;
    [[self topPresenter] presentViewController:nav animated:YES completion:nil];
}

- (void)presentInstallForIPAURL:(NSURL *)url {
    SFIpaBundleApplication *app = [[SFIpaBundleApplication alloc] initWithIpaURL:url];
    if (!app.bundleIdentifier) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:SFL(@"Can't open this file")
                                                                       message:SFL(@"That doesn't look like a valid .ipa app file.")
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:SFL(@"OK") style:UIAlertActionStyleCancel handler:nil]];
        [[self topPresenter] presentViewController:alert animated:YES completion:nil];
        return;
    }
    SFAppDetailViewController *detail = [[SFAppDetailViewController alloc] initWithApplication:app installMode:YES];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:detail];
    nav.sheetPresentationController.prefersGrabberVisible = YES;
    [[self topPresenter] presentViewController:nav animated:YES completion:nil];
}

- (void)presentCertificateImportForURL:(NSURL *)url {
    SFShareCertificateViewController *share = [SFShareCertificateViewController new];
    share.pendingImportURL = url;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:share];
    [[self topPresenter] presentViewController:nav animated:YES completion:nil];
}

@end
