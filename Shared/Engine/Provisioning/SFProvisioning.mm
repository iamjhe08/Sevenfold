//
//  SFProvisioning.mm
//  Sevenfold
//
//  BY: T4MAG0
//
//  One profile request runs four steps, each a method below:
//    team         sign in and pick the team
//    certificate  find this iPhone's certificate (with its private key) or make a new one
//    App ID       create or update the App ID, its capabilities and app groups
//    profile      drop the old profile and fetch a fresh one
//

#import "SFProvisioning.h"
#import "SFDevice.h"
extern "C" {
#import "SFLog.h"
}
#import "SFSigning.h"
#import "SAMKeychain.h"
#import "SFResources.h"
#import <UIKit/UIKit.h>
extern "C" CFTypeRef MGCopyAnswer(CFStringRef property);

#include <openssl/pem.h>
#include <openssl/rsa.h>
#include <openssl/x509.h>
#include <memory>

// Keychain items. These names must not change, or existing certificates are lost.
static NSString *const SFKeychainService      = @"com.t4mag0.sevenfold";
static NSString *const SFKeychainPrivateKey   = @"privateKey";
static NSString *const SFKeychainKeyTeam      = @"privateKeyTeamID";
static NSString *const SFKeychainMachineID    = @"uuid";
static NSString *const SFDefaultsActiveSerial = @"sfActiveCertificateSerial";

typedef void (^SFCertificateResult)(NSError *error, NSString *privateKey, NSDictionary *certificate);
typedef void (^SFAppIDResult)(NSError *error, NSString *appIdId, NSDictionary *entitlements);

#pragma mark - Small helpers

