//
//  SFGrandSlam.m
//  Sevenfold
//
//  BY: T4MAG0
//
//  Sign-in, in three requests to gsa.apple.com/grandslam/GsService2:
//    init       send the SRP public value A; Apple answers with salt, iterations and B
//    complete   send the proof M1; Apple answers with M2 and an encrypted session (spd)
//    apptokens  ask for the Xcode token; Apple answers with it encrypted (et)
//  When two-factor is needed, "complete" says so and the code step runs in between.
//
//  The protocol details (password hashing, transcript HMAC, key names, AES modes)
//  follow Apple's AppleIDAuthSupport so Apple accepts the result.
//

#import "SFGrandSlam.h"
#import "SFAuthKit.h"
#import "SFAnisetteServers.h"
#import "SFLog.h"

#import <corecrypto/ccsrp.h>
#import <corecrypto/ccsrp_gp.h>
#import <corecrypto/ccdigest.h>
#import <corecrypto/ccsha2.h>
#import <corecrypto/ccpbkdf2.h>
#import <corecrypto/cchmac.h>
#import <corecrypto/ccaes.h>
#import <corecrypto/ccpad.h>
#import <corecrypto/ccrng.h>
#import <dlfcn.h>

struct ccrng_state *ccDRBGGetRngState(void);

static NSString *const SFGSService   = @"https://gsa.apple.com/grandslam/GsService2";
static NSString *const SFXcodeApp    = @"com.apple.gs.xcode.auth";
static const NSUInteger SFGSAttempts = 3;       // per request, for 5xx answers only
static const NSTimeInterval SFGSBudget = 20;    // seconds per request, retries included

#pragma mark - Small helpers

static NSError *SFLoginError(NSString *text, NSInteger code) {
    text = text.length ? text : @"Apple rejected the sign-in.";
    return [NSError errorWithDomain:NSCocoaErrorDomain code:code userInfo:@{ NSLocalizedDescriptionKey: text, NSLocalizedFailureReasonErrorKey: text }];
}

static id SFAs(id value, Class kind) {
    return [value isKindOfClass:kind] ? value : nil;
}

/// Apple wants "akd" as the client in X-MMe-Client-Info, not Xcode.
static NSString *SFAkdClientInfo(NSString *info) {
    if (![info isKindOfClass:[NSString class]]) return nil;
    static NSRegularExpression *xcode;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        xcode = [NSRegularExpression regularExpressionWithPattern:@"(?<=\\()com\\.apple\\.dt\\.Xcode/[^\\s()<>]+(?=\\))" options:NSRegularExpressionCaseInsensitive error:nil];
    });
    return [xcode stringByReplacingMatchesInString:info options:0 range:NSMakeRange(0, info.length) withTemplate:@"com.apple.akd/1.0"];
}

/// The verification code as six ASCII digits; any script's digits count (AutoFill, Arabic keypad, …).
static NSString *SFSixDigits(NSString *code) {
    NSMutableString *digits = [NSMutableString string];
    for (NSUInteger i = 0; i < code.length; i++) {
        unichar c = [code characterAtIndex:i];
        // Unicode puts each script's 0–9 in a run of ten; the run's start is the "0".
        static const unichar zeros[] = { 0x0030, 0x0660, 0x06F0, 0x07C0, 0x0966, 0x09E6, 0x0A66, 0x0AE6, 0x0B66, 0x0BE6,
                                         0x0C66, 0x0CE6, 0x0D66, 0x0DE6, 0x0E50, 0x0ED0, 0x0F20, 0x1040, 0x1090, 0x17E0,
                                         0x1810, 0x1946, 0x19D0, 0x1A80, 0x1A90, 0x1B50, 0x1BB0, 0x1C40, 0x1C50, 0xA620,
                                         0xA8D0, 0xA900, 0xA9D0, 0xA9F0, 0xAA50, 0xABF0, 0xFF10 };
        for (size_t z = 0; z < sizeof(zeros) / sizeof(zeros[0]); z++) {
            if (c >= zeros[z] && c <= zeros[z] + 9) { [digits appendFormat:@"%d", c - zeros[z]]; break; }
        }
    }
    return digits;
}

#pragma mark - Crypto (AppleIDAuthSupport-compatible)

/// The SRP "password": PBKDF2-HMAC-SHA256 over SHA-256(password).
/// "s2k" uses the raw digest; "s2k_fo" uses it written as lowercase hex.
static NSData *SFPasswordKey(NSString *password, BOOL hexDigest, NSData *salt, NSInteger iterations) {
    const struct ccdigest_info *sha256 = ccsha256_di();
    const char *utf8 = password.UTF8String ?: "";
    unsigned char digest[32];
    ccdigest(sha256, strlen(utf8), utf8, digest);

    char input[64];
    size_t inputLength = 32;
    if (hexDigest) {
        static const char hex[] = "0123456789abcdef";
        for (int i = 0; i < 32; i++) { input[i * 2] = hex[digest[i] >> 4]; input[i * 2 + 1] = hex[digest[i] & 0xF]; }
        inputLength = 64;
    } else {
        memcpy(input, digest, 32);
    }
    NSMutableData *key = [NSMutableData dataWithLength:sha256->output_size];
    if (ccpbkdf2_hmac(sha256, inputLength, input, salt.length, salt.bytes, iterations, key.length, key.mutableBytes) != 0) return nil;
    return key;
}

