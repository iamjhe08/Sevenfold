//
//  SFWelcomeViewController.m
//  Sevenfold
//
//  BY: T4MAG0
//

#import "SFWelcomeViewController.h"
#import "SFLocalization.h"
#import "SFTheme.h"

@interface SFWelcomeViewController () <UIScrollViewDelegate>
@property (nonatomic, strong) UIScrollView *pager;
@property (nonatomic, strong) NSArray<UIView *> *dots;
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *dotWidths;
@property (nonatomic, strong) UIButton *mainButton;
@property (nonatomic, strong) UIButton *skipButton;
@property (nonatomic) NSInteger page;
@end

static const NSInteger SFWelcomePages = 3;

@implementation SFWelcomeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [SFTheme background];
    self.navigationController.navigationBarHidden = YES;

    self.pager = [UIScrollView new];
    self.pager.pagingEnabled = YES;
    self.pager.showsHorizontalScrollIndicator = NO;
    self.pager.delegate = self;
    self.pager.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.pager];

    UIStackView *pages = [[UIStackView alloc] initWithArrangedSubviews:@[[self welcomePage], [self limitsPage], [self schedulePage]]];
    pages.axis = UILayoutConstraintAxisHorizontal;
    pages.distribution = UIStackViewDistributionFillEqually;
    pages.translatesAutoresizingMaskIntoConstraints = NO;
    [self.pager addSubview:pages];

    self.skipButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.skipButton setTitle:SFL(@"Skip") forState:UIControlStateNormal];
    self.skipButton.titleLabel.font = [UIFont systemFontOfSize:17];
    [self.skipButton setTitleColor:[SFTheme secondaryText] forState:UIControlStateNormal];
    [self.skipButton addTarget:self action:@selector(finish) forControlEvents:UIControlEventTouchUpInside];
    self.skipButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.skipButton];

    NSMutableArray *dots = [NSMutableArray array];
    NSMutableArray *widths = [NSMutableArray array];
    for (NSInteger i = 0; i < SFWelcomePages; i++) {
        UIView *dot = [UIView new];
        dot.layer.cornerRadius = 4;
        [dot.heightAnchor constraintEqualToConstant:8].active = YES;
        NSLayoutConstraint *w = [dot.widthAnchor constraintEqualToConstant:8];
        w.active = YES;
        [dots addObject:dot];
        [widths addObject:w];
    }
    self.dots = dots;
    self.dotWidths = widths;
    UIStackView *dotRow = [[UIStackView alloc] initWithArrangedSubviews:dots];
    dotRow.spacing = 8;
    dotRow.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:dotRow];

    self.mainButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.mainButton.backgroundColor = [SFTheme amber];
    self.mainButton.layer.cornerRadius = 16;
    self.mainButton.layer.cornerCurve = kCACornerCurveContinuous;
    self.mainButton.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    [self.mainButton setTitleColor:[UIColor colorWithWhite:0.07 alpha:1] forState:UIControlStateNormal];
    [self.mainButton addTarget:self action:@selector(next) forControlEvents:UIControlEventTouchUpInside];
    self.mainButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.mainButton];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    UILayoutGuide *column = self.view.readableContentGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.skipButton.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
        [self.skipButton.trailingAnchor constraintEqualToAnchor:column.trailingAnchor],
        [self.skipButton.heightAnchor constraintEqualToConstant:44],

        [self.pager.topAnchor constraintEqualToAnchor:self.skipButton.bottomAnchor],
        [self.pager.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.pager.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.pager.bottomAnchor constraintEqualToAnchor:dotRow.topAnchor constant:-20],

        [pages.topAnchor constraintEqualToAnchor:self.pager.contentLayoutGuide.topAnchor],
        [pages.bottomAnchor constraintEqualToAnchor:self.pager.contentLayoutGuide.bottomAnchor],
        [pages.leadingAnchor constraintEqualToAnchor:self.pager.contentLayoutGuide.leadingAnchor],
        [pages.trailingAnchor constraintEqualToAnchor:self.pager.contentLayoutGuide.trailingAnchor],
        [pages.heightAnchor constraintEqualToAnchor:self.pager.frameLayoutGuide.heightAnchor],
        [pages.widthAnchor constraintEqualToAnchor:self.pager.frameLayoutGuide.widthAnchor multiplier:SFWelcomePages],

        [dotRow.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [dotRow.bottomAnchor constraintEqualToAnchor:self.mainButton.topAnchor constant:-22],

        [self.mainButton.leadingAnchor constraintEqualToAnchor:column.leadingAnchor constant:8],
        [self.mainButton.trailingAnchor constraintEqualToAnchor:column.trailingAnchor constant:-8],
        [self.mainButton.heightAnchor constraintEqualToConstant:56],
        [self.mainButton.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-16],
    ]];
    [self updateForPage:0];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:animated];
}