static NSString *SFString(id value) {
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

static NSError *SFProvisionError(NSString *text) {
    text = text.length ? text : @"Apple returned an error without a message.";
    return [NSError errorWithDomain:NSCocoaErrorDomain code:-1 userInfo:@{
        NSLocalizedDescriptionKey: text,
        NSLocalizedFailureReasonErrorKey: text,
    }];
}

/// nil when the call worked; otherwise an error naming the step.
/// Old-style portal answers carry resultCode; v1 answers carry an "errors" array.
static NSError *SFCheck(NSString *step, NSError *transport, NSDictionary *plist) {
    if (transport) return SFProvisionError([NSString stringWithFormat:@"%@: %@", step, transport.localizedDescription]);
    id code = plist[@"resultCode"];
    if (code && [code intValue] != 0) {
        NSString *message = SFString(plist[@"userString"]) ?: SFString(plist[@"resultString"]) ?: [NSString stringWithFormat:@"code %d", [code intValue]];
        return SFProvisionError([NSString stringWithFormat:@"%@: %@", step, message]);
    }
    NSArray *errors = [plist[@"errors"] isKindOfClass:[NSArray class]] ? plist[@"errors"] : nil;
    if (errors.count) {
        NSDictionary *first = [errors.firstObject isKindOfClass:[NSDictionary class]] ? errors.firstObject : @{};
        NSString *message = SFString(first[@"detail"]) ?: SFString(first[@"title"]) ?: @"rejected";
        return SFProvisionError([NSString stringWithFormat:@"%@: %@", step, message]);
    }
    return nil;
}

static NSString *SFTeam(void) {
    return [[SFAppleServices sharedInstance] currentTeamID] ?: @"";
}

#pragma mark - Keys and certificates (OpenSSL)

struct SFBIOFree  { void operator()(BIO *p) const { BIO_free_all(p); } };
struct SFPKeyFree { void operator()(EVP_PKEY *p) const { EVP_PKEY_free(p); } };
struct SFX509Free { void operator()(X509 *p) const { X509_free(p); } };
struct SFReqFree  { void operator()(X509_REQ *p) const { X509_REQ_free(p); } };
struct SFBNFree   { void operator()(BIGNUM *p) const { BN_free(p); } };
typedef std::unique_ptr<BIO, SFBIOFree> SFBIO;
typedef std::unique_ptr<EVP_PKEY, SFPKeyFree> SFPKey;

static SFPKey SFReadPrivateKey(NSString *pem) {
    if (pem.length == 0) return SFPKey();
    SFBIO bio(BIO_new_mem_buf((void *)pem.UTF8String, -1));
    return SFPKey(bio ? PEM_read_bio_PrivateKey(bio.get(), NULL, NULL, NULL) : NULL);
}

/// YES when the PEM private key belongs to the certificate in these attributes.
static BOOL SFKeyFitsCertificate(NSString *pem, NSDictionary *attributes) {
    NSString *content = SFString(attributes[@"certificateContent"]);
    if (content.length == 0) return NO;
    NSData *der = [[NSData alloc] initWithBase64EncodedString:content options:NSDataBase64DecodingIgnoreUnknownCharacters];
    if (der.length == 0) return NO;
    SFPKey key = SFReadPrivateKey(pem);
    if (!key) return NO;
    const unsigned char *bytes = (const unsigned char *)der.bytes;
    std::unique_ptr<X509, SFX509Free> cert(d2i_X509(NULL, &bytes, (long)der.length));
    if (!cert) return NO;
    SFPKey publicKey(X509_get_pubkey(cert.get()));
    return publicKey && EVP_PKEY_cmp(key.get(), publicKey.get()) == 1;
}

static NSData *SFBIOData(BIO *bio) {
    char *data = NULL;
    long length = BIO_get_mem_data(bio, &data);
    return (data && length > 0) ? [NSData dataWithBytes:data length:(NSUInteger)length] : nil;
}

/// A new 2048-bit RSA key and a CSR for it, both PEM. Returns NO if OpenSSL fails.
static BOOL SFMakeSigningRequest(NSData **keyPEM, NSData **requestPEM) {
    std::unique_ptr<BIGNUM, SFBNFree> exponent(BN_new());
    if (!exponent || BN_set_word(exponent.get(), RSA_F4) != 1) return NO;

    RSA *rsa = RSA_new();
    if (!rsa || RSA_generate_key_ex(rsa, 2048, exponent.get(), NULL) != 1) { RSA_free(rsa); return NO; }
    SFPKey key(EVP_PKEY_new());
    if (!key || EVP_PKEY_assign_RSA(key.get(), rsa) != 1) { RSA_free(rsa); return NO; }   // key owns rsa from here

    std::unique_ptr<X509_REQ, SFReqFree> request(X509_REQ_new());
    if (!request || X509_REQ_set_version(request.get(), 0) != 1) return NO;
    X509_NAME *subject = X509_REQ_get_subject_name(request.get());
    const char *fields[][2] = { {"C", "PH"}, {"O", "Sevenfold"}, {"CN", "Sevenfold"} };
    for (auto &field : fields) {
        if (X509_NAME_add_entry_by_txt(subject, field[0], MBSTRING_ASC, (const unsigned char *)field[1], -1, -1, 0) != 1) return NO;
    }
    if (X509_REQ_set_pubkey(request.get(), key.get()) != 1) return NO;
    if (X509_REQ_sign(request.get(), key.get(), EVP_sha256()) <= 0) return NO;

    SFBIO requestBIO(BIO_new(BIO_s_mem())), keyBIO(BIO_new(BIO_s_mem()));
    if (!requestBIO || !keyBIO) return NO;
    if (PEM_write_bio_X509_REQ(requestBIO.get(), request.get()) != 1) return NO;
    if (PEM_write_bio_RSAPrivateKey(keyBIO.get(), rsa, NULL, NULL, 0, NULL, NULL) != 1) return NO;   // rsa is still owned by key

    *requestPEM = SFBIOData(requestBIO.get());
    *keyPEM = SFBIOData(keyBIO.get());
    return *requestPEM && *keyPEM;
}

static NSDate *SFPortalDate(id value) {
    NSString *text = SFString(value);
    if (!text.length) return nil;
    static NSDateFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [NSDateFormatter new];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
        formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
    });
    @synchronized (formatter) { return [formatter dateFromString:text]; }
}

#pragma mark - Certificate memory for one signing run

// Checking the certificate once per run is enough: it is reused for 10 minutes.
static NSString *SFRememberedTeam;
static NSString *SFRememberedKey;
static NSDictionary *SFRememberedCertificate;
static NSDate *SFRememberedAt;
static SFSystemType SFRememberedSystem;
static NSMutableArray *SFCertificateWaiters;   // completions waiting on a certificate lookup in progress

@implementation SFProvisioning {
    NSString *_identity;
    NSString *_gsToken;
}

+ (void)sevenfoldResetCertificateCache {
    @synchronized (self) {
        SFRememberedAt = nil;
        SFRememberedKey = nil;
        SFRememberedCertificate = nil;
    }
}

+ (instancetype)provisionerWithCredentials:(NSString *)identity :(NSString *)gsToken {
    SFProvisioning *provisioner = [self new];
    provisioner->_identity = identity;
    provisioner->_gsToken = gsToken;
    return provisioner;
}

#pragma mark - Public

