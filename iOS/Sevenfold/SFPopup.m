//
//  SFPopup.m
//  Sevenfold
//

#import "SFPopup.h"
#import "SFLocalization.h"
#import "SFTheme.h"

static UIColor *SFHex(uint32_t rgb, CGFloat alpha) {
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0 blue:(rgb & 0xFF) / 255.0 alpha:alpha];
}

// MARK: - Pieces

/// Only the pop-up takes touches; everything else passes through to the app.
@interface SFPopupWindow : UIWindow
@property (nonatomic, weak) UIView *popupView;
@end

@implementation SFPopupWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return (self.popupView && [hit isDescendantOfView:self.popupView]) ? hit : nil;
}
@end

/// Thin line that empties over the pop-up's lifetime.
@interface SFCountdownBar : UIView
@property (nonatomic, strong) CAGradientLayer *gradient;
@property (nonatomic, strong) CAShapeLayer *fill;
@property (nonatomic, strong) CAShapeLayer *track;
@end

@implementation SFCountdownBar
- (instancetype)initWithColor:(UIColor *)color light:(UIColor *)light {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _track = [CAShapeLayer layer];
        _track.strokeColor = [UIColor colorWithWhite:1 alpha:0.12].CGColor;
        _track.lineCap = kCALineCapRound;
        [self.layer addSublayer:_track];
        _fill = [CAShapeLayer layer];
        _fill.strokeColor = [UIColor blackColor].CGColor;
        _fill.lineCap = kCALineCapRound;
        _gradient = [CAGradientLayer layer];
        _gradient.colors = @[(id)color.CGColor, (id)light.CGColor];
        _gradient.startPoint = CGPointMake(0, 0.5);
        _gradient.endPoint = CGPointMake(1, 0.5);
        _gradient.mask = _fill;
        [self.layer addSublayer:_gradient];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat h = self.bounds.size.height, w = self.bounds.size.width;
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:CGPointMake(h / 2, h / 2)];
    [path addLineToPoint:CGPointMake(MAX(w - h / 2, h / 2), h / 2)];
    self.track.path = path.CGPath; self.track.lineWidth = h;
    self.fill.path = path.CGPath; self.fill.lineWidth = h;
    self.gradient.frame = self.bounds;
    self.fill.frame = self.bounds;
}
- (void)startWithDuration:(NSTimeInterval)duration delay:(NSTimeInterval)delay {
    CABasicAnimation *drain = [CABasicAnimation animationWithKeyPath:@"strokeEnd"];
    drain.fromValue = @1; drain.toValue = @0;
    drain.beginTime = CACurrentMediaTime() + delay;
    drain.duration = duration;
    drain.fillMode = kCAFillModeBoth;
    drain.removedOnCompletion = NO;
    [self.fill addAnimation:drain forKey:@"drain"];
}
@end

/// Ring + check mark that draw themselves.
@interface SFCheckRing : UIView
@property (nonatomic, strong) CAShapeLayer *ring;
@property (nonatomic, strong) CAShapeLayer *check;
@end

@implementation SFCheckRing
- (instancetype)initWithColor:(UIColor *)color {
    self = [super initWithFrame:CGRectMake(0, 0, 40, 40)];
    if (self) {
        self.backgroundColor = [color colorWithAlphaComponent:0.14];
        self.layer.cornerRadius = 20;
        _ring = [CAShapeLayer layer];
        _ring.path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(20, 20) radius:17 startAngle:-M_PI_2 endAngle:M_PI * 1.5 clockwise:YES].CGPath;
        _ring.strokeColor = color.CGColor; _ring.fillColor = nil; _ring.lineWidth = 3; _ring.strokeEnd = 0;
        [self.layer addSublayer:_ring];
        UIBezierPath *tick = [UIBezierPath bezierPath];
        [tick moveToPoint:CGPointMake(13, 20.5)];
        [tick addLineToPoint:CGPointMake(17.5, 25)];
        [tick addLineToPoint:CGPointMake(27, 15)];
        _check = [CAShapeLayer layer];
        _check.path = tick.CGPath;
        _check.strokeColor = color.CGColor; _check.fillColor = nil; _check.lineWidth = 3.2;
        _check.lineCap = kCALineCapRound; _check.lineJoin = kCALineJoinRound; _check.strokeEnd = 0;
        [self.layer addSublayer:_check];
    }
    return self;
}
- (CGSize)intrinsicContentSize { return CGSizeMake(40, 40); }
- (void)drawAfter:(NSTimeInterval)delay {
    for (CAShapeLayer *layer in @[self.ring, self.check]) {
        BOOL isCheck = layer == self.check;
        CABasicAnimation *draw = [CABasicAnimation animationWithKeyPath:@"strokeEnd"];
        draw.fromValue = @0; draw.toValue = @1;
        draw.beginTime = CACurrentMediaTime() + delay + (isCheck ? 0.32 : 0);
        draw.duration = isCheck ? 0.28 : 0.45;
        draw.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        draw.fillMode = kCAFillModeBoth;
        draw.removedOnCompletion = NO;
        [layer addAnimation:draw forKey:@"draw"];
    }
}
@end