/// One SRP sign-in: the corecrypto context and the running hash of what was negotiated.
@interface SFSRPExchange : NSObject {
@public
    struct ccsrp_ctx *srp;
    struct ccdigest_ctx *transcript;
    const struct ccdigest_info *sha256;
}
@end

@implementation SFSRPExchange
- (instancetype)init {
    if ((self = [super init])) {
        sha256 = ccsha256_di();
        ccsrp_const_gp_t group = ccsrp_gp_rfc5054_2048();
        srp = (struct ccsrp_ctx *)calloc(1, ccsrp_sizeof_srp(sha256, group));
        ccsrp_ctx_init(srp, sha256, group);
        ccsrp_client_set_noUsernameInX(srp, true);
        SRP_RNG(srp) = ccrng(NULL);
        transcript = (struct ccdigest_ctx *)calloc(1, ccdigest_di_size(sha256));
        ccdigest_init(sha256, transcript);
    }
    return self;
}
- (void)dealloc {
    free(srp);
    free(transcript);
}
/// Strings go into the transcript as-is; data goes in with a 4-byte length first.
- (void)note:(const char *)text { ccdigest_update(sha256, transcript, strlen(text), text); }
- (void)noteData:(NSData *)data {
    uint32_t length = (uint32_t)data.length;
    ccdigest_update(sha256, transcript, sizeof(length), &length);
    ccdigest_update(sha256, transcript, length, data.bytes);
}
/// HMAC-SHA256 of the SRP session key under a label ("HMAC key:", "extra data key:", …).
- (NSData *)sessionKeyFor:(const char *)label {
    size_t length = 0;
    const void *key = ccsrp_get_session_key(srp, &length);
    NSMutableData *out = [NSMutableData dataWithLength:sha256->output_size];
    cchmac(sha256, length, key, strlen(label), label, out.mutableBytes);
    return out;
}
/// Checks Apple's "np": an HMAC of the transcript under the session's HMAC key.
- (BOOL)transcriptMatches:(NSData *)expected {
    if (expected.length != sha256->output_size) return NO;
    unsigned char digest[32], mac[32];
    sha256->final(sha256, transcript, digest);
    NSData *key = [self sessionKeyFor:"HMAC key:"];
    cchmac(sha256, key.length, key.bytes, sizeof(digest), digest, mac);
    return cc_cmp_safe(sizeof(mac), mac, expected.bytes) == 0;
}
/// Opens "spd" (AES-CBC, PKCS#7) with keys derived from the session.
- (NSData *)openSessionData:(NSData *)spd {
    NSData *key = [self sessionKeyFor:"extra data key:"];
    NSData *iv = [self sessionKeyFor:"extra data iv:"];
    const struct ccmode_cbc *cbc = ccaes_cbc_decrypt_mode();
    cccbc_iv ivBuffer[cbc->block_size];
    memcpy(ivBuffer, iv.bytes, cbc->block_size);
    cccbc_ctx context[cbc->size];
    cbc->init(cbc, context, key.length, key.bytes);
    NSMutableData *plain = [NSMutableData dataWithLength:spd.length];
    size_t length = ccpad_pkcs7_decrypt(cbc, context, ivBuffer, spd.length, spd.bytes, plain.mutableBytes);
    if (length > spd.length) return nil;
    plain.length = length;
    return plain;
}
@end

/// The app token arrives as "XYZ" + 16-byte IV + AES-GCM ciphertext + 16-byte tag.
static NSData *SFOpenAppToken(NSData *sessionKey, NSData *sealed) {
    if (sealed.length < 35 || memcmp(sealed.bytes, "XYZ", 3) != 0) return nil;
    const unsigned char *bytes = sealed.bytes;
    const struct ccmode_gcm *gcm = ccaes_gcm_decrypt_mode();
    ccgcm_ctx context[gcm->size];
    gcm->init(gcm, context, sessionKey.length, sessionKey.bytes);
    gcm->set_iv(context, 16, bytes + 3);
    gcm->gmac(context, 3, bytes);                       // the "XYZ" header is authenticated too
    size_t length = sealed.length - 35;
    NSMutableData *plain = [NSMutableData dataWithLength:length];
    gcm->gcm(context, length, bytes + 19, plain.mutableBytes);
    unsigned char tag[16];
    gcm->finalize(context, sizeof(tag), tag);
    return cc_cmp_safe(16, bytes + 19 + length, tag) == 0 ? plain : nil;
}

/// Proof that we hold the session key, sent with the token request:
/// HMAC-SHA256(sk, "apptokens" + dsid + each app name).
static NSData *SFAppTokenChecksum(NSData *sessionKey, NSString *dsid, NSArray<NSString *> *apps) {
    const struct ccdigest_info *sha256 = ccsha256_di();
    struct cchmac_ctx context[cchmac_di_size(sha256)];
    cchmac_init(sha256, context, sessionKey.length, sessionKey.bytes);
    NSMutableArray *parts = [@[@"apptokens", dsid ?: @""] mutableCopy];
    [parts addObjectsFromArray:apps];
    for (NSString *part in parts) {
        const char *utf8 = part.UTF8String;
        cchmac_update(sha256, context, strlen(utf8), utf8);
    }
    NSMutableData *out = [NSMutableData dataWithLength:sha256->output_size];
    cchmac_final(sha256, context, out.mutableBytes);
    return out;
}