- (void)provisionDevice:(NSString *)udid name:(NSString *)name withTeamIDCheck:(NSString * (^)(NSArray *))teamIDCallback systemType:(SFSystemType)systemType andCallback:(void (^)(NSError *))completionHandler {
    [self prepareTeam:teamIDCallback completion:^(NSError *error) {
        if (error) { completionHandler(error); return; }
        [[SFAppleServices sharedInstance] addDevice:udid deviceName:name forTeamID:SFTeam() systemType:systemType withCompletionHandler:^(NSError *transport, NSDictionary *plist) {
            completionHandler(SFCheck(@"Register device", transport, plist));
        }];
    }];
}

- (void)revokeCertificatesWithTeamIDCheck:(NSString * (^)(NSArray *))teamIDCallback systemType:(SFSystemType)systemType andCallback:(void (^)(NSError *))completionHandler {
    [self prepareTeam:teamIDCallback completion:^(NSError *error) {
        if (error) { completionHandler(error); return; }
        SFAppleServices *apple = [SFAppleServices sharedInstance];
        [apple listAllDevelopmentCertificatesForTeamID:SFTeam() systemType:systemType withCompletionHandler:^(NSError *transport, NSDictionary *plist) {
            NSError *listError = SFCheck(@"List certificates", transport, plist);
            if (listError) { completionHandler(listError); return; }
            NSString *mine = [self machineIdentifier];
            NSString *certificateID = nil;
            for (NSDictionary *entry in plist[@"data"]) {
                if ([SFString(entry[@"attributes"][@"machineId"]) isEqualToString:mine]) { certificateID = SFString(entry[@"id"]); break; }
            }
            if (!certificateID) {
                SFLogEvent(SFLogLevelInfo, @"certificate · nothing to revoke for this iPhone");
                completionHandler(nil);
                return;
            }
            [apple revokeCertificateForIdentifier:certificateID andTeamID:SFTeam() systemType:systemType withCompletionHandler:^(NSError *revokeTransport, NSDictionary *result) {
                if (!revokeTransport) [SFProvisioning sevenfoldResetCertificateCache];
                completionHandler(revokeTransport);
            }];
        }];
    }];
}

- (void)downloadProvisioningProfileForApplicationIdentifier:(NSString *)identifier applicationName:(NSString *)applicationName binaryLocation:(NSString *)binaryLocation withTeamIDCheck:(NSString * (^)(NSArray *))teamIDCallback systemType:(SFSystemType)systemType andCallback:(void (^)(NSError *, NSData *, NSString *, NSDictionary *, NSDictionary *))completionHandler {
    void (^fail)(NSError *) = ^(NSError *error) { completionHandler(error, nil, nil, nil, nil); };

    [self prepareTeam:teamIDCallback completion:^(NSError *error) {
        if (error) { fail(error); return; }
        [self ensureThisDeviceRegisteredForSystem:systemType completion:^{
        [self certificateForSystem:systemType completion:^(NSError *certError, NSString *privateKey, NSDictionary *certificate) {
            if (certError) { fail(certError); return; }
            [self appIDFor:identifier name:applicationName binary:binaryLocation system:systemType completion:^(NSError *appError, NSString *appIdId, NSDictionary *entitlements) {
                if (appError) { fail(appError); return; }
                [self freshProfileFor:identifier appIdId:appIdId system:systemType completion:^(NSError *profileError, NSData *profile) {
                    if (profileError) { fail(profileError); return; }
                    completionHandler(nil, profile, privateKey, certificate, entitlements);
                }];
            }];
        }];
        }];
    }];
}

#pragma mark - Step 1b: this iPhone is still registered

static NSDate *SFDeviceCheckedAt;

/// Apple can drop a phone from the account's device list; profiles made after that
/// no longer include it and signing on it fails. Check once per run (at most every
/// 10 minutes) and register the phone again if it's missing. Never blocks signing.
- (void)ensureThisDeviceRegisteredForSystem:(SFSystemType)system completion:(void (^)(void))completion {
    if (system != SFSystemTypeiOS) { completion(); return; }
    @synchronized ([SFProvisioning class]) {
        if (SFDeviceCheckedAt && -SFDeviceCheckedAt.timeIntervalSinceNow < 600) { completion(); return; }
        SFDeviceCheckedAt = [NSDate date];
    }
    NSString *udid = CFBridgingRelease(MGCopyAnswer(CFSTR("UniqueDeviceID")));
    if (udid.length == 0) { completion(); return; }
    SFAppleServices *apple = [SFAppleServices sharedInstance];
    [apple listDevicesForTeamID:SFTeam() systemType:system withCompletionHandler:^(NSError *transport, NSDictionary *plist) {
        NSArray *entries = plist[@"devices"] ?: plist[@"data"];
        if (transport || ![entries isKindOfClass:[NSArray class]]) { completion(); return; }
        for (NSDictionary *entry in entries) {
            if (![entry isKindOfClass:[NSDictionary class]]) continue;
            NSDictionary *attributes = [entry[@"attributes"] isKindOfClass:[NSDictionary class]] ? entry[@"attributes"] : entry;
            NSString *number = SFString(attributes[@"deviceNumber"] ?: attributes[@"udid"]);
            if ([number caseInsensitiveCompare:udid] == NSOrderedSame) { completion(); return; }
        }
        SFLogEvent(SFLogLevelWarning, @"device · this iPhone was missing from the Apple ID's device list, registering it again");
        NSString *name = [UIDevice currentDevice].name ?: @"iPhone";
        [apple addDevice:udid deviceName:name forTeamID:SFTeam() systemType:system withCompletionHandler:^(NSError *addTransport, NSDictionary *result) {
            NSError *addError = SFCheck(@"Register device", addTransport, result);
            if (addError) SFLogEvent(SFLogLevelError, @"device · couldn't register this iPhone again: %@", addError.localizedDescription);
            else SFLogEvent(SFLogLevelOK, @"device · this iPhone is registered again");
            completion();
        }];
    }];
}

