//
//  SFTheme.m
//  Sevenfold
//

#import "SFTheme.h"
#import "SFLocalization.h"

static UIColor *SFHex(uint32_t hex, CGFloat alpha) {
    return [UIColor colorWithRed:((hex >> 16) & 0xFF) / 255.0
                           green:((hex >> 8) & 0xFF) / 255.0
                            blue:(hex & 0xFF) / 255.0
                           alpha:alpha];
}

static UIColor *SFDynamic(uint32_t light, uint32_t dark) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? SFHex(dark, 1) : SFHex(light, 1);
    }];
}

@implementation SFTheme

+ (UIColor *)accent { return SFDynamic(0xB85400, 0xFF9A3D); }
+ (UIColor *)accentSoft {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? SFHex(0xFF9A3D, 0.16) : SFHex(0xB85400, 0.10);
    }];
}
+ (UIColor *)midnight { return SFHex(0x1D2747, 1); }
+ (UIColor *)midnightDeep { return SFHex(0x060914, 1); }
+ (UIColor *)amber { return SFHex(0xFF9A3D, 1); }
+ (UIColor *)amberLight { return SFHex(0xFFD27A, 1); }
+ (UIColor *)success { return SFDynamic(0x137A3F, 0x4ADE80); }
+ (UIColor *)warning { return SFDynamic(0x9A4708, 0xF5B971); }
+ (UIColor *)danger { return SFDynamic(0xC4272C, 0xFF6B6B); }
+ (UIColor *)background { return SFDynamic(0xF2F2F7, 0x0B0D14); }
+ (UIColor *)card { return SFDynamic(0xFFFFFF, 0x171A24); }
+ (UIColor *)secondaryText { return SFDynamic(0x6B6B73, 0x9EA3B5); }
+ (UIColor *)separator { return SFDynamic(0xECECF0, 0x262A38); }

+ (UIFont *)fontOfSize:(CGFloat)size weight:(UIFontWeight)weight {
    UIFont *font = [UIFont systemFontOfSize:size weight:weight];
    UIFontDescriptor *rounded = [font.fontDescriptor fontDescriptorWithDesign:UIFontDescriptorSystemDesignDefault];
    return rounded ? [UIFont fontWithDescriptor:rounded size:size] : font;
}

+ (UIFont *)monoFontOfSize:(CGFloat)size {
    return [UIFont monospacedSystemFontOfSize:size weight:UIFontWeightRegular];
}

+ (void)applyGlobalAppearance {
    UINavigationBarAppearance *nav = [[UINavigationBarAppearance alloc] init];
    [nav configureWithDefaultBackground];
    nav.backgroundColor = [self background];
    nav.shadowColor = [UIColor clearColor];
    nav.largeTitleTextAttributes = @{ NSFontAttributeName: [self fontOfSize:32 weight:UIFontWeightBold] };
    nav.titleTextAttributes = @{ NSFontAttributeName: [self fontOfSize:17 weight:UIFontWeightSemibold] };
    UINavigationBar *bar = [UINavigationBar appearance];
    bar.standardAppearance = nav;
    bar.compactAppearance = nav;
    bar.scrollEdgeAppearance = nav;
    bar.tintColor = [self accent];

    UITabBarAppearance *tab = [[UITabBarAppearance alloc] init];
    [tab configureWithDefaultBackground];
    UITabBar *tabBar = [UITabBar appearance];
    tabBar.standardAppearance = tab;
    if (@available(iOS 15.0, *)) tabBar.scrollEdgeAppearance = tab;
    tabBar.tintColor = [self accent];

    [UISwitch appearance].onTintColor = [self accent];
}

+ (UIButton *)primaryButtonWithTitle:(NSString *)title {
    UIButtonConfiguration *config = [UIButtonConfiguration filledButtonConfiguration];
    config.title = title;
    config.baseBackgroundColor = [self accent];
    config.baseForegroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? SFHex(0x1A1205, 1) : [UIColor whiteColor];
    }];
    config.cornerStyle = UIButtonConfigurationCornerStyleLarge;
    config.contentInsets = NSDirectionalEdgeInsetsMake(15, 18, 15, 18);
    config.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *attrs) {
        NSMutableDictionary *m = [attrs mutableCopy];
        m[NSFontAttributeName] = [SFTheme fontOfSize:17 weight:UIFontWeightSemibold];
        return m;
    };
    UIButton *button = [UIButton buttonWithConfiguration:config primaryAction:nil];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    return button;
}

+ (UIButton *)secondaryButtonWithTitle:(NSString *)title {
    UIButtonConfiguration *config = [UIButtonConfiguration tintedButtonConfiguration];
    config.title = title;
    config.baseBackgroundColor = [self accent];
    config.baseForegroundColor = [self accent];
    config.cornerStyle = UIButtonConfigurationCornerStyleLarge;
    config.contentInsets = NSDirectionalEdgeInsetsMake(13, 16, 13, 16);
    config.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *attrs) {
        NSMutableDictionary *m = [attrs mutableCopy];
        m[NSFontAttributeName] = [SFTheme fontOfSize:16 weight:UIFontWeightSemibold];
        return m;
    };
    UIButton *button = [UIButton buttonWithConfiguration:config primaryAction:nil];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    return button;
}

