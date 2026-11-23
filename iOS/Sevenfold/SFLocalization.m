//
//  SFLocalization.m
//  Sevenfold
//
//  BY: T4MAG0
//

#import "SFLocalization.h"
#import <UIKit/UIKit.h>

NSString *const SFLanguageDidChangeNotification = @"SFLanguageDidChange";
static NSString *const SFLanguageKey = @"sfLanguage";

static NSDictionary<NSString *, NSString *> *SFTable;   // English → translation, for the effective language
static NSString *SFTableCode;

/// The printf-style placeholders in a string, in order ("%@", "%lu", "%.1f", …).
static NSArray<NSString *> *SFPlaceholders(NSString *text) {
    static NSRegularExpression *pattern;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        pattern = [NSRegularExpression regularExpressionWithPattern:@"%(?:\\d+\\$)?[-+ #0]*\\d*(?:\\.\\d+)?(?:hh|h|ll|l|q|z|t|j)?[@dDuUxXoOfeEgGcCsSp%]" options:0 error:nil];
    });
    NSMutableArray *found = [NSMutableArray array];
    for (NSTextCheckingResult *match in [pattern matchesInString:text options:0 range:NSMakeRange(0, text.length)]) {
        NSString *token = [text substringWithRange:match.range];
        // Positional "%1$@" counts as the same kind as "%@".
        NSRange dollar = [token rangeOfString:@"$"];
        if (dollar.location != NSNotFound) token = [@"%" stringByAppendingString:[token substringFromIndex:dollar.location + 1]];
        [found addObject:token];
    }
    return found;
}

static NSDictionary *SFLoadTable(NSString *code) {
    if ([code isEqualToString:@"en"]) return @{};
    NSString *folder = [[NSBundle mainBundle].resourcePath stringByAppendingPathComponent:@"Languages"];
    NSArray *english = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[folder stringByAppendingPathComponent:@"en.json"]] ?: [NSData data] options:0 error:nil];
    NSDictionary *translated = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[folder stringByAppendingPathComponent:[code stringByAppendingString:@".json"]]] ?: [NSData data] options:0 error:nil];
    if (![english isKindOfClass:[NSArray class]] || ![translated isKindOfClass:[NSDictionary class]]) return @{};

    NSMutableDictionary *table = [NSMutableDictionary dictionary];
    __block NSUInteger rejected = 0;
    [translated enumerateKeysAndObjectsUsingBlock:^(NSString *index, NSString *text, BOOL *stop) {
        NSInteger i = index.integerValue;
        if (![text isKindOfClass:[NSString class]] || i < 0 || i >= (NSInteger)english.count) return;
        NSString *source = english[i];
        // A translation must keep the same placeholders, or formatting it could crash.
        NSArray *a = [SFPlaceholders(source) sortedArrayUsingSelector:@selector(compare:)];
        NSArray *b = [SFPlaceholders(text) sortedArrayUsingSelector:@selector(compare:)];
        if (![a isEqualToArray:b]) { rejected++; return; }
        table[source] = text;
    }];
    if (rejected) NSLog(@"[Sevenfold] %lu %@ strings skipped (placeholders differ)", (unsigned long)rejected, code);
    return table;
}

NSString *SFL(NSString *english) {
    if (!english.length) return english;
    NSString *code = [SFLanguage effectiveCode];
    @synchronized ([SFLanguage class]) {
        if (![SFTableCode isEqualToString:code]) {
            SFTable = SFLoadTable(code);
            SFTableCode = code;
        }
        return SFTable[english] ?: english;
    }
}

@implementation SFLanguage

+ (NSArray<NSDictionary *> *)available {
    return @[
        @{ @"code": @"en",      @"native": @"English",          @"english": @"" },
        @{ @"code": @"zh-Hans", @"native": @"简体中文",          @"english": @"Chinese" },
        @{ @"code": @"es",      @"native": @"Español",          @"english": @"Spanish" },
        @{ @"code": @"pt",      @"native": @"Português",        @"english": @"Portuguese" },
        @{ @"code": @"ru",      @"native": @"Русский",          @"english": @"Russian" },
        @{ @"code": @"id",      @"native": @"Bahasa Indonesia", @"english": @"Indonesian" },
        @{ @"code": @"ja",      @"native": @"日本語",            @"english": @"Japanese" },
        @{ @"code": @"hi",      @"native": @"हिन्दी",              @"english": @"Hindi" },
        @{ @"code": @"ar",      @"native": @"العربية",          @"english": @"Arabic" },
    ];
}

+ (NSString *)selectedCode {
    NSString *code = [[NSUserDefaults standardUserDefaults] stringForKey:SFLanguageKey];
    return code.length ? code : @"auto";
}

+ (void)setSelectedCode:(NSString *)code {
    [[NSUserDefaults standardUserDefaults] setObject:code ?: @"auto" forKey:SFLanguageKey];
    [self applyLayoutDirection];
    [[NSNotificationCenter defaultCenter] postNotificationName:SFLanguageDidChangeNotification object:nil];
}

+ (NSString *)effectiveCode {
    NSString *chosen = [self selectedCode];
    if (![chosen isEqualToString:@"auto"]) return chosen;
    // Auto: the first of the iPhone's preferred languages that Sevenfold has.
    for (NSString *preferred in [NSLocale preferredLanguages]) {
        NSString *lower = preferred.lowercaseString;
        if ([lower hasPrefix:@"zh-hans"] || [lower isEqualToString:@"zh"] || [lower hasPrefix:@"zh-cn"] || [lower hasPrefix:@"zh-sg"]) return @"zh-Hans";
        for (NSDictionary *language in [self available]) {
            NSString *code = language[@"code"];
            if ([code isEqualToString:@"zh-Hans"]) continue;
            if ([lower isEqualToString:code] || [lower hasPrefix:[code stringByAppendingString:@"-"]]) return code;
        }
    }
    return @"en";
}

+ (BOOL)isRightToLeft {
    return [[self effectiveCode] isEqualToString:@"ar"];
}

+ (void)applyLayoutDirection {
    UISemanticContentAttribute direction = [self isRightToLeft] ? UISemanticContentAttributeForceRightToLeft : UISemanticContentAttributeForceLeftToRight;
    [UIView appearance].semanticContentAttribute = direction;
    [UINavigationBar appearance].semanticContentAttribute = direction;
    [UITabBar appearance].semanticContentAttribute = direction;
    [UISearchBar appearance].semanticContentAttribute = direction;
}

@end