#pragma mark - Step 1: team

- (void)prepareTeam:(NSString * (^)(NSArray *))teamCheck completion:(void (^)(NSError *))completion {
    SFAppleServices *apple = [SFAppleServices sharedInstance];
    [apple ensureSessionWithIdentity:_identity gsToken:_gsToken andCompletionHandler:^(NSError *error, NSDictionary *plist) {
        if (error) { completion(error); return; }
        NSString *reason = SFString(plist[@"reason"]);
        if (![reason isEqualToString:@"authenticated"]) {
            completion(SFProvisionError([NSString stringWithFormat:@"Sign-in: %@ %@", reason ?: @"", SFString(plist[@"userString"]) ?: @""]));
            return;
        }
        [apple updateCurrentTeamIDWithTeamIDCheck:teamCheck andCallback:^(NSError *teamError, NSString *teamID) {
            if (teamError) { completion(SFProvisionError([@"Choosing the team: " stringByAppendingString:teamError.localizedDescription ?: @""])); return; }
            if (teamID.length == 0) { completion(SFProvisionError(@"This Apple ID has no developer team.")); return; }
            completion(nil);
        }];
    }];
}

#pragma mark - Step 2: certificate

- (NSString *)machineName {
#if TARGET_OS_SIMULATOR
    return @"Simulator";
#else
    return [SFDevice certificateMachineName];   // "Sevenfold · <model>"
#endif
}

/// A UUID kept in the keychain that identifies this iPhone on its certificate.
- (NSString *)machineIdentifier {
    NSString *uuid = [SAMKeychain passwordForService:SFKeychainService account:SFKeychainMachineID];
    if (uuid.length == 0) {
        uuid = [NSUUID UUID].UUIDString;
        [SAMKeychain setPassword:uuid forService:SFKeychainService account:SFKeychainMachineID];
    }
    return uuid;
}

- (void)certificateForSystem:(SFSystemType)system completion:(SFCertificateResult)completion {
    NSString *team = SFTeam();
    @synchronized ([SFProvisioning class]) {
        if (SFRememberedAt && -SFRememberedAt.timeIntervalSinceNow < 600 && SFRememberedSystem == system &&
            [SFRememberedTeam isEqualToString:team] && SFRememberedKey.length && SFRememberedCertificate) {
            completion(nil, SFRememberedKey, SFRememberedCertificate);
            return;
        }
        // Apps signed together must never look for (or make) a certificate at the same time:
        // the first one does it and the others wait for its answer.
        if (SFCertificateWaiters) { [SFCertificateWaiters addObject:[completion copy]]; return; }
        SFCertificateWaiters = [NSMutableArray arrayWithObject:[completion copy]];
    }
    [self findOrMakeCertificateForSystem:system completion:^(NSError *error, NSString *privateKey, NSDictionary *certificate) {
        NSArray *waiters;
        @synchronized ([SFProvisioning class]) {
            waiters = SFCertificateWaiters;
            SFCertificateWaiters = nil;
            if (error) {
                SFRememberedAt = nil;
            } else {
                SFRememberedTeam = team;
                SFRememberedKey = privateKey;
                SFRememberedCertificate = certificate;
                SFRememberedSystem = system;
                SFRememberedAt = [NSDate date];
            }
        }
        NSString *serial = SFString(certificate[@"serialNumber"]);
        if (!error && serial) [[NSUserDefaults standardUserDefaults] setObject:serial forKey:SFDefaultsActiveSerial];
        for (SFCertificateResult waiter in waiters) waiter(error, privateKey, certificate);
    }];
}