+ (UIView *)cardView {
    UIView *view = [UIView new];
    view.translatesAutoresizingMaskIntoConstraints = NO;
    view.backgroundColor = [self card];
    view.layer.cornerRadius = 18;
    view.layer.cornerCurve = kCACornerCurveContinuous;
    return view;
}

+ (UILabel *)labelWithSize:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color {
    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [self fontOfSize:size weight:weight];
    label.textColor = color;
    label.numberOfLines = 0;
    label.adjustsFontForContentSizeCategory = YES;
    return label;
}

+ (UILabel *)pillWithText:(NSString *)text color:(UIColor *)color {
    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = [NSString stringWithFormat:@"  %@  ", text.uppercaseString];
    label.font = [self fontOfSize:11 weight:UIFontWeightBold];
    label.textColor = color;
    label.backgroundColor = [color colorWithAlphaComponent:0.14];
    label.layer.cornerRadius = 9;
    label.layer.masksToBounds = YES;
    [label.heightAnchor constraintEqualToConstant:18].active = YES;
    return label;
}

+ (UIImage *)placeholderIconForName:(NSString *)name size:(CGFloat)size {
    NSString *initial = name.length > 0 ? [[name substringToIndex:1] uppercaseString] : @"?";
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(size, size)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, size, size) cornerRadius:size * 0.225];
        [SFHex(0x1D2747, 1) setFill];
        [path fill];
        NSDictionary *attrs = @{ NSFontAttributeName: [UIFont systemFontOfSize:size * 0.45 weight:UIFontWeightBold],
                                 NSForegroundColorAttributeName: SFHex(0xFFD27A, 1) };
        CGSize textSize = [initial sizeWithAttributes:attrs];
        [initial drawAtPoint:CGPointMake((size - textSize.width) / 2, (size - textSize.height) / 2) withAttributes:attrs];
    }];
}

+ (UIImage *)symbol:(NSString *)name size:(CGFloat)size weight:(UIImageSymbolWeight)weight {
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:size weight:weight];
    return [UIImage systemImageNamed:name withConfiguration:config] ?: [UIImage systemImageNamed:@"circle" withConfiguration:config];
}

+ (UIImage *)settingsIcon:(NSString *)symbol color:(UIColor *)color {
    CGFloat size = 30;
    UIImage *glyph = [[self symbol:symbol size:15 weight:UIImageSymbolWeightSemibold] imageWithTintColor:[UIColor whiteColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(size, size)];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [color setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, size, size) cornerRadius:7.5] fill];
        CGSize g = glyph.size;
        [glyph drawInRect:CGRectMake((size - g.width) / 2, (size - g.height) / 2, g.width, g.height)];
    }];
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

+ (NSString *)relativeExpiry:(NSDate *)date {
    if (!date) return SFL(@"Unknown");
    NSTimeInterval left = [date timeIntervalSinceNow];
    if (left <= 0) return SFL(@"Expired");
    if (left < 3600) return SFL(@"Under 1 hour");
    NSInteger hours = left < 24 * 3600 ? (NSInteger)(left / 3600) : (NSInteger)lround(left / 3600.0);
    if (hours < 24) return [NSString stringWithFormat:(hours == 1 ? SFL(@"%ld hour") : SFL(@"%ld hours")), (long)hours];
    NSInteger days = hours / 24;
    NSInteger rest = hours % 24;
    if (days < 14) {
        NSString *d = [NSString stringWithFormat:(days == 1 ? SFL(@"%ld day") : SFL(@"%ld days")), (long)days];
        if (rest == 0) return d;
        return [NSString stringWithFormat:(rest == 1 ? SFL(@"%@, %ld hr") : SFL(@"%@, %ld hrs")), d, (long)rest];
    }
    if (days < 60) return [NSString stringWithFormat:(days == 1 ? SFL(@"%ld day") : SFL(@"%ld days")), (long)days];
    NSInteger months = days / 30;
    return [NSString stringWithFormat:SFL(@"%ld months"), (long)months];
}

+ (UIColor *)colorForExpiry:(NSDate *)date {
    NSTimeInterval left = [date timeIntervalSinceNow];
    if (!date || left <= 0) return [self danger];
    if (left < 2 * 24 * 3600) return [self warning];
    return [self success];
}

+ (NSString *)shortDateTime:(NSDate *)date {
    if (!date) return @"—";
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateFormatter *time = [NSDateFormatter new];
    time.dateStyle = NSDateFormatterNoStyle;
    time.timeStyle = NSDateFormatterShortStyle;
    if ([calendar isDateInToday:date]) return [NSString stringWithFormat:SFL(@"Today, %@"), [time stringFromDate:date]];
    if ([calendar isDateInTomorrow:date]) return [NSString stringWithFormat:SFL(@"Tomorrow, %@"), [time stringFromDate:date]];
    if ([calendar isDateInYesterday:date]) return [NSString stringWithFormat:SFL(@"Yesterday, %@"), [time stringFromDate:date]];
    NSDateFormatter *day = [NSDateFormatter new];
    day.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"EEE d MMM" options:0 locale:[NSLocale currentLocale]];
    return [NSString stringWithFormat:@"%@, %@", [day stringFromDate:date], [time stringFromDate:date]];
}

@end