#pragma mark - SFGrandSlam

@interface SFGrandSlam ()
@property (nonatomic, copy) NSDictionary *endpoints;    // from GsService2/lookup
@property (nonatomic, copy) NSDictionary *trustedPhone; // { id, mode } for the phone 2FA step
@end

@implementation SFGrandSlam

- (instancetype)init {
    if ((self = [super init])) self.clientInfo = SFClientIdentity;
    return self;
}

- (void)setClientInfo:(NSString *)clientInfo {
    _clientInfo = [SFAkdClientInfo(clientInfo) copy];
}

- (void)setAnisette:(NSDictionary *)anisette {
    if (![anisette isKindOfClass:[NSDictionary class]]) { _anisette = nil; return; }
    NSMutableDictionary *headers = [anisette mutableCopy];
    NSString *info = SFAkdClientInfo(anisette[@"X-MMe-Client-Info"]);
    if (info) headers[@"X-MMe-Client-Info"] = info;
    _anisette = [headers copy];
}

#pragma mark Identity sent with every request

/// Anisette headers: the remote provider's, or else this iPhone's own.
- (NSDictionary *)anisetteHeaders {
    if (self.anisette.count) return self.anisette;

    dlopen("/System/Library/PrivateFrameworks/AuthKit.framework/AuthKit", RTLD_NOW);
    NSDictionary *native = [[[NSClassFromString(@"AKAppleIDSession") alloc] initWithIdentifier:SFXcodeApp] appleIDHeadersForRequest:nil];
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
    formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
    NSMutableDictionary *headers = [@{
        @"X-Apple-I-Client-Time": [formatter stringFromDate:[NSDate date]],
        @"X-Apple-Locale": NSLocale.currentLocale.localeIdentifier,
        @"X-Apple-I-TimeZone": NSTimeZone.localTimeZone.abbreviation ?: @"UTC",
    } mutableCopy];
    [headers addEntriesFromDictionary:native ?: @{}];
    headers[@"X-MMe-Client-Info"] = self.clientInfo;
    return headers;
}

/// Device identifiers, only when using this iPhone's own anisette (remote anisette brings its own).
- (NSDictionary *)deviceHeaders {
    if (self.anisette.count) return @{};
    dlopen("/System/Library/PrivateFrameworks/AuthKit.framework/AuthKit", RTLD_NOW);
    AKDevice *device = [NSClassFromString(@"AKDevice") currentDevice];
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    if (device.uniqueDeviceIdentifier) headers[@"X-Mme-Device-Id"] = device.uniqueDeviceIdentifier;
    if ([device respondsToSelector:@selector(MLBSerialNumber)] && device.MLBSerialNumber) headers[@"X-Apple-I-MLB"] = device.MLBSerialNumber;
    if ([device respondsToSelector:@selector(ROMAddress)] && device.ROMAddress) headers[@"X-Apple-I-ROM"] = device.ROMAddress;
    if (device.serialNumber) headers[@"X-Apple-I-SRL-NO"] = device.serialNumber;
    return headers;
}

/// "cpd": client details sent inside every GrandSlam request.
- (NSDictionary *)clientDetails {
    NSMutableDictionary *details = [@{ @"bootstrap": @YES, @"icscrec": @YES, @"loc": NSLocale.currentLocale.localeIdentifier,
                                       @"pbe": @NO, @"prkgen": @YES, @"svct": @"iCloud" } mutableCopy];
    [details addEntriesFromDictionary:[self anisetteHeaders]];
    [details addEntriesFromDictionary:[self deviceHeaders]];
    return details;
}

#pragma mark GrandSlam transport

/// Sends one request, with a fresh connection per attempt. 5xx answers without an Apple
/// error code are tried again (1, 2, 4 s or Retry-After) while the 20 s budget lasts.
- (void)send:(NSURLRequest *)request attempt:(NSUInteger)attempt deadline:(NSTimeInterval)deadline completion:(void (^)(NSData *, NSHTTPURLResponse *, NSError *))completion {
    NSTimeInterval left = deadline - NSProcessInfo.processInfo.systemUptime;
    if (left <= 0) { completion(nil, nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil]); return; }

    NSMutableURLRequest *timed = [request mutableCopy];
    timed.timeoutInterval = MIN(10, left);
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    config.URLCache = nil;
    config.URLCredentialStorage = nil;
    config.HTTPCookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];   // cookies shared, connections not
    config.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    config.timeoutIntervalForRequest = config.timeoutIntervalForResource = timed.timeoutInterval;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];

    [[session dataTaskWithRequest:timed completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        [session finishTasksAndInvalidate];
        NSHTTPURLResponse *http = SFAs(response, [NSHTTPURLResponse class]);
        NSInteger status = http.statusCode;
        BOOL serverTrouble = !error && status >= 500 && status <= 599 && ![self appleErrorIn:data];
        NSTimeInterval wait = [self retryDelayFor:http attempt:attempt];
        if (serverTrouble && attempt < SFGSAttempts && NSProcessInfo.processInfo.systemUptime + wait + 1 < deadline) {
            SFLogEvent(SFLogLevelInfo, @"sign-in · Apple answered HTTP %ld, trying again in %.0f s", (long)status, wait);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(wait * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                [self send:request attempt:attempt + 1 deadline:deadline completion:completion];
            });
            return;
        }
        completion(data, http, error);
    }] resume];
}