/*
 Which certificate this iPhone signs with:
 - one whose public key matches the private key stored here (this is how two iPhones share one
   certificate: the second one imports the key), or
 - one carrying this iPhone's machine ID.
 A certificate with this iPhone's ID but whose key doesn't match the stored one is skipped and
 left alone: another device may hold its key.
 If the chosen one is expired, or there is no usable key here, it is revoked and a new one made.
*/
- (void)findOrMakeCertificateForSystem:(SFSystemType)system completion:(SFCertificateResult)completion {
    SFAppleServices *apple = [SFAppleServices sharedInstance];
    NSString *team = SFTeam();
    [apple listAllDevelopmentCertificatesForTeamID:team systemType:system withCompletionHandler:^(NSError *transport, NSDictionary *plist) {
        NSError *listError = SFCheck(@"List certificates", transport, plist);
        if (listError) { completion(listError, nil, nil); return; }

        NSString *storedKey = [SAMKeychain passwordForService:SFKeychainService account:SFKeychainPrivateKey];
        BOOL keyIsForThisTeam = [team isEqualToString:[SAMKeychain passwordForService:SFKeychainService account:SFKeychainKeyTeam]];
        BOOL keyReadable = SFReadPrivateKey(storedKey) != nullptr;
        NSString *mine = [self machineIdentifier];

        NSDictionary *chosen = nil;
        NSString *chosenID = nil;
        BOOL usable = NO;
        for (NSDictionary *entry in plist[@"data"]) {
            NSDictionary *attributes = [entry[@"attributes"] isKindOfClass:[NSDictionary class]] ? entry[@"attributes"] : nil;
            NSString *name = SFString(attributes[@"machineName"]);
            if (name.length == 0) continue;
            NSString *machineID = SFString(attributes[@"machineId"]);
            BOOL isMine = [machineID isEqualToString:mine];
            BOOL keyFits = keyIsForThisTeam && SFKeyFitsCertificate(storedKey, attributes);

            if (isMine && !keyFits && keyIsForThisTeam && keyReadable && SFString(attributes[@"certificateContent"]).length) {
                SFLogEvent(SFLogLevelInfo, @"certificate · skipping %@: the key here belongs to another certificate", SFString(entry[@"id"]) ?: @"?");
                continue;
            }
            if (!(isMine || keyFits)) continue;

            chosen = attributes;
            chosenID = SFString(entry[@"id"]);
            // Shared certificate made on another iPhone: adopt its machine ID so later runs find it directly.
            if (keyFits && machineID.length && !isMine)
                [SAMKeychain setPassword:machineID forService:SFKeychainService account:SFKeychainMachineID];
            NSDate *expires = SFPortalDate(attributes[@"expirationDate"]);
            usable = !(expires && [expires compare:[NSDate date]] == NSOrderedAscending);
            break;
        }

        BOOL haveKey = storedKey.length > 0 && keyIsForThisTeam;
        if (chosen && usable && haveKey) {
            SFLogEvent(SFLogLevelInfo, @"certificate · using %@", SFString(chosen[@"machineName"]) ?: @"existing certificate");
            completion(nil, storedKey, chosen);
            return;
        }

        void (^makeNew)(void) = ^{ [self makeCertificateForSystem:system completion:completion]; };
        if (!chosen) { makeNew(); return; }

        SFLogEvent(SFLogLevelInfo, @"certificate · revoking %@ (%@)", chosenID ?: @"?", haveKey ? @"expired" : @"no private key on this iPhone");
        [apple revokeCertificateForIdentifier:chosenID andTeamID:team systemType:system withCompletionHandler:^(NSError *revokeError, NSDictionary *result) {
            if (revokeError) { completion(revokeError, nil, nil); return; }
            makeNew();
        }];
    }];
}

