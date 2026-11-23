//
//  SFProgressBar.h
//  Sevenfold
//
//  Straight, rounded progress bar (amber gradient while running, green when done).
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SFProgressBar : UIView
@property (nonatomic) float progress;            // 0…1
@property (nonatomic, strong) UIColor *trackColor;
@property (nonatomic) BOOL complete;             // green fill
@property (nonatomic) BOOL failed;               // red fill
- (void)setProgress:(float)progress animated:(BOOL)animated;
@end

NS_ASSUME_NONNULL_END