// MARK: - Pop-up

@interface SFPopup ()
@property (nonatomic, strong) SFPopupWindow *window;
@property (nonatomic, strong) UIView *container;
@property (nonatomic, strong) NSTimer *hideTimer;
@property (nonatomic) BOOL island;
@property (nonatomic) CGRect hiddenFrame;
@property (nonatomic, copy) void (^retryBlock)(void);
@end

@implementation SFPopup

+ (instancetype)shared {
    static SFPopup *popup;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ popup = [SFPopup new]; });
    return popup;
}

+ (UIWindowScene *)activeScene {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive)
            return (UIWindowScene *)scene;
    }
    return nil;
}

+ (BOOL)deviceHasDynamicIsland {
    // Dynamic Island iPhones have a 59pt (or larger) top safe area in portrait; notch iPhones 44-50pt.
    UIWindow *window = [self activeScene].windows.firstObject;
    if (!window || UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPhone) return NO;
    return window.safeAreaInsets.top >= 58;
}

+ (void)showWithTitle:(NSString *)title subtitle:(NSString *)subtitle style:(SFPopupStyle)style {
    [self showWithTitle:title subtitle:subtitle style:style icon:nil retry:nil];
}

+ (void)showWithTitle:(NSString *)title subtitle:(NSString *)subtitle style:(SFPopupStyle)style icon:(UIImage *)icon retry:(void (^)(void))retry {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[self shared] showWithTitle:title subtitle:subtitle style:style icon:icon retry:retry];
    });
}

- (void)colorsForStyle:(SFPopupStyle)style main:(UIColor **)main badge:(UIColor **)badge symbol:(NSString **)symbol {
    switch (style) {
        case SFPopupStyleSuccess: *main = SFHex(0x4ADE80, 1); *badge = SFHex(0x22C55E, 1); *symbol = @"checkmark"; break;
        case SFPopupStyleFailure: *main = SFHex(0xFF6B6B, 1); *badge = SFHex(0xFF6B6B, 1); *symbol = @"xmark"; break;
        case SFPopupStyleInfo:    *main = SFHex(0xFF9A3D, 1); *badge = SFHex(0xFF9A3D, 1); *symbol = @"checkmark"; break;
    }
}

- (UIView *)iconViewWithImage:(UIImage *)image size:(CGFloat)size badgeColor:(UIColor *)badgeColor symbol:(NSString *)symbol ringColor:(UIColor *)ringColor badge:(UIView **)badgeOut {
    UIView *holder = [UIView new];
    holder.translatesAutoresizingMaskIntoConstraints = NO;
    UIImageView *imageView = [[UIImageView alloc] initWithImage:image ?: [UIImage imageNamed:@"SevenfoldLogo"]];
    imageView.contentMode = UIViewContentModeScaleAspectFill;
    imageView.clipsToBounds = YES;
    imageView.layer.cornerRadius = size * 0.27;
    imageView.layer.cornerCurve = kCACornerCurveContinuous;
    imageView.translatesAutoresizingMaskIntoConstraints = NO;
    [holder addSubview:imageView];

    UIView *badge = [UIView new];
    badge.backgroundColor = badgeColor;
    badge.layer.cornerRadius = 11;
    badge.layer.borderWidth = 3;
    badge.layer.borderColor = ringColor.CGColor;
    badge.translatesAutoresizingMaskIntoConstraints = NO;
    UIImageView *mark = [[UIImageView alloc] initWithImage:[SFTheme symbol:symbol size:9 weight:UIImageSymbolWeightBlack]];
    mark.tintColor = [UIColor blackColor];
    mark.translatesAutoresizingMaskIntoConstraints = NO;
    [badge addSubview:mark];
    [holder addSubview:badge];

    [NSLayoutConstraint activateConstraints:@[
        [holder.widthAnchor constraintEqualToConstant:size],
        [holder.heightAnchor constraintEqualToConstant:size],
        [imageView.leadingAnchor constraintEqualToAnchor:holder.leadingAnchor],
        [imageView.trailingAnchor constraintEqualToAnchor:holder.trailingAnchor],
        [imageView.topAnchor constraintEqualToAnchor:holder.topAnchor],
        [imageView.bottomAnchor constraintEqualToAnchor:holder.bottomAnchor],
        [badge.widthAnchor constraintEqualToConstant:22],
        [badge.heightAnchor constraintEqualToConstant:22],
        [badge.trailingAnchor constraintEqualToAnchor:holder.trailingAnchor constant:4],
        [badge.bottomAnchor constraintEqualToAnchor:holder.bottomAnchor constant:4],
        [mark.centerXAnchor constraintEqualToAnchor:badge.centerXAnchor],
        [mark.centerYAnchor constraintEqualToAnchor:badge.centerYAnchor],
    ]];
    badge.transform = CGAffineTransformMakeScale(0.01, 0.01);
    *badgeOut = badge;
    return holder;
}

