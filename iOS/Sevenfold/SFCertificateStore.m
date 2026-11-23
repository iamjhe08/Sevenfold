//
//  SFCertificateStore.m
//  Sevenfold
//

#import "SFCertificateStore.h"
#import "SFLocalization.h"
#import "SFDevice.h"
#import "SFLog.h"
#import "SFAppleServices.h"
#import "SFProvisioning.h"
#import "SFResources.h"
#import "SAMKeychain.h"
#import "SFApplication.h"
#import "SFCodeSignature.h"
#import "SFApplicationDatabase.h"
#import <CommonCrypto/CommonCrypto.h>
#import <UIKit/UIKit.h>

static NSString *const SFKeychainService = @"com.t4mag0.sevenfold";
static NSString *const SFUsersKey = @"sfCertificateUsers";       // serial -> [ {model, role, date} ]
static NSString *const SFSharedCountKey = @"sfCertificateSharedCount";

static NSError *SFError(NSString *message) {
    return [NSError errorWithDomain:@"com.t4mag0.sevenfold.certificate" code:1 userInfo:@{ NSLocalizedDescriptionKey: message }];
}

static NSDate *SFParseAppleDate(id value) {
    if (![value isKindOfClass:[NSString class]]) return [value isKindOfClass:[NSDate class]] ? value : nil;
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    for (NSString *format in @[@"yyyy-MM-dd'T'HH:mm:ss'Z'", @"yyyy-MM-dd'T'HH:mm:ss.SSSZ", @"yyyy-MM-dd'T'HH:mm:ssZ"]) {
        formatter.dateFormat = format;
        NSDate *date = [formatter dateFromString:value];
        if (date) return date;
    }
    return nil;
}

@implementation SFCertificate

- (NSString *)toolName {
    if (self.madeBySevenfold) return @"Sevenfold";
    NSString *name = self.machineName ?: @"";
    NSString *lower = name.lowercaseString;
    if ([lower containsString:@"iloader"]) return @"iloader";
    if ([lower containsString:@"sidestore"]) return @"SideStore";
    if ([lower containsString:@"altstore"]) return @"AltStore";
    if ([lower containsString:@"sideloadly"]) return @"Sideloadly";
    if ([lower containsString:@"cydia"]) return @"Cydia Impactor";
    return SFL(@"Another tool");
}

- (NSString *)creatorName {
    NSString *model = [SFDevice modelFromCertificateMachineName:self.machineName];
    if (model) return model;
    NSString *name = self.machineName ?: @"";
    NSString *lower = name.lowercaseString;
    // Computer tools put their own name here instead of a device name.
    if ([lower containsString:@"iloader"] || [lower containsString:@"altstore"] || [lower containsString:@"sidestore"] || [lower containsString:@"sideloadly"])
        return SFL(@"A computer");
    if ([name isEqualToString:@"iPhone"] || [name isEqualToString:@"iPad"])
        return [NSString stringWithFormat:SFL(@"An %@ (model hidden by iOS)"), name];
    return name.length > 0 ? name : SFL(@"Unknown device");
}

- (NSArray<NSString *> *)usedByDescriptions {
    NSMutableArray *result = [NSMutableArray array];
    if (self.usedByThisDevice)
        [result addObject:[NSString stringWithFormat:SFL(@"This iPhone (%@)"), [SFDevice modelName]]];
    NSArray *records = [[NSUserDefaults standardUserDefaults] dictionaryForKey:SFUsersKey][self.serialNumber ?: @""];
    for (NSDictionary *record in records) {
        NSString *model = record[@"model"];
        if ([record[@"role"] isEqualToString:@"self"] || model.length == 0) continue;
        if (![result containsObject:model]) [result addObject:model];
    }
    if ([self.serialNumber isEqualToString:[[NSUserDefaults standardUserDefaults] stringForKey:@"sfActiveCertificateSerial"]]) {
        NSInteger shared = [SFCertificateStore sharedWithCount];
        // Models not already listed (e.g. recorded when importing) among the other registered iPhones.
        NSMutableArray *candidates = [NSMutableArray array];
        for (NSString *model in self.otherRegisteredModels)
            if (![result containsObject:model] && ![candidates containsObject:model]) [candidates addObject:model];
        NSInteger alreadyNamed = (NSInteger)result.count - (self.usedByThisDevice ? 1 : 0);
        NSInteger unnamed = MAX(shared - alreadyNamed, 0);
        if (unnamed > 0 && candidates.count > 0 && (NSInteger)candidates.count <= unnamed) {
            // Every other registered iPhone must be one this certificate was shared with.
            for (NSString *model in candidates) [result addObject:[model stringByAppendingString:SFL(@" (shared)")]];
            unnamed -= candidates.count;
        }
        if (unnamed > 0)
            [result addObject:unnamed == 1 ? SFL(@"1 other iPhone you shared with") : [NSString stringWithFormat:SFL(@"%ld other iPhones you shared with"), (long)unnamed]];
    }
    return result;
}