- (void)makeCertificateForSystem:(SFSystemType)system completion:(SFCertificateResult)completion {
    NSData *keyPEM = nil, *requestPEM = nil;
    if (!SFMakeSigningRequest(&keyPEM, &requestPEM)) {
        completion(SFProvisionError(@"Couldn't create a key for the new certificate."), nil, nil);
        return;
    }
    SFLogEvent(SFLogLevelInfo, @"certificate · requesting a new one");
    SFAppleServices *apple = [SFAppleServices sharedInstance];
    NSString *team = SFTeam();
    [apple submitCodeSigningRequestForTeamID:team machineName:[self machineName] machineID:[self machineIdentifier] codeSigningRequest:requestPEM systemType:system withCompletionHandler:^(NSError *transport, NSDictionary *plist) {
        NSError *submitError = SFCheck(@"New certificate", transport, plist);
        if (submitError) { completion(submitError, nil, nil); return; }
        NSString *serial = SFString(plist[@"data"][@"attributes"][@"serialNumber"]);

        // The answer doesn't include the certificate itself, so look it up by serial number.
        [apple listAllDevelopmentCertificatesForTeamID:team systemType:system withCompletionHandler:^(NSError *listTransport, NSDictionary *list) {
            NSError *listError = SFCheck(@"List certificates", listTransport, list);
            if (listError) { completion(listError, nil, nil); return; }
            NSDictionary *created = nil;
            for (NSDictionary *entry in list[@"data"]) {
                if ([SFString(entry[@"attributes"][@"serialNumber"]) isEqualToString:serial]) { created = entry[@"attributes"]; break; }
            }
            if (!created) {
                completion(SFProvisionError([NSString stringWithFormat:@"New certificate %@ isn't listed by Apple yet. Try again in a minute.", serial ?: @""]), nil, nil);
                return;
            }
            NSString *key = [[NSString alloc] initWithData:keyPEM encoding:NSUTF8StringEncoding];
            [SAMKeychain setPassword:key forService:SFKeychainService account:SFKeychainPrivateKey];
            [SAMKeychain setPassword:team forService:SFKeychainService account:SFKeychainKeyTeam];
            SFLogEvent(SFLogLevelOK, @"certificate · created %@", SFString(created[@"machineName"]) ?: @"");
            completion(nil, key, created);
        }];
    }];
}

#pragma mark - Step 3: App ID

/// Free accounts may only use these entitlements; anything else is removed.
static NSArray *SFFreeEntitlements(void) {
    return @[@"application-identifier", @"com.apple.developer.team-identifier", @"keychain-access-groups",
             @"com.apple.security.application-groups", @"com.apple.developer.default-data-protection",
             @"com.apple.developer.healthkit", @"com.apple.developer.homekit",
             @"com.apple.external-accessory.wireless-configuration", @"inter-app-audio", @"get-task-allow"];
}

/// Portal capability codes, keyed by the entitlement that asks for them.
static NSDictionary *SFCapabilities(BOOL paid) {
    NSMutableDictionary *map = [@{
        @"inter-app-audio": @"IAD53UNK2F",
        @"com.apple.external-accessory.wireless-configuration": @"WC421J6T7P",
        @"com.apple.developer.homekit": @"homeKit",
        @"com.apple.developer.healthkit": @"HK421J6T7P",
        @"com.apple.developer.default-data-protection": @"dataProtection",
    } mutableCopy];
    if (paid) [map addEntriesFromDictionary:@{
        @"com.apple.developer.networking.networkextension": @"NWEXT04537",
        @"com.apple.developer.networking.multipath": @"MP49FN762P",
        @"com.apple.networking.vpn.configuration": @"V66P55NK2I",
        @"com.apple.developer.siri": @"SI015DKUHP",
    }];
    return map;
}

static NSString *SFDataProtectionLevel(id value) {
    NSDictionary *levels = @{ @"NSFileProtectionComplete": @"complete",
                              @"NSFileProtectionCompleteUnlessOpen": @"unlessopen",
                              @"NSFileProtectionCompleteUntilFirstUserAuthentication": @"untilfirstauth" };
    return levels[SFString(value) ?: @""] ?: @"";
}

static BOOL SFTeamIsPaid(NSDictionary *teamsAnswer, NSString *team) {
    for (NSDictionary *entry in teamsAnswer[@"teams"]) {
        if (![SFString(entry[@"teamId"]) isEqualToString:team]) continue;
        for (NSDictionary *membership in entry[@"memberships"]) {
            if ([SFString(membership[@"name"]) containsString:@"Apple Developer Program"] &&
                [SFString(membership[@"platform"]) isEqualToString:@"ios"]) return YES;
        }
    }
    return NO;
}