/// YES when a 5xx body carries Apple's own error code (a real answer, not worth repeating).
- (BOOL)appleErrorIn:(NSData *)data {
    if (data.length == 0) return NO;
    NSDictionary *plist = SFAs([NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:nil], [NSDictionary class]);
    id code = SFAs(SFAs(plist[@"Response"], [NSDictionary class])[@"Status"], [NSDictionary class])[@"ec"];
    if ([code isKindOfClass:[NSNumber class]]) return [code longLongValue] != 0;
    if ([code isKindOfClass:[NSString class]]) {
        NSScanner *scanner = [NSScanner scannerWithString:code];
        long long value = 0;
        return [scanner scanLongLong:&value] && scanner.isAtEnd && value != 0;
    }
    return NO;
}

- (NSTimeInterval)retryDelayFor:(NSHTTPURLResponse *)response attempt:(NSUInteger)attempt {
    NSTimeInterval delay = (NSTimeInterval)(1UL << MIN(attempt - 1, (NSUInteger)3));
    NSString *retryAfter = [response valueForHTTPHeaderField:@"Retry-After"];
    if (!retryAfter.length) return delay;
    NSScanner *scanner = [NSScanner scannerWithString:retryAfter];
    long long seconds = 0;
    if ([scanner scanLongLong:&seconds] && scanner.isAtEnd && seconds >= 0) return MAX(delay, seconds);
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    formatter.dateFormat = @"EEE',' dd MMM yyyy HH':'mm':'ss 'GMT'";
    NSDate *date = [formatter dateFromString:retryAfter];
    return date ? MAX(delay, date.timeIntervalSinceNow) : delay;
}

/// One GsService2 request; answers Apple's "Response" dictionary.
- (void)grandSlam:(NSDictionary *)fields completion:(void (^)(NSError *, NSDictionary *))completion {
    NSString *step = fields[@"o"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:SFGSService]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = [NSPropertyListSerialization dataWithPropertyList:@{ @"Header": @{ @"Version": @"1.0.1" }, @"Request": fields }
                                                                  format:NSPropertyListXMLFormat_v1_0 options:0 error:nil];
    NSDictionary *headers = @{
        @"X-MMe-Client-Info": self.clientInfo ?: @"",
        @"Content-Type": @"text/x-xml-plist",
        @"User-Agent": SFAkdUserAgent,
        @"X-Xcode-Version": @"27.0 (27A5218g)",
        @"X-Apple-App-Info": SFXcodeApp,
        @"Accept": @"*/*",
    };
    [headers enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) { [request setValue:value forHTTPHeaderField:key]; }];

    [self send:request attempt:1 deadline:NSProcessInfo.processInfo.systemUptime + SFGSBudget completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        if (error) {
            SFLogEvent(SFLogLevelError, @"sign-in · %@ failed: %@", step, error.localizedDescription);
            completion(error, nil);
            return;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
            SFLogEvent(SFLogLevelError, @"sign-in · %@ answered HTTP %ld", step, (long)response.statusCode);
            completion(SFLoginError([NSString stringWithFormat:@"Apple's sign-in service failed during %@ (HTTP %ld). Please try again later.", step, (long)response.statusCode], SFInternalLoginError), nil);
            return;
        }
        NSError *parseError = nil;
        NSDictionary *plist = SFAs([NSPropertyListSerialization propertyListWithData:data ?: [NSData data] options:0 format:NULL error:&parseError], [NSDictionary class]);
        NSDictionary *answer = SFAs(plist[@"Response"], [NSDictionary class]);
        if (!answer) {
            completion(data.length ? (parseError ?: SFLoginError(@"Apple's sign-in answer couldn't be read.", SFInternalLoginError))
                                   : SFLoginError(@"Apple returned an empty sign-in answer.", SFInternalLoginError), nil);
            return;
        }
        SFLogEvent(SFLogLevelInfo, @"sign-in · %@ answered (code %ld)", step, (long)[SFAs(answer[@"Status"], [NSDictionary class])[@"ec"] integerValue]);
        completion(nil, answer);
    }];
}

/// Reads the endpoint list (2FA URLs) once per sign-in object.
- (void)loadEndpoints:(void (^)(NSError *))completion {
    if (self.endpoints) { completion(nil); return; }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[SFGSService stringByAppendingString:@"/lookup"]]];
    NSMutableDictionary *headers = [@{
        @"Content-Type": @"text/x-xml-plist", @"Accept": @"text/x-xml-plist", @"Accept-Language": @"en-us",
        @"User-Agent": SFAkdUserAgent, @"X-Apple-App-Info": SFXcodeApp, @"X-Xcode-Version": @"14.2 (14C18)",
    } mutableCopy];
    [headers addEntriesFromDictionary:[self anisetteHeaders]];
    [headers addEntriesFromDictionary:[self deviceHeaders]];
    [headers enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) { [request setValue:value forHTTPHeaderField:key]; }];

    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) { completion(error); return; }
        NSDictionary *plist = SFAs([NSPropertyListSerialization propertyListWithData:data ?: [NSData data] options:0 format:NULL error:nil], [NSDictionary class]);
        NSDictionary *urls = SFAs(plist[@"urls"], [NSDictionary class]);
        if (!urls.count) { completion(SFLoginError(@"Apple's sign-in service list couldn't be read.", SFInternalLoginError)); return; }
        self.endpoints = urls;
        completion(nil);
    }] resume];
}

