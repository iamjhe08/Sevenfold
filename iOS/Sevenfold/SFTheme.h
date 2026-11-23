//
//  SFTheme.h
//  Sevenfold
//
//  Colours and reusable views. Midnight + amber, follows light/dark mode.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SFTheme : NSObject
+ (UIColor *)accent;          // deep amber (light) / amber (dark)
+ (UIColor *)accentSoft;      // tinted fill behind accent content
+ (UIColor *)midnight;        // #1D2747
+ (UIColor *)midnightDeep;    // #060914
+ (UIColor *)amber;           // #FF9A3D, both modes
+ (UIColor *)amberLight;      // #FFD27A
+ (UIColor *)success;
+ (UIColor *)warning;
+ (UIColor *)danger;
+ (UIColor *)background;
+ (UIColor *)card;
+ (UIColor *)secondaryText;
+ (UIColor *)separator;

+ (UIFont *)fontOfSize:(CGFloat)size weight:(UIFontWeight)weight;
+ (UIFont *)monoFontOfSize:(CGFloat)size;

+ (void)applyGlobalAppearance;

/// Filled amber button with large rounded corners.
+ (UIButton *)primaryButtonWithTitle:(NSString *)title;
/// Tinted, lighter button.
+ (UIButton *)secondaryButtonWithTitle:(NSString *)title;
+ (UIView *)cardView;
+ (UILabel *)labelWithSize:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color;
/// A small coloured capsule with text, e.g. "THIS IPHONE".
+ (UILabel *)pillWithText:(NSString *)text color:(UIColor *)color;
/// Rounded app icon placeholder with the first letter of the name.
+ (UIImage *)placeholderIconForName:(NSString *)name size:(CGFloat)size;
+ (UIImage *)symbol:(NSString *)name size:(CGFloat)size weight:(UIImageSymbolWeight)weight;
/// Square tile with a white SF Symbol, for settings rows.
+ (UIImage *)settingsIcon:(NSString *)symbol color:(UIColor *)color;

+ (NSString *)relativeExpiry:(NSDate *)date;
+ (UIColor *)colorForExpiry:(NSDate *)date;
+ (NSString *)shortDateTime:(NSDate *)date;
@end

NS_ASSUME_NONNULL_END