- (void)appIDFor:(NSString *)identifier name:(NSString *)appName binary:(NSString *)binary system:(SFSystemType)system completion:(SFAppIDResult)completion {
    SFAppleServices *apple = [SFAppleServices sharedInstance];
    NSString *team = SFTeam();
    [apple listAllApplicationsForTeamID:team systemType:system withCompletionHandler:^(NSError *transport, NSDictionary *plist) {
        NSError *listError = SFCheck(@"List App IDs", transport, plist);
        if (listError) { completion(listError, @"", nil); return; }

        NSString *existing = nil;
        NSString *doubledID = team.length ? [identifier stringByAppendingFormat:@".%@", team] : nil;
        NSString *doubledEntry = nil;
        for (NSDictionary *entry in plist[@"appIds"]) {
            NSString *entryID = SFString(entry[@"identifier"]);
            if ([entryID isEqualToString:identifier]) { existing = SFString(entry[@"appIdId"]); break; }
            if (doubledID && [entryID isEqualToString:doubledID] && [SFString(entry[@"name"]) isEqualToString:appName])
                doubledEntry = SFString(entry[@"appIdId"]);
        }

        // An older build could leave an App ID with the team suffix twice; remove it once, then retry.
        if (!existing && doubledEntry) {
            SFLogEvent(SFLogLevelInfo, @"App ID · removing old %@", doubledID);
            [apple deleteApplicationIdId:doubledEntry teamID:team systemType:system withCompletionHandler:^(NSError *deleteTransport, NSDictionary *answer) {
                NSError *deleteError = SFCheck(@"Remove old App ID", deleteTransport, answer);
                if (deleteError) { completion(deleteError, @"", nil); return; }
                [self appIDFor:identifier name:appName binary:binary system:system completion:completion];
            }];
            return;
        }

        NSMutableDictionary *entitlements = [[SFSigning updateEntitlementsForBinaryAtLocation:binary bundleIdentifier:identifier teamID:team] mutableCopy] ?: [NSMutableDictionary dictionary];
        entitlements[@"application-identifier"] = [NSString stringWithFormat:@"%@.%@", team, identifier];

        [apple listTeamsWithCompletionHandler:^(NSError *teamsError, NSDictionary *teams) {
            if (teamsError) { completion(SFProvisionError([@"List teams: " stringByAppendingString:teamsError.localizedDescription ?: @"no answer"]), @"", nil); return; }
            BOOL paid = SFTeamIsPaid(teams, team);

            NSMutableDictionary *features = [NSMutableDictionary dictionary];
            [SFCapabilities(paid) enumerateKeysAndObjectsUsingBlock:^(NSString *entitlement, NSString *feature, BOOL *stop) {
                if (!entitlements[entitlement]) return;
                features[feature] = [feature isEqualToString:@"dataProtection"] ? SFDataProtectionLevel(entitlements[entitlement]) : @"on";
            }];
            if (!paid) {
                NSArray *allowed = SFFreeEntitlements();
                for (NSString *key in entitlements.allKeys) if (![allowed containsObject:key]) [entitlements removeObjectForKey:key];
            }
            NSArray *groups = [entitlements[@"com.apple.security.application-groups"] isKindOfClass:[NSArray class]] ? entitlements[@"com.apple.security.application-groups"] : nil;
            if (groups) features[@"APG3427HIY"] = @"on";

            void (^afterSave)(NSError *, NSDictionary *, NSString *) = ^(NSError *saveTransport, NSDictionary *answer, NSString *step) {
                NSError *saveError = SFCheck(step, saveTransport, answer);
                if (saveError) { completion(saveError, @"", nil); return; }
                NSDictionary *appId = [answer[@"appId"] isKindOfClass:[NSDictionary class]] ? answer[@"appId"] : nil;
                NSString *appIdId = SFString(appId[@"appIdId"]) ?: existing ?: @"";
                if (!groups.count) { completion(nil, appIdId, entitlements); return; }
                [self joinAppID:appIdId toGroups:groups index:0 joined:[NSMutableArray array] system:system completion:^(NSError *groupError, NSArray *joined) {
                    if (groupError) { completion(groupError, @"", nil); return; }
                    entitlements[@"com.apple.security.application-groups"] = joined;
                    completion(nil, appIdId, entitlements);
                }];
            };

            if (existing) {
                SFLogEvent(SFLogLevelInfo, @"App ID · updating %@", identifier);
                [apple updateApplicationIdId:existing enabledFeatures:features teamID:team entitlements:entitlements systemType:system withCompletionHandler:^(NSError *e, NSDictionary *a) { afterSave(e, a, @"Update App ID"); }];
            } else {
                // The portal only accepts letters, digits and spaces in names.
                NSCharacterSet *other = [NSCharacterSet alphanumericCharacterSet].invertedSet;
                NSString *portalName = [[appName ?: identifier componentsSeparatedByCharactersInSet:other] componentsJoinedByString:@" "];
                SFLogEvent(SFLogLevelInfo, @"App ID · creating %@", identifier);
                [apple addApplicationId:identifier name:portalName enabledFeatures:features teamID:team entitlements:entitlements systemType:system withCompletionHandler:^(NSError *e, NSDictionary *a) { afterSave(e, a, @"New App ID"); }];
            }
        }];
    }];
}

#pragma mark - App groups