/// Apple's error in a GrandSlam answer, or nil when ec is 0 or missing.
static NSError *SFStatusError(NSDictionary *answer) {
    NSDictionary *status = SFAs(answer[@"Status"], [NSDictionary class]);
    NSInteger code = [status[@"ec"] integerValue];
    return code ? SFLoginError(SFAs(status[@"em"], [NSString class]), code) : nil;
}

#pragma mark Sign-in

- (void)loginWithUsername:(NSString *)username password:(NSString *)password completion:(SFLoginResultBlock)completion {
    SFLogEvent(SFLogLevelInfo, @"sign-in · starting (%@ anisette)", self.anisette.count ? @"remote" : @"this iPhone's");
    void (^fail)(NSError *) = ^(NSError *error) { completion(error, nil, nil, nil); };

    [self loadEndpoints:^(NSError *lookupError) {
        if (lookupError) { fail(lookupError); return; }
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSDictionary *details = [self clientDetails];
            SFSRPExchange *exchange = [SFSRPExchange new];

            // init: offer both password schemes and send A.
            NSArray *schemes = @[@"s2k", @"s2k_fo"];
            [exchange note:"s2k"]; [exchange note:","]; [exchange note:"s2k_fo"];
            NSMutableData *A = [NSMutableData dataWithLength:ccsrp_exchange_size(exchange->srp)];
            ccsrp_client_start_authentication(exchange->srp, ccDRBGGetRngState(), A.mutableBytes);
            [exchange note:"|"];

            [self grandSlam:@{ @"A2k": A, @"ps": schemes, @"cpd": details, @"u": username, @"o": @"init" } completion:^(NSError *error, NSDictionary *challenge) {
                if (error || (error = SFStatusError(challenge))) { fail(error); return; }
                [self answerChallenge:challenge exchange:exchange username:username password:password details:details completion:completion];
            }];
        });
    }];
}

/// complete: prove the password, check Apple's proof, and open the session details.
- (void)answerChallenge:(NSDictionary *)challenge exchange:(SFSRPExchange *)exchange username:(NSString *)username password:(NSString *)password
                details:(NSDictionary *)details completion:(SFLoginResultBlock)completion {
    void (^fail)(NSError *) = ^(NSError *error) { completion(error, nil, nil, nil); };
    NSString *scheme = SFAs(challenge[@"sp"], [NSString class]);
    NSData *salt = SFAs(challenge[@"s"], [NSData class]), *B = SFAs(challenge[@"B"], [NSData class]);
    [exchange note:"|"];
    if (scheme) [exchange note:scheme.UTF8String];

    NSData *key = SFPasswordKey(password, ![scheme isEqualToString:@"s2k"], salt, [challenge[@"i"] integerValue]);
    if (!key || !salt || !B) { fail(SFLoginError(@"Couldn't prepare the password proof.", SFInternalLoginError)); return; }
    NSMutableData *M1 = [NSMutableData dataWithLength:ccsrp_get_session_key_length(exchange->srp)];
    if (ccsrp_client_process_challenge(exchange->srp, username.UTF8String, key.length, key.bytes, salt.length, salt.bytes, B.bytes, M1.mutableBytes) != 0) {
        fail(SFLoginError(@"Couldn't answer Apple's password challenge.", SFInternalLoginError));
        return;
    }

    [self grandSlam:@{ @"c": challenge[@"c"] ?: @"", @"M1": M1, @"cpd": details, @"u": username, @"o": @"complete" } completion:^(NSError *error, NSDictionary *result) {
        if (error) { fail(error); return; }
        NSDictionary *status = SFAs(result[@"Status"], [NSDictionary class]);
        NSInteger code = [status[@"ec"] integerValue];
        NSString *outerMode = SFAs(status[@"au"], [NSString class]);
        BOOL secondFactor = outerMode.length > 0 || code == 409;
        // A non-zero code is fatal, unless it is the two-factor request (handled after decrypting).
        if (code && !secondFactor) { fail(SFLoginError(SFAs(status[@"em"], [NSString class]) ?: @"Apple rejected the sign-in.", code)); return; }

        NSData *M2 = SFAs(result[@"M2"], [NSData class]);
        if (M2.length != ccsrp_get_session_key_length(exchange->srp) || !ccsrp_client_verify_session(exchange->srp, M2.bytes)) {
            fail(SFLoginError(@"Apple's answer couldn't be verified.", SFInternalLoginError));
            return;
        }
        NSData *spd = SFAs(result[@"spd"], [NSData class]), *sc = SFAs(result[@"sc"], [NSData class]);
        [exchange note:"|"]; if (spd) [exchange noteData:spd];
        [exchange note:"|"]; if (sc) [exchange noteData:sc];
        [exchange note:"|"];
        if (![exchange transcriptMatches:SFAs(result[@"np"], [NSData class])]) {
            fail(SFLoginError(@"Apple's answer doesn't match what was negotiated.", SFInternalLoginError));
            return;
        }
        NSData *plain = spd ? [exchange openSessionData:spd] : nil;
        NSDictionary *session = plain ? SFAs([NSPropertyListSerialization propertyListWithData:plain options:0 format:NULL error:nil], [NSDictionary class]) : nil;
        if (!session) { fail(SFLoginError(@"Apple's session details couldn't be opened.", SFInternalLoginError)); return; }

        NSString *dsid = SFAs(session[@"adsid"], [NSString class]);
        NSString *idms = SFAs(session[@"GsIdmsToken"], [NSString class]);
        if (!dsid.length || !idms.length) { fail(SFLoginError(@"Apple returned an incomplete sign-in session.", SFInternalLoginError)); return; }
        NSString *acname = SFAs(session[@"acname"], [NSString class]);
        NSString *account = acname.length ? acname : username;
        NSString *identity = [NSString stringWithFormat:@"%@|%@", dsid, account];

        // Two-factor may be flagged outside or inside the encrypted part.
        if (secondFactor || [session[@"status-code"] integerValue] == 409) {
            NSString *mode = outerMode.length ? outerMode : SFAs(session[@"url"], [NSString class]);
            int needed = (mode.length == 0 || [mode isEqualToString:@"trustedDeviceSecondaryAuth"]) ? SFInternalLogin2FARequiredTrustedDeviceError
                                                                                                     : SFInternalLogin2FARequiredSecondaryAuthError;
            SFLogEvent(SFLogLevelInfo, @"sign-in · two-factor code needed (%@)", needed == SFInternalLogin2FARequiredTrustedDeviceError ? @"trusted device" : @"phone");
            completion(SFLoginError(SFAs(status[@"em"], [NSString class]) ?: @"Two-factor authentication is required", needed), identity, nil, idms);
            return;
        }
        [self requestAppTokenWithSession:session dsid:dsid idms:idms identity:identity details:details completion:completion];
    }];
}

