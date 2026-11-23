//
//  SFPopup.h
//  Sevenfold
//
//  In-app pop-up for signing results.
//  Dynamic Island iPhones: a black pill drops from under the island and sits
//  below the status bar (so the island and overlays like TrollSpeed stay clear).
//  Other iPhones: a frosted banner slides down like an iOS notification.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SFPopupStyle) {
    SFPopupStyleSuccess,
    SFPopupStyleFailure,
    SFPopupStyleInfo,
};

@interface SFPopup : NSObject
+ (void)showWithTitle:(NSString *)title subtitle:(nullable NSString *)subtitle style:(SFPopupStyle)style;
/// icon: the signed app's icon (nil = Sevenfold logo). retry: shows a Retry button (failures).
+ (void)showWithTitle:(NSString *)title subtitle:(nullable NSString *)subtitle style:(SFPopupStyle)style
                 icon:(nullable UIImage *)icon retry:(nullable void (^)(void))retry;
+ (BOOL)deviceHasDynamicIsland;
@end

NS_ASSUME_NONNULL_END