- (void)showWithTitle:(NSString *)title subtitle:(NSString *)subtitle style:(SFPopupStyle)style icon:(UIImage *)icon retry:(void (^)(void))retry {
    UIWindowScene *scene = [SFPopup activeScene];
    if (!scene) return;
    [self dismissAnimated:NO];

    self.island = [SFPopup deviceHasDynamicIsland];
    self.retryBlock = retry;
    UIColor *main = nil, *badgeColor = nil; NSString *symbol = nil;
    [self colorsForStyle:style main:&main badge:&badgeColor symbol:&symbol];
    NSTimeInterval lifetime = style == SFPopupStyleFailure ? 7.0 : 4.0;
    UIColor *amber = SFHex(0xFF9A3D, 1);
    UIColor *gold = SFHex(0xFFD27A, 1);

    SFPopupWindow *window = [[SFPopupWindow alloc] initWithWindowScene:scene];
    window.windowLevel = UIWindowLevelStatusBar + 1;
    window.backgroundColor = [UIColor clearColor];
    window.rootViewController = [UIViewController new];
    window.rootViewController.view.backgroundColor = [UIColor clearColor];
    window.hidden = NO;
    self.window = window;

    CGFloat width = window.bounds.size.width;
    CGFloat topInset = MAX(window.safeAreaInsets.top, scene.windows.firstObject.safeAreaInsets.top);

    // Outer view carries the glow/shadow; inner view clips the content.
    UIView *container = [UIView new];
    UIView *body = [UIView new];
    body.clipsToBounds = YES;
    body.layer.cornerCurve = kCACornerCurveContinuous;
    body.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [container addSubview:body];

    UIColor *ringColor;
    if (self.island) {
        body.backgroundColor = [UIColor blackColor];
        body.layer.borderWidth = 1;
        body.layer.borderColor = [amber colorWithAlphaComponent:0.55].CGColor;
        container.layer.shadowColor = amber.CGColor;
        container.layer.shadowOpacity = 0.35;
        container.layer.shadowRadius = 22;
        container.layer.shadowOffset = CGSizeMake(0, 10);
        ringColor = [UIColor blackColor];
    } else {
        UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark]];
        blur.frame = body.bounds;
        blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [body addSubview:blur];
        body.backgroundColor = SFHex(0x1E212E, 0.55);
        body.layer.borderWidth = 1;
        body.layer.borderColor = [amber colorWithAlphaComponent:0.45].CGColor;
        container.layer.shadowColor = SFHex(0x3A1E05, 1).CGColor;
        container.layer.shadowOpacity = 0.6;
        container.layer.shadowRadius = 20;
        container.layer.shadowOffset = CGSizeMake(0, 12);
        ringColor = SFHex(0x1E212E, 1);
    }

    // Content
    UIView *badge = nil;
    UIView *iconView = [self iconViewWithImage:icon size:self.island ? 48 : 46 badgeColor:badgeColor symbol:symbol ringColor:ringColor badge:&badge];

    UILabel *titleLabel = [SFTheme labelWithSize:16 weight:UIFontWeightBold color:[UIColor whiteColor]];
    titleLabel.text = title;
    titleLabel.numberOfLines = 1;
    UILabel *subtitleLabel = [SFTheme labelWithSize:13 weight:UIFontWeightRegular color:[UIColor colorWithWhite:1 alpha:0.62]];
    subtitleLabel.text = subtitle;
    subtitleLabel.numberOfLines = 2;
    subtitleLabel.hidden = subtitle.length == 0;
    UIStackView *texts = [[UIStackView alloc] initWithArrangedSubviews:@[titleLabel, subtitleLabel]];
    texts.axis = UILayoutConstraintAxisVertical;
    texts.spacing = 2;

    NSMutableArray *rowViews = [NSMutableArray arrayWithObjects:iconView, texts, nil];
    SFCheckRing *checkRing = nil;
    if (retry) {
        UIButton *retryButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [retryButton setTitle:SFL(@"Retry") forState:UIControlStateNormal];
        retryButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
        [retryButton setTitleColor:SFHex(0x1A1205, 1) forState:UIControlStateNormal];
        retryButton.backgroundColor = [SFTheme amber];
        retryButton.layer.cornerRadius = 18;
        retryButton.contentEdgeInsets = UIEdgeInsetsMake(0, 16, 0, 16);
        [retryButton.heightAnchor constraintEqualToConstant:36].active = YES;
        [retryButton addTarget:self action:@selector(retryTapped) forControlEvents:UIControlEventTouchUpInside];
        [retryButton setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [retryButton setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [rowViews addObject:retryButton];
    } else if (self.island) {
        checkRing = [[SFCheckRing alloc] initWithColor:amber];
        [checkRing setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [rowViews addObject:checkRing];
    }
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:rowViews];
    row.spacing = 12;
    row.alignment = UIStackViewAlignmentCenter;

    SFCountdownBar *bar = [[SFCountdownBar alloc] initWithColor:amber light:gold];
    [bar.heightAnchor constraintEqualToConstant:self.island ? 4 : 3].active = YES;

    NSMutableArray *stackViews = [NSMutableArray array];
    if (!self.island) {
        // "7 SEVENFOLD · now" header, like an iOS notification
        UIImageView *logo = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"SevenfoldLogo"]];
        logo.layer.cornerRadius = 5; logo.clipsToBounds = YES;
        [logo.widthAnchor constraintEqualToConstant:18].active = YES;
        [logo.heightAnchor constraintEqualToConstant:18].active = YES;
        UILabel *app = [SFTheme labelWithSize:12 weight:UIFontWeightBold color:[UIColor colorWithWhite:1 alpha:0.6]];
        NSMutableAttributedString *name = [[NSMutableAttributedString alloc] initWithString:@"SEVENFOLD" attributes:@{ NSKernAttributeName: @0.8 }];
        app.attributedText = name;
        UILabel *now = [SFTheme labelWithSize:12 weight:UIFontWeightRegular color:[UIColor colorWithWhite:1 alpha:0.5]];
        now.text = @"now";
        [now setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:@[logo, app, now]];
        header.spacing = 8;
        header.alignment = UIStackViewAlignmentCenter;
        [stackViews addObject:header];
    }
    [stackViews addObject:row];
    UIView *barHolder = [UIView new];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    [barHolder addSubview:bar];
    CGFloat barInset = self.island ? 6 : 0;
    [NSLayoutConstraint activateConstraints:@[
        [bar.leadingAnchor constraintEqualToAnchor:barHolder.leadingAnchor constant:barInset],
        [bar.trailingAnchor constraintEqualToAnchor:barHolder.trailingAnchor constant:-barInset],
        [bar.topAnchor constraintEqualToAnchor:barHolder.topAnchor],
        [bar.bottomAnchor constraintEqualToAnchor:barHolder.bottomAnchor],
    ]];
    [stackViews addObject:barHolder];

    UIStackView *content = [[UIStackView alloc] initWithArrangedSubviews:stackViews];
    content.axis = UILayoutConstraintAxisVertical;
    content.spacing = self.island ? 12 : 10;
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [body addSubview:content];
    UIEdgeInsets pad = self.island ? UIEdgeInsetsMake(16, 14, 14, 16) : UIEdgeInsetsMake(12, 12, 12, 14);
    [NSLayoutConstraint activateConstraints:@[
        [content.leadingAnchor constraintEqualToAnchor:body.leadingAnchor constant:pad.left],
        [content.trailingAnchor constraintEqualToAnchor:body.trailingAnchor constant:-pad.right],
        [content.topAnchor constraintEqualToAnchor:body.topAnchor constant:pad.top],
    ]];

    // Size the pop-up from its content.
    CGFloat popupWidth = width - 20;
    CGSize fit = [content systemLayoutSizeFittingSize:CGSizeMake(popupWidth - pad.left - pad.right, 0)
                        withHorizontalFittingPriority:UILayoutPriorityRequired
                              verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    CGFloat height = ceil(fit.height + pad.top + pad.bottom);
    CGFloat radius = self.island ? MIN(44, height / 2) : 26;

    CGRect shown;
    if (self.island) {
        // Below the status bar, so the island (and anything drawn on it) stays visible.
        shown = CGRectMake(10, topInset + 3, popupWidth, height);
        // Starts as an island-sized pill tucked under the island.
        self.hiddenFrame = CGRectMake((width - 126) / 2, 11, 126, 37);
        container.frame = self.hiddenFrame;
        body.frame = container.bounds;
        body.layer.cornerRadius = 18.5;
        container.alpha = 0;
    } else {
        shown = CGRectMake(10, MAX(topInset, 20) + 8, popupWidth, height);
        self.hiddenFrame = CGRectOffset(shown, 0, -(CGRectGetMaxY(shown) + 20));
        container.frame = self.hiddenFrame;
        body.frame = container.bounds;
        body.layer.cornerRadius = radius;
    }
    content.alpha = self.island ? 0 : 1;

    container.accessibilityLabel = subtitle.length ? [NSString stringWithFormat:@"%@. %@", title, subtitle] : title;
    [container addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)]];
    UISwipeGestureRecognizer *swipe = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)];
    swipe.direction = UISwipeGestureRecognizerDirectionUp;
    [container addGestureRecognizer:swipe];

    [window.rootViewController.view addSubview:container];
    window.popupView = container;
    self.container = container;
    [body layoutIfNeeded];

    UINotificationFeedbackGenerator *haptic = [UINotificationFeedbackGenerator new];
    [haptic notificationOccurred:style == SFPopupStyleFailure ? UINotificationFeedbackTypeError
                               : style == SFPopupStyleSuccess ? UINotificationFeedbackTypeSuccess : UINotificationFeedbackTypeWarning];

    // Show: spring down (with a little overshoot), then the details animate in.
    if (self.island) {
        [UIView animateWithDuration:0.12 animations:^{ container.alpha = 1; }];
        [UIView animateWithDuration:0.62 delay:0.02 usingSpringWithDamping:0.68 initialSpringVelocity:0.5 options:UIViewAnimationOptionAllowUserInteraction animations:^{
            container.frame = shown;
            body.layer.cornerRadius = radius;
            [body layoutIfNeeded];
        } completion:nil];
        [UIView animateWithDuration:0.28 delay:0.22 options:0 animations:^{ content.alpha = 1; } completion:nil];
    } else {
        [UIView animateWithDuration:0.6 delay:0 usingSpringWithDamping:0.74 initialSpringVelocity:0.4 options:UIViewAnimationOptionAllowUserInteraction animations:^{
            container.frame = shown;
        } completion:nil];
    }
    [UIView animateWithDuration:0.45 delay:0.32 usingSpringWithDamping:0.5 initialSpringVelocity:0.8 options:0 animations:^{
        badge.transform = CGAffineTransformIdentity;
    } completion:nil];
    [checkRing drawAfter:0.3];
    [bar layoutIfNeeded];
    [bar startWithDuration:lifetime - 0.5 delay:0.5];

    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, container.accessibilityLabel);
    self.hideTimer = [NSTimer scheduledTimerWithTimeInterval:lifetime target:self selector:@selector(hideTimerFired) userInfo:nil repeats:NO];
}