/// apptokens: exchange the session for the Xcode token.
- (void)requestAppTokenWithSession:(NSDictionary *)session dsid:(NSString *)dsid idms:(NSString *)idms identity:(NSString *)identity
                           details:(NSDictionary *)details completion:(SFLoginResultBlock)completion {
    void (^fail)(NSError *) = ^(NSError *error) { completion(error, nil, nil, nil); };
    NSData *sessionKey = SFAs(session[@"sk"], [NSData class]), *c = SFAs(session[@"c"], [NSData class]);
    if (!sessionKey.length || !c.length) { fail(SFLoginError(@"Apple returned incomplete token details.", SFInternalLoginError)); return; }

    NSArray *apps = @[SFXcodeApp];
    [self grandSlam:@{ @"u": dsid, @"app": apps, @"c": c, @"t": idms, @"checksum": SFAppTokenChecksum(sessionKey, dsid, apps), @"cpd": details, @"o": @"apptokens" }
         completion:^(NSError *error, NSDictionary *result) {
        if (error || (error = SFStatusError(result))) { fail(error); return; }
        NSData *plain = SFOpenAppToken(sessionKey, SFAs(result[@"et"], [NSData class]));
        NSDictionary *tokens = plain ? SFAs([NSPropertyListSerialization propertyListWithData:plain options:0 format:NULL error:nil], [NSDictionary class]) : nil;
        NSString *token = SFAs(SFAs(SFAs(tokens[@"t"], [NSDictionary class])[SFXcodeApp], [NSDictionary class])[@"token"], [NSString class]);
        if (!token.length) { fail(SFLoginError(@"Apple didn't return the Xcode token.", SFInternalLoginError)); return; }
        SFLogEvent(SFLogLevelOK, @"sign-in · signed in");
        completion(nil, identity, token, nil);
    }];
}

#pragma mark Two-factor

/// A request to the 2FA endpoints, authenticated with the IDMS token.
- (NSMutableURLRequest *)twoFactorRequest:(NSString *)url identity:(NSString *)identity token:(NSString *)token json:(BOOL)json {
    NSString *dsid = [identity componentsSeparatedByString:@"|"].firstObject;
    NSURL *URL = url.length ? [NSURL URLWithString:url] : nil;
    if (!URL || !dsid.length || !token.length) return nil;
    NSString *identityToken = [[[NSString stringWithFormat:@"%@:%@", dsid, token] dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:URL];
    NSMutableDictionary *headers = [@{
        @"Content-Type": json ? @"application/json" : @"text/x-xml-plist",
        @"Accept": json ? @"application/json" : @"text/x-xml-plist",
        @"Accept-Language": @"en-us",
        @"User-Agent": SFAkdUserAgent,
        @"X-Apple-App-Info": SFXcodeApp,
        @"X-Apple-Client-App-Name": @"Xcode",
        @"X-Xcode-Version": @"14.2 (14C18)",
        @"X-Apple-Identity-Token": identityToken,
    } mutableCopy];
    [headers addEntriesFromDictionary:[self anisetteHeaders]];
    [headers addEntriesFromDictionary:[self deviceHeaders]];
    if (self.clientInfo.length) headers[@"X-MMe-Client-Info"] = self.clientInfo;
    if (json) { headers[@"Content-Type"] = @"application/json"; headers[@"Accept"] = @"application/json"; }
    [headers enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) { [request setValue:value forHTTPHeaderField:key]; }];
    return request;
}