@end

@implementation SFRegisteredDevice
@end

@implementation SFCertificateStore

+ (void)withSession:(void (^)(NSError *error))block {
    NSString *username = [SFResources getUsername];
    NSString *password = [SFResources getPassword];
    if (username.length == 0 || password.length == 0) {
        block(SFError(SFL(@"Sign in first.")));
        return;
    }
    [[SFAppleServices sharedInstance] ensureSessionWithIdentity:username gsToken:password andCompletionHandler:^(NSError *error, NSDictionary *plist) {
        block(error);
    }];
}

+ (NSString *)thisMachineId {
    return [SAMKeychain passwordForService:SFKeychainService account:@"uuid"];
}

+ (NSString *)normalisedSerial:(NSString *)serial {
    NSString *upper = [[serial uppercaseString] stringByReplacingOccurrencesOfString:@":" withString:@""];
    while ([upper hasPrefix:@"0"] && upper.length > 1) upper = [upper substringFromIndex:1];
    return upper;
}

/// Serial number -> names of installed apps actually signed with that certificate
/// (read from each app's code signature).
+ (NSDictionary<NSString *, NSArray<NSString *> *> *)appsBySerialOnThisDevice {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    NSString *teamID = [SFResources getTeamID];
    if (teamID.length == 0) return result;
    for (SFApplication *app in [[SFApplicationDatabase sharedInstance] getAllApplicationsForTeamID:teamID]) {
        NSURL *bundleURL = app.locationOfApplicationOnFilesystem;
        if (!bundleURL) continue;
        NSString *serial = SFSigningCertificateSerialForApp(bundleURL);
        if (serial.length == 0) continue;
        NSString *key = [self normalisedSerial:serial];
        NSMutableArray *names = result[key] ?: [NSMutableArray array];
        NSString *name = app.applicationName ?: app.bundleIdentifier ?: @"App";
        if (![names containsObject:name]) [names addObject:name];
        result[key] = names;
    }
    return result;
}

+ (void)fetchCertificatesWithCompletion:(void (^)(NSArray<SFCertificate *> *, NSError *))completion {
    [self withSession:^(NSError *sessionError) {
        if (sessionError) { dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, sessionError); }); return; }
        [[SFAppleServices sharedInstance] listAllDevelopmentCertificatesWithFiltering:NO teamID:[SFResources getTeamID] systemType:SFSystemTypeiOS withCompletionHandler:^(NSError *error, NSDictionary *dictionary) {
            NSMutableArray *certificates = [NSMutableArray array];
            NSString *machineId = [self thisMachineId];
            NSDictionary *appsBySerial = [self appsBySerialOnThisDevice];
            NSString *activeSerial = [[NSUserDefaults standardUserDefaults] stringForKey:@"sfActiveCertificateSerial"];
            for (NSDictionary *entry in dictionary[@"data"]) {
                if (![entry isKindOfClass:[NSDictionary class]]) continue;
                NSDictionary *attributes = entry[@"attributes"];
                SFCertificate *certificate = [SFCertificate new];
                certificate.identifier = [entry[@"id"] description] ?: @"";
                id serial = attributes[@"serialNumber"];
                certificate.serialNumber = [serial isKindOfClass:[NSString class]] ? serial : @"";
                id name = attributes[@"machineName"];
                certificate.machineName = [name isKindOfClass:[NSString class]] ? name : @"";
                id mid = attributes[@"machineId"];
                certificate.machineId = [mid isKindOfClass:[NSString class]] ? mid : @"";
                certificate.expirationDate = SFParseAppleDate(attributes[@"expirationDate"]);
                certificate.madeBySevenfold = [SFDevice modelFromCertificateMachineName:certificate.machineName] != nil;
                certificate.appsSignedHere = appsBySerial[[self normalisedSerial:certificate.serialNumber]] ?: @[];
                certificate.usedByThisDevice = (machineId.length > 0 && [certificate.machineId isEqualToString:machineId]) ||
                                               (activeSerial.length > 0 && [certificate.serialNumber isEqualToString:activeSerial]);
                [certificates addObject:certificate];
            }
            [certificates sortUsingComparator:^NSComparisonResult(SFCertificate *a, SFCertificate *b) {
                if (a.usedByThisDevice != b.usedByThisDevice) return a.usedByThisDevice ? NSOrderedAscending : NSOrderedDescending;
                BOOL aHere = a.appsSignedHere.count > 0, bHere = b.appsSignedHere.count > 0;
                if (aHere != bHere) return aHere ? NSOrderedAscending : NSOrderedDescending;
                return [b.expirationDate ?: [NSDate distantPast] compare:a.expirationDate ?: [NSDate distantPast]];
            }];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(error ? nil : certificates, error); });
        }];
    }];
}