/// The part of a group ID that identifies it, without "group." and any per-tool prefix.
static NSString *SFGroupCore(NSString *group) {
    NSString *core = [group hasPrefix:@"group."] ? [group substringFromIndex:6] : group;
    if ([core hasPrefix:@"AltStore"]) {
        NSRange dot = [core rangeOfString:@"."];
        if (dot.location != NSNotFound) core = [core substringFromIndex:dot.location + 1];
    }
    return core;
}

- (void)joinAppID:(NSString *)appIdId toGroups:(NSArray *)groups index:(NSUInteger)i joined:(NSMutableArray *)joined system:(SFSystemType)system completion:(void (^)(NSError *, NSArray *))completion {
    if (i >= groups.count) { completion(nil, joined); return; }
    [self joinAppID:appIdId toGroup:groups[i] system:system completion:^(NSError *error, NSString *groupID) {
        if (error) { completion(error, nil); return; }
        if (groupID.length) [joined addObject:groupID];
        [self joinAppID:appIdId toGroups:groups index:i + 1 joined:joined system:system completion:completion];
    }];
}

- (void)joinAppID:(NSString *)appIdId toGroup:(NSString *)requested system:(SFSystemType)system completion:(void (^)(NSError *, NSString *))completion {
    SFAppleServices *apple = [SFAppleServices sharedInstance];
    NSString *team = SFTeam();
    NSString *core = SFGroupCore(SFString(requested) ?: @"");
    [apple listAllApplicationGroupsForTeamID:team systemType:system withCompletionHandler:^(NSError *transport, NSDictionary *plist) {
        NSError *listError = SFCheck(@"List app groups", transport, plist);
        if (listError) { completion(listError, nil); return; }

        void (^assign)(NSString *, NSString *) = ^(NSString *portalGroup, NSString *groupID) {
            [apple assignApplicationGroup:portalGroup toApplicationIdId:appIdId teamID:team systemType:system withCompletionHandler:^(NSError *assignTransport, NSDictionary *answer) {
                NSError *assignError = SFCheck(@"Join app group", assignTransport, answer);
                completion(assignError, assignError ? nil : groupID);
            }];
        };

        for (NSDictionary *group in plist[@"applicationGroupList"]) {
            NSString *groupID = SFString(group[@"identifier"]);
            if (core.length && [groupID containsString:core]) { assign(SFString(group[@"applicationGroup"]), groupID); return; }
        }

        NSString *newID = [NSString stringWithFormat:@"group.%@.%@", core, team];
        NSString *newName = [@"SF group " stringByAppendingString:[core stringByReplacingOccurrencesOfString:@"." withString:@" "]];
        SFLogEvent(SFLogLevelInfo, @"App ID · new app group %@", newID);
        [apple addApplicationGroupWithIdentifier:newID andName:newName forTeamID:team systemType:system withCompletionHandler:^(NSError *addTransport, NSDictionary *answer) {
            NSError *addError = SFCheck(@"New app group", addTransport, answer);
            if (addError) { completion(addError, nil); return; }
            NSDictionary *created = [answer[@"applicationGroup"] isKindOfClass:[NSDictionary class]] ? answer[@"applicationGroup"] : nil;
            assign(SFString(created[@"applicationGroup"]), SFString(created[@"identifier"]) ?: newID);
        }];
    }];
}

#pragma mark - Step 4: profile

- (void)freshProfileFor:(NSString *)identifier appIdId:(NSString *)appIdId system:(SFSystemType)system completion:(void (^)(NSError *, NSData *))completion {
    SFAppleServices *apple = [SFAppleServices sharedInstance];
    NSString *team = SFTeam();
    NSString *fullID = [NSString stringWithFormat:@"%@.%@", team, identifier];
    // Remove the old profile first so Apple issues a new one with a fresh 7 days. Failure here is fine.
    [apple deleteProvisioningProfileForApplication:fullID andTeamID:team systemType:system withCompletionHandler:^(NSError *ignored, NSDictionary *unused) {
        [apple getProvisioningProfileForAppIdId:appIdId withTeamID:team systemType:system andCompletionHandler:^(NSError *transport, NSDictionary *plist) {
            NSError *error = SFCheck(@"Download profile", transport, plist);
            if (error) { completion(error, nil); return; }
            NSDictionary *profile = [plist[@"provisioningProfile"] isKindOfClass:[NSDictionary class]] ? plist[@"provisioningProfile"] : nil;
            NSData *data = [profile[@"encodedProfile"] isKindOfClass:[NSData class]] ? profile[@"encodedProfile"] : nil;
            if (data.length == 0) { completion(SFProvisionError(@"Download profile: Apple sent an empty profile."), nil); return; }
            completion(nil, data);
        }];
    }];
}

@end