/// 2FA answers come as a plist or JSON.
static NSDictionary *SFReadAnswer(NSData *data) {
    if (!data.length) return nil;
    id object = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:nil];
    if (![object isKindOfClass:[NSDictionary class]]) object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return SFAs(object, [NSDictionary class]);
}

/// The answer and the dictionaries nested in it where Apple puts details.
static NSArray<NSDictionary *> *SFAnswerLayers(NSDictionary *answer) {
    if (!answer) return @[];
    NSMutableArray *layers = [NSMutableArray arrayWithObject:answer];
    for (NSString *key in @[@"Response", @"response", @"serverInfo", @"ServerInfo"]) {
        NSDictionary *inner = SFAs(answer[key], [NSDictionary class]);
        if (!inner) continue;
        [layers addObject:inner];
        NSDictionary *info = SFAs(inner[@"serverInfo"] ?: inner[@"ServerInfo"], [NSDictionary class]);
        if (info) [layers addObject:info];
    }
    return layers;
}

/// Apple's error code anywhere in the answer; a nested non-zero code wins over an outer 0.
static NSNumber *SFAnswerCode(NSDictionary *answer) {
    NSNumber *found = nil;
    for (NSDictionary *layer in SFAnswerLayers(answer)) {
        NSMutableArray *codes = [NSMutableArray array];
        for (id code in @[layer[@"ec"] ?: [NSNull null], layer[@"code"] ?: [NSNull null], SFAs(layer[@"Status"], [NSDictionary class])[@"ec"] ?: [NSNull null]]) [codes addObject:code];
        for (NSString *key in @[@"service_errors", @"serviceErrors"])
            for (NSDictionary *entry in SFAs(layer[key], [NSArray class])) if ([entry isKindOfClass:[NSDictionary class]] && entry[@"code"]) [codes addObject:entry[@"code"]];
        for (id raw in codes) {
            NSString *text = [raw isKindOfClass:[NSNumber class]] ? [raw stringValue] : SFAs(raw, [NSString class]);
            NSScanner *scanner = text.length ? [NSScanner scannerWithString:text] : nil;
            long long value = 0;
            if (!scanner || ![scanner scanLongLong:&value] || !scanner.isAtEnd) continue;
            if (value) return @(value);
            found = @0;
        }
    }
    return found;
}

static NSString *SFAnswerMessage(NSDictionary *answer) {
    for (NSDictionary *layer in SFAnswerLayers(answer)) {
        for (NSString *key in @[@"em", @"message", @"userString", @"title"]) if ([SFAs(layer[key], [NSString class]) length]) return layer[key];
        NSDictionary *first = SFAs([SFAs(layer[@"service_errors"] ?: layer[@"serviceErrors"], [NSArray class]) firstObject], [NSDictionary class]);
        for (NSString *key in @[@"message", @"title"]) if ([SFAs(first[key], [NSString class]) length]) return first[key];
    }
    return nil;
}

/// nil if the 2FA call worked. An empty 2xx is fine; an unreadable non-empty one is not.
- (NSError *)twoFactorError:(NSData *)data response:(NSURLResponse *)response error:(NSError *)error {
    if (error) return error;
    NSHTTPURLResponse *http = SFAs(response, [NSHTTPURLResponse class]);
    if (!http) return SFLoginError(@"Apple returned an invalid answer.", SFInternalLoginError);
    NSDictionary *answer = SFReadAnswer(data);
    NSNumber *code = SFAnswerCode(answer);
    if (code.integerValue == -21669) return SFLoginError(@"Incorrect 2FA code", SFInternalLoginIncorrect2FACodeError);
    BOOL httpFailed = http.statusCode < 200 || http.statusCode >= 300;
    if (httpFailed || code.integerValue) {
        NSString *message = SFAnswerMessage(answer) ?: (httpFailed ? [NSString stringWithFormat:@"Apple rejected the request (HTTP %ld)", (long)http.statusCode] : @"Apple rejected the request");
        NSInteger errorCode = code.integerValue ?: http.statusCode;
        return SFLoginError(message, errorCode ?: SFInternalLoginError);
    }
    if (data.length && !answer) return SFLoginError(@"Apple's answer couldn't be read. Please try again later.", SFInternalLoginError);
    return nil;
}

- (void)perform:(NSURLRequest *)request step:(NSString *)step completion:(SFTwoFactorResultBlock)completion {
    if (!request) { completion(SFLoginError(@"The sign-in session is incomplete. Please sign in again.", SFInternalLoginError)); return; }
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSError *problem = [self twoFactorError:data response:response error:error];
        SFLogEvent(problem ? SFLogLevelError : SFLogLevelInfo, @"sign-in · %@ %@", step, problem ? [NSString stringWithFormat:@"failed (%ld)", (long)problem.code] : @"done");
        completion(problem);
    }] resume];
}