+ (void)fetchRegisteredDevicesWithCompletion:(void (^)(NSArray<SFRegisteredDevice *> *, NSError *))completion {
    [self withSession:^(NSError *sessionError) {
        if (sessionError) { dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, sessionError); }); return; }
        [[SFAppleServices sharedInstance] listDevicesForTeamID:[SFResources getTeamID] systemType:SFSystemTypeiOS withCompletionHandler:^(NSError *error, NSDictionary *plist) {
            NSString *thisUDID = nil;
            Class gestalt = NSClassFromString(@"AKDevice");
            if ([gestalt respondsToSelector:@selector(currentDevice)]) {
                id device = [gestalt performSelector:@selector(currentDevice)];
                if ([device respondsToSelector:@selector(uniqueDeviceIdentifier)])
                    thisUDID = [device performSelector:@selector(uniqueDeviceIdentifier)];
            }
            NSArray *entries = plist[@"devices"] ?: plist[@"data"];
            NSMutableArray *devices = [NSMutableArray array];
            for (NSDictionary *entry in entries) {
                if (![entry isKindOfClass:[NSDictionary class]]) continue;
                NSDictionary *attributes = [entry[@"attributes"] isKindOfClass:[NSDictionary class]] ? entry[@"attributes"] : entry;
                SFRegisteredDevice *device = [SFRegisteredDevice new];
                device.name = [attributes[@"name"] description] ?: SFL(@"Device");
                id model = attributes[@"model"] ?: attributes[@"deviceClass"];
                device.model = [model isKindOfClass:[NSString class]] ? model : @"";
                device.udid = [(attributes[@"deviceNumber"] ?: attributes[@"udid"]) description] ?: @"";
                device.isThisDevice = thisUDID.length > 0 && [device.udid caseInsensitiveCompare:thisUDID] == NSOrderedSame;
                [devices addObject:device];
            }
            dispatch_async(dispatch_get_main_queue(), ^{ completion(error ? nil : devices, error); });
        }];
    }];
}

+ (void)revokeCertificate:(SFCertificate *)certificate completion:(void (^)(NSError *))completion {
    [self withSession:^(NSError *sessionError) {
        if (sessionError) { dispatch_async(dispatch_get_main_queue(), ^{ completion(sessionError); }); return; }
        [[SFAppleServices sharedInstance] revokeCertificateForIdentifier:certificate.identifier andTeamID:[SFResources getTeamID] systemType:SFSystemTypeiOS withCompletionHandler:^(NSError *error, NSDictionary *plist) {
            if (!error) {
                SFLogEvent(SFLogLevelInfo, @"revoked certificate from %@", certificate.creatorName);
                [SFProvisioning sevenfoldResetCertificateCache];
            }
            dispatch_async(dispatch_get_main_queue(), ^{ completion(error); });
        }];
    }];
}

