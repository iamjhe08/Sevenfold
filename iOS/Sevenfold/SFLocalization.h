//
//  SFLocalization.h
//  Sevenfold
//
//  BY: T4MAG0
//
//  Sevenfold's own languages, switchable in the app without a restart.
//  Text is written in English in the code and looked up with SFL(@"English text").
//  Translations live in Languages/<code>.json, matched to Languages/en.json by position.
//

#import <Foundation/Foundation.h>

/// The text in the chosen language (English when there is no translation).
NSString *SFL(NSString *english);

extern NSString *const SFLanguageDidChangeNotification;

@interface SFLanguage : NSObject

/// Each: @{ @"code", @"native", @"english" }, English first.
+ (NSArray<NSDictionary *> *)available;
/// "auto" or a language code.
+ (NSString *)selectedCode;
+ (void)setSelectedCode:(NSString *)code;
/// The language actually shown.
+ (NSString *)effectiveCode;
+ (BOOL)isRightToLeft;
/// Points UIKit's layout direction at the language (Arabic: right to left).
+ (void)applyLayoutDirection;

@end
