//
//  SFProgressBar.m
//  Sevenfold
//

#import "SFProgressBar.h"
#import "SFTheme.h"

@interface SFProgressBar ()
@property (nonatomic, strong) CAGradientLayer *fill;
@end

@implementation SFProgressBar

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.clipsToBounds = YES;
        _trackColor = [SFTheme separator];
        _fill = [CAGradientLayer layer];
        _fill.startPoint = CGPointMake(0, 0.5);
        _fill.endPoint = CGPointMake(1, 0.5);
        [self.layer addSublayer:_fill];
        [self updateColors];
    }
    return self;
}

- (void)setTrackColor:(UIColor *)trackColor {
    _trackColor = trackColor;
    [self updateColors];
}

- (void)setComplete:(BOOL)complete {
    _complete = complete;
    [self updateColors];
}

- (void)setFailed:(BOOL)failed {
    _failed = failed;
    [self updateColors];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self updateColors];
}

- (void)updateColors {
    UITraitCollection *traits = self.traitCollection;
    self.backgroundColor = [self.trackColor resolvedColorWithTraitCollection:traits];
    if (self.failed) {
        UIColor *red = [[SFTheme danger] resolvedColorWithTraitCollection:traits];
        self.fill.colors = @[(id)red.CGColor, (id)red.CGColor];
    } else if (self.complete) {
        UIColor *green = [UIColor colorWithRed:0.20 green:0.77 blue:0.42 alpha:1];
        self.fill.colors = @[(id)green.CGColor, (id)green.CGColor];
    } else {
        self.fill.colors = @[(id)[UIColor colorWithRed:1 green:0.54 blue:0.24 alpha:1].CGColor,
                             (id)[UIColor colorWithRed:1 green:0.82 blue:0.48 alpha:1].CGColor];
    }
}

- (void)setProgress:(float)progress {
    [self setProgress:progress animated:NO];
}

- (void)setProgress:(float)progress animated:(BOOL)animated {
    _progress = MIN(MAX(progress, 0), 1);
    [CATransaction begin];
    [CATransaction setDisableActions:!animated];
    [CATransaction setAnimationDuration:0.35];
    [self layoutFill];
    [CATransaction commit];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.layer.cornerRadius = self.bounds.size.height / 2;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self layoutFill];
    [CATransaction commit];
}

- (void)layoutFill {
    CGFloat h = self.bounds.size.height;
    CGFloat w = self.bounds.size.width * self.progress;
    if (self.progress > 0) w = MAX(w, h);
    self.fill.frame = CGRectMake(0, 0, w, h);
    self.fill.cornerRadius = h / 2;
}

@end