+ (void)addUserRecord:(NSDictionary *)record forSerial:(NSString *)serial {
    if (serial.length == 0) return;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *all = [[defaults dictionaryForKey:SFUsersKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableArray *list = [all[serial] mutableCopy] ?: [NSMutableArray array];
    for (NSDictionary *existing in [list copy])
        if ([existing[@"model"] isEqualToString:record[@"model"]] && [existing[@"role"] isEqualToString:record[@"role"]]) [list removeObject:existing];
    [list addObject:record];
    all[serial] = list;
    [defaults setObject:all forKey:SFUsersKey];
}

+ (void)recordThisDeviceUsesActiveCertificate {
    NSString *serial = [[NSUserDefaults standardUserDefaults] stringForKey:@"sfActiveCertificateSerial"];
    [self addUserRecord:@{ @"model": [SFDevice modelName], @"role": @"self", @"date": [NSDate date] } forSerial:serial];
}

+ (BOOL)hasPrivateKey {
    return [SAMKeychain passwordForService:SFKeychainService account:@"privateKey"].length > 0;
}

+ (NSInteger)sharedWithCount {
    return [[NSUserDefaults standardUserDefaults] integerForKey:SFSharedCountKey];
}

// MARK: - Encryption (PBKDF2-SHA256 + AES-256-CBC + HMAC-SHA256)

+ (NSData *)deriveKeyFromPassword:(NSString *)password salt:(NSData *)salt {
    NSMutableData *key = [NSMutableData dataWithLength:64];
    NSData *pw = [password dataUsingEncoding:NSUTF8StringEncoding];
    CCKeyDerivationPBKDF(kCCPBKDF2, pw.bytes, pw.length, salt.bytes, salt.length, kCCPRFHmacAlgSHA256, 150000, key.mutableBytes, key.length);
    return key;
}

+ (NSData *)random:(size_t)length {
    NSMutableData *data = [NSMutableData dataWithLength:length];
    (void)SecRandomCopyBytes(kSecRandomDefault, length, data.mutableBytes);
    return data;
}

+ (NSData *)aes:(CCOperation)op data:(NSData *)data key:(NSData *)key iv:(NSData *)iv {
    size_t outLength = 0;
    NSMutableData *out = [NSMutableData dataWithLength:data.length + kCCBlockSizeAES128];
    CCCryptorStatus status = CCCrypt(op, kCCAlgorithmAES, kCCOptionPKCS7Padding, key.bytes, kCCKeySizeAES256, iv.bytes,
                                     data.bytes, data.length, out.mutableBytes, out.length, &outLength);
    if (status != kCCSuccess) return nil;
    out.length = outLength;
    return out;
}

+ (NSData *)hmac:(NSData *)data key:(NSData *)key {
    NSMutableData *mac = [NSMutableData dataWithLength:CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, key.bytes, key.length, data.bytes, data.length, mac.mutableBytes);
    return mac;
}

+ (NSURL *)exportCertificateWithPassword:(NSString *)password error:(NSError **)error {
    NSString *privateKey = [SAMKeychain passwordForService:SFKeychainService account:@"privateKey"];
    NSString *teamID = [SAMKeychain passwordForService:SFKeychainService account:@"privateKeyTeamID"];
    NSString *machineId = [self thisMachineId];
    NSString *serial = [[NSUserDefaults standardUserDefaults] stringForKey:@"sfActiveCertificateSerial"] ?: @"";
    if (privateKey.length == 0 || teamID.length == 0 || machineId.length == 0) {
        if (error) *error = SFError(SFL(@"This iPhone has no certificate yet. Sign an app once, then share."));
        return nil;
    }
    if (password.length < 4) {
        if (error) *error = SFError(SFL(@"Use a password of at least 4 characters."));
        return nil;
    }

    NSDictionary *payload = @{
        @"privateKey": privateKey,
        @"teamID": teamID,
        @"machineId": machineId,
        @"serial": serial,
        @"senderModel": [SFDevice modelName],
        @"created": @([[NSDate date] timeIntervalSince1970]),
    };
    NSData *plain = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    NSData *salt = [self random:16];
    NSData *iv = [self random:16];
    NSData *keys = [self deriveKeyFromPassword:password salt:salt];
    NSData *encKey = [keys subdataWithRange:NSMakeRange(0, 32)];
    NSData *macKey = [keys subdataWithRange:NSMakeRange(32, 32)];
    NSData *cipher = [self aes:kCCEncrypt data:plain key:encKey iv:iv];
    NSMutableData *signedPart = [NSMutableData dataWithData:iv];
    [signedPart appendData:cipher];
    NSData *mac = [self hmac:signedPart key:macKey];

    NSDictionary *file = @{
        @"format": @"sevenfold-cert",
        @"v": @1,
        @"team": teamID,
        @"from": [SFDevice modelName],
        @"salt": [salt base64EncodedStringWithOptions:0],
        @"iv": [iv base64EncodedStringWithOptions:0],
        @"data": [cipher base64EncodedStringWithOptions:0],
        @"mac": [mac base64EncodedStringWithOptions:0],
    };
    NSData *json = [NSJSONSerialization dataWithJSONObject:file options:NSJSONWritingPrettyPrinted error:nil];
    NSString *name = [NSString stringWithFormat:@"Sevenfold certificate (%@).sevenfold-cert", [SFDevice modelName]];
    NSURL *url = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:name];
    if (![json writeToURL:url options:NSDataWritingAtomic | NSDataWritingFileProtectionComplete error:error]) return nil;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setInteger:MAX([self sharedWithCount], 1) forKey:SFSharedCountKey];
    SFLogEvent(SFLogLevelInfo, @"certificate exported for sharing");
    return url;
}