/// Finds which trusted phone number to use, from the secondary-auth page.
- (void)findTrustedPhone:(NSString *)identity token:(NSString *)token completion:(void (^)(NSError *, NSDictionary *))completion {
    NSMutableURLRequest *request = [self twoFactorRequest:self.endpoints[@"secondaryAuth"] ?: @"https://gsa.apple.com/auth" identity:identity token:token json:YES];
    if (!request) { completion(SFLoginError(@"The sign-in session is incomplete. Please sign in again.", SFInternalLoginError), nil); return; }
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSError *problem = [self twoFactorError:data response:response error:error];
        if (problem) { completion(problem, nil); return; }
        for (NSDictionary *layer in SFAnswerLayers(SFReadAnswer(data))) {
            NSMutableArray *phones = [NSMutableArray array];
            for (NSString *key in @[@"trustedPhoneNumber", @"phoneNumber"]) if (SFAs(layer[key], [NSDictionary class])) [phones addObject:layer[key]];
            for (id phone in SFAs(layer[@"trustedPhoneNumbers"], [NSArray class])) if ([phone isKindOfClass:[NSDictionary class]]) [phones addObject:phone];
            for (NSDictionary *phone in phones) {
                id rawID = phone[@"id"] ?: phone[@"phoneNumber.id"];
                NSString *phoneID = [rawID isKindOfClass:[NSString class]] ? rawID : ([rawID respondsToSelector:@selector(stringValue)] ? [rawID stringValue] : nil);
                if (!phoneID.length) continue;
                NSString *mode = SFAs(phone[@"pushMode"] ?: phone[@"mode"] ?: layer[@"mode"], [NSString class]);
                completion(nil, @{ @"id": phoneID, @"mode": [mode.lowercaseString isEqualToString:@"voice"] ? @"voice" : @"sms" });
                return;
            }
        }
        completion(SFLoginError(@"Apple didn't list a trusted phone number to use.", SFInternalLoginError), nil);
    }] resume];
}

- (void)requestTwoFactorCodeWithUserIdentity:(NSString *)identity idmsToken:(NSString *)token mode:(int)mode completion:(SFTwoFactorResultBlock)completion {
    if (mode == SFInternalLogin2FARequiredTrustedDeviceError) {
        self.trustedPhone = nil;
        NSString *url = self.endpoints[@"trustedDeviceSecondaryAuth"] ?: @"https://gsa.apple.com/auth/verify/trusteddevice";
        [self perform:[self twoFactorRequest:url identity:identity token:token json:NO] step:@"code to trusted device" completion:completion];
        return;
    }
    if (mode != SFInternalLogin2FARequiredSecondaryAuthError) {
        completion(SFLoginError(@"Apple asked for an unsupported kind of two-factor check.", SFInternalLoginError));
        return;
    }
    [self findTrustedPhone:identity token:token completion:^(NSError *error, NSDictionary *phone) {
        if (error) { completion(error); return; }
        self.trustedPhone = phone;
        NSMutableURLRequest *request = [self twoFactorRequest:@"https://gsa.apple.com/auth/verify/phone" identity:identity token:token json:YES];
        request.HTTPMethod = @"PUT";
        request.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{ @"phoneNumber": @{ @"id": @([phone[@"id"] integerValue]) }, @"mode": phone[@"mode"] } options:0 error:nil];
        [self perform:request step:@"code to phone" completion:completion];
    }];
}

- (void)submitTwoFactorCode:(NSString *)code userIdentity:(NSString *)identity idmsToken:(NSString *)token mode:(int)mode completion:(SFTwoFactorResultBlock)completion {
    NSString *digits = SFSixDigits(code ?: @"");
    if (digits.length != 6) { completion(SFLoginError(@"The verification code must be exactly six digits.", SFInternalLoginInvalid2FAFormatError)); return; }

    if (mode != SFInternalLogin2FARequiredSecondaryAuthError) {
        NSString *url = self.endpoints[@"validateCode"] ?: [SFGSService stringByAppendingString:@"/validate"];
        NSMutableURLRequest *request = [self twoFactorRequest:url identity:identity token:token json:NO];
        [request setValue:digits forHTTPHeaderField:@"security-code"];
        [self perform:request step:@"code check" completion:completion];
        return;
    }

    void (^submit)(NSDictionary *) = ^(NSDictionary *phone) {
        NSMutableURLRequest *request = [self twoFactorRequest:@"https://gsa.apple.com/auth/verify/phone/securitycode" identity:identity token:token json:YES];
        request.HTTPMethod = @"POST";
        request.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{ @"securityCode": @{ @"code": digits },
                                                                      @"phoneNumber": @{ @"id": @([phone[@"id"] integerValue]) },
                                                                      @"mode": phone[@"mode"] } options:0 error:nil];
        [self perform:request step:@"phone code check" completion:completion];
    };
    if (self.trustedPhone) { submit(self.trustedPhone); return; }
    [self findTrustedPhone:identity token:token completion:^(NSError *error, NSDictionary *phone) {
        if (error) { completion(error); return; }
        self.trustedPhone = phone;
        submit(phone);
    }];
}

@end