#pragma mark - Pages

- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color {
    UILabel *label = [SFTheme labelWithSize:size weight:weight color:color];
    label.text = text;
    label.numberOfLines = 0;
    return label;
}

- (UIView *)iconTile:(NSString *)symbol size:(CGFloat)size {
    UIView *tile = [UIView new];
    tile.backgroundColor = [SFTheme midnight];
    tile.layer.cornerRadius = size * 0.24;
    tile.layer.cornerCurve = kCACornerCurveContinuous;
    UIImageView *image = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:size * 0.45 weight:UIImageSymbolWeightSemibold]]];
    image.tintColor = [SFTheme amber];
    image.translatesAutoresizingMaskIntoConstraints = NO;
    [tile addSubview:image];
    [NSLayoutConstraint activateConstraints:@[
        [tile.widthAnchor constraintEqualToConstant:size],
        [tile.heightAnchor constraintEqualToConstant:size],
        [image.centerXAnchor constraintEqualToAnchor:tile.centerXAnchor],
        [image.centerYAnchor constraintEqualToAnchor:tile.centerYAnchor],
    ]];
    return tile;
}

/// Wraps a vertical stack in a page that centres it in the readable column.
- (UIView *)pageWithStack:(UIStackView *)stack {
    UIView *page = [UIView new];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [page addSubview:stack];
    UILayoutGuide *column = page.readableContentGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:column.leadingAnchor constant:8],
        [stack.trailingAnchor constraintEqualToAnchor:column.trailingAnchor constant:-8],
        [stack.centerYAnchor constraintEqualToAnchor:page.centerYAnchor],
        [stack.topAnchor constraintGreaterThanOrEqualToAnchor:page.topAnchor],
    ]];
    return page;
}

- (UIView *)welcomePage {
    // The Sevenfold logo, same image as the sign-in screen.
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"SevenfoldLogo"]];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    [icon.widthAnchor constraintEqualToConstant:112].active = YES;
    [icon.heightAnchor constraintEqualToConstant:112].active = YES;
    icon.layer.shadowColor = [SFTheme amber].CGColor;
    icon.layer.shadowOpacity = 0.3;
    icon.layer.shadowRadius = 30;
    icon.layer.shadowOffset = CGSizeZero;
    UILabel *title = [self label:SFL(@"Welcome to Sevenfold") size:30 weight:UIFontWeightHeavy color:[UIColor labelColor]];
    UILabel *body = [self label:SFL(@"Your sideloaded apps, signed with your own Apple ID and signed again before they expire.") size:17 weight:UIFontWeightRegular color:[SFTheme secondaryText]];
    title.textAlignment = NSTextAlignmentCenter;
    body.textAlignment = NSTextAlignmentCenter;
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[icon, title, body]];
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 22;
    return [self pageWithStack:stack];
}

- (UIView *)limitRow:(NSString *)value text:(NSString *)text {
    UIView *row = [UIView new];
    row.backgroundColor = [SFTheme card];
    row.layer.cornerRadius = 16;
    row.layer.cornerCurve = kCACornerCurveContinuous;
    UILabel *big = [self label:value size:22 weight:UIFontWeightHeavy color:[SFTheme amberLight]];
    big.numberOfLines = 1;
    big.adjustsFontSizeToFitWidth = YES;
    big.minimumScaleFactor = 0.6;
    UILabel *small = [self label:text size:15 weight:UIFontWeightRegular color:[UIColor labelColor]];
    UIStackView *line = [[UIStackView alloc] initWithArrangedSubviews:@[big, small]];
    line.spacing = 14;
    line.alignment = UIStackViewAlignmentCenter;
    line.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:line];
    [NSLayoutConstraint activateConstraints:@[
        [big.widthAnchor constraintEqualToConstant:88],
        [line.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:16],
        [line.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-16],
        [line.topAnchor constraintEqualToAnchor:row.topAnchor constant:16],
        [line.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-16],
    ]];
    return row;
}