+ (BOOL)importCertificateAtURL:(NSURL *)url password:(NSString *)password summary:(NSString **)summary error:(NSError **)error {
    BOOL scoped = [url startAccessingSecurityScopedResource];
    NSData *json = [NSData dataWithContentsOfURL:url];
    if (scoped) [url stopAccessingSecurityScopedResource];
    NSDictionary *file = json ? [NSJSONSerialization JSONObjectWithData:json options:0 error:nil] : nil;
    if (![file isKindOfClass:[NSDictionary class]] || ![file[@"format"] isEqual:@"sevenfold-cert"]) {
        if (error) *error = SFError(SFL(@"That isn't a Sevenfold certificate file."));
        return NO;
    }
    NSData *salt = [[NSData alloc] initWithBase64EncodedString:file[@"salt"] ?: @"" options:0];
    NSData *iv = [[NSData alloc] initWithBase64EncodedString:file[@"iv"] ?: @"" options:0];
    NSData *cipher = [[NSData alloc] initWithBase64EncodedString:file[@"data"] ?: @"" options:0];
    NSData *mac = [[NSData alloc] initWithBase64EncodedString:file[@"mac"] ?: @"" options:0];
    if (salt.length != 16 || iv.length != 16 || cipher.length == 0 || mac.length != CC_SHA256_DIGEST_LENGTH) {
        if (error) *error = SFError(SFL(@"The certificate file is damaged."));
        return NO;
    }
    NSData *keys = [self deriveKeyFromPassword:password salt:salt];
    NSMutableData *signedPart = [NSMutableData dataWithData:iv];
    [signedPart appendData:cipher];
    if (![[self hmac:signedPart key:[keys subdataWithRange:NSMakeRange(32, 32)]] isEqualToData:mac]) {
        if (error) *error = SFError(SFL(@"Wrong password."));
        return NO;
    }
    NSData *plain = [self aes:kCCDecrypt data:cipher key:[keys subdataWithRange:NSMakeRange(0, 32)] iv:iv];
    NSDictionary *payload = plain ? [NSJSONSerialization JSONObjectWithData:plain options:0 error:nil] : nil;
    NSString *privateKey = payload[@"privateKey"];
    NSString *teamID = payload[@"teamID"];
    NSString *machineId = payload[@"machineId"];
    if (privateKey.length == 0 || teamID.length == 0 || machineId.length == 0) {
        if (error) *error = SFError(SFL(@"The certificate file is damaged."));
        return NO;
    }
    NSString *myTeam = [SFResources getTeamID];
    if (myTeam.length > 0 && ![myTeam isEqualToString:teamID]) {
        if (error) *error = SFError(SFL(@"This certificate belongs to a different Apple ID. Sign in with the same Apple ID on both iPhones."));
        return NO;
    }

    [SAMKeychain setPassword:privateKey forService:SFKeychainService account:@"privateKey"];
    [SAMKeychain setPassword:teamID forService:SFKeychainService account:@"privateKeyTeamID"];
    [SAMKeychain setPassword:machineId forService:SFKeychainService account:@"uuid"];

    NSString *serial = payload[@"serial"];
    if (serial.length > 0) {
        [[NSUserDefaults standardUserDefaults] setObject:serial forKey:@"sfActiveCertificateSerial"];
        NSString *sender = payload[@"senderModel"] ?: SFL(@"Your other iPhone");
        [self addUserRecord:@{ @"model": sender, @"role": @"sender", @"date": [NSDate date] } forSerial:serial];
        [self recordThisDeviceUsesActiveCertificate];
    }
    [SFProvisioning sevenfoldResetCertificateCache];
    SFLogEvent(SFLogLevelOK, @"imported shared certificate from %@", payload[@"senderModel"] ?: SFL(@"another iPhone"));
    if (summary) *summary = [NSString stringWithFormat:SFL(@"This iPhone now signs with the certificate from your %@."), payload[@"senderModel"] ?: SFL(@"other iPhone")];
    return YES;
}

@end