- (void)retryTapped {
    void (^retry)(void) = self.retryBlock;
    [self dismissAnimated:YES];
    if (retry) retry();
}

- (void)tapped { [self dismissAnimated:YES]; }
- (void)hideTimerFired { [self dismissAnimated:YES]; }

- (void)dismissAnimated:(BOOL)animated {
    [self.hideTimer invalidate];
    self.hideTimer = nil;
    self.retryBlock = nil;
    UIView *container = self.container;
    SFPopupWindow *window = self.window;
    self.container = nil;
    self.window = nil;
    if (!container) return;
    void (^finish)(BOOL) = ^(BOOL done) {
        [container removeFromSuperview];
        window.hidden = YES;
    };
    if (!animated) { finish(YES); return; }
    CGRect hidden = self.hiddenFrame;
    UIView *body = container.subviews.firstObject;
    if (self.island) {
        // Fade the details, then pull back up under the island.
        UIView *content = body.subviews.lastObject;
        [UIView animateWithDuration:0.16 animations:^{ content.alpha = 0; }];
        [UIView animateWithDuration:0.42 delay:0.06 usingSpringWithDamping:0.92 initialSpringVelocity:0 options:0 animations:^{
            container.frame = hidden;
            body.layer.cornerRadius = hidden.size.height / 2;
            container.layer.shadowOpacity = 0;
        } completion:^(BOOL done) {
            [UIView animateWithDuration:0.12 animations:^{ container.alpha = 0; } completion:finish];
        }];
    } else {
        [UIView animateWithDuration:0.35 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
            container.frame = hidden;
        } completion:finish];
    }
}

@end