- (UIView *)limitsPage {
    UILabel *title = [self label:SFL(@"Free Apple ID limits") size:30 weight:UIFontWeightHeavy color:[UIColor labelColor]];
    UILabel *body = [self label:SFL(@"Apple sets these for free accounts. Sevenfold works within them.") size:17 weight:UIFontWeightRegular color:[SFTheme secondaryText]];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        title, body,
        [self limitRow:SFL(@"7 days") text:SFL(@"Each signed app works for a week, then needs signing again.")],
        [self limitRow:SFL(@"3 apps") text:SFL(@"Up to 3 sideloaded apps can be active at once.")],
        [self limitRow:SFL(@"10 IDs") text:SFL(@"Each app and extension uses an App ID. They free up after 7 days.")],
    ]];
    stack.spacing = 12;
    [stack setCustomSpacing:16 afterView:title];
    [stack setCustomSpacing:22 afterView:body];
    return [self pageWithStack:stack];
}

- (UIView *)schedulePage {
    UIView *icon = [self iconTile:@"clock" size:72];
    UIStackView *iconRow = [[UIStackView alloc] initWithArrangedSubviews:@[icon, [UIView new]]];
    UILabel *title = [self label:SFL(@"Signs on its own") size:30 weight:UIFontWeightHeavy color:[UIColor labelColor]];
    UILabel *body = [self label:SFL(@"Pick the times in Settings › Schedule. Sevenfold wakes and signs at those times, even while your iPhone is locked.") size:17 weight:UIFontWeightRegular color:[SFTheme secondaryText]];
    UIView *tip = [UIView new];
    tip.backgroundColor = [SFTheme card];
    tip.layer.cornerRadius = 16;
    tip.layer.cornerCurve = kCACornerCurveContinuous;
    UILabel *tipText = [self label:SFL(@"Use a separate Apple ID for sideloading. It's only used to get signing certificates from Apple.") size:15 weight:UIFontWeightRegular color:[UIColor labelColor]];
    tipText.translatesAutoresizingMaskIntoConstraints = NO;
    [tip addSubview:tipText];
    [NSLayoutConstraint activateConstraints:@[
        [tipText.leadingAnchor constraintEqualToAnchor:tip.leadingAnchor constant:16],
        [tipText.trailingAnchor constraintEqualToAnchor:tip.trailingAnchor constant:-16],
        [tipText.topAnchor constraintEqualToAnchor:tip.topAnchor constant:16],
        [tipText.bottomAnchor constraintEqualToAnchor:tip.bottomAnchor constant:-16],
    ]];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[iconRow, title, body, tip]];
    stack.spacing = 22;
    return [self pageWithStack:stack];
}

#pragma mark - Paging

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    CGFloat width = scrollView.bounds.size.width;
    if (width <= 0) return;
    NSInteger page = (NSInteger)lround(scrollView.contentOffset.x / width);
    if ([SFLanguage isRightToLeft]) page = SFWelcomePages - 1 - page;
    page = MAX(0, MIN(SFWelcomePages - 1, page));
    if (page != self.page) [self updateForPage:page];
}

- (void)updateForPage:(NSInteger)page {
    self.page = page;
    BOOL last = page == SFWelcomePages - 1;
    NSString *title = !last ? SFL(@"Continue") : (self.reopened ? SFL(@"Done") : SFL(@"Sign in with Apple ID"));
    [UIView performWithoutAnimation:^{
        [self.mainButton setTitle:title forState:UIControlStateNormal];
        [self.mainButton layoutIfNeeded];
    }];
    self.skipButton.hidden = last;
    [UIView animateWithDuration:0.2 animations:^{
        for (NSInteger i = 0; i < SFWelcomePages; i++) {
            self.dots[i].backgroundColor = i == page ? [SFTheme amber] : [UIColor colorWithWhite:0.5 alpha:0.35];
            self.dotWidths[i].constant = i == page ? 22 : 8;
        }
        [self.view layoutIfNeeded];
    }];
}

- (void)next {
    if (self.page >= SFWelcomePages - 1) { [self finish]; return; }
    NSInteger target = self.page + 1;
    NSInteger visual = [SFLanguage isRightToLeft] ? SFWelcomePages - 1 - target : target;
    [self.pager setContentOffset:CGPointMake(visual * self.pager.bounds.size.width, 0) animated:YES];
    [self updateForPage:target];
}

- (void)finish {
    if (self.onDone) self.onDone();
}

@end
