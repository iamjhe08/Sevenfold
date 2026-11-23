//
//  SFSigning.mm
//  Sevenfold
//
//  Sevenfold · BY: T4MAG0
//

#import "SFSigning.h"
extern "C" {
#import "SFLog.h"
}
#include "ldid.hpp"
#include <atomic>
#include <memory>
#include <openssl/err.h>
#include <openssl/evp.h>
#include <openssl/pem.h>
#include <openssl/pkcs12.h>
#include <openssl/x509.h>
#include <openssl/x509v3.h>
#include <string>

namespace {

/// Owns an OpenSSL object and frees it with the right function.
template <typename T, void (*Free)(T *)>
struct Owned {
    T *ptr = nullptr;
    Owned() = default;
    explicit Owned(T *p) : ptr(p) {}
    ~Owned() { if (ptr) Free(ptr); }
    Owned(const Owned &) = delete;
    Owned &operator=(const Owned &) = delete;
    T *release() { T *p = ptr; ptr = nullptr; return p; }
    explicit operator bool() const { return ptr != nullptr; }
};

void FreeBio(BIO *b) { BIO_free_all(b); }
void FreeStack(STACK_OF(X509) *s) { sk_X509_pop_free(s, X509_free); }

using OwnedX509 = Owned<X509, X509_free>;
using OwnedKey = Owned<EVP_PKEY, EVP_PKEY_free>;
using OwnedBio = Owned<BIO, FreeBio>;
using OwnedPKCS12 = Owned<PKCS12, PKCS12_free>;
using OwnedStack = Owned<STACK_OF(X509), FreeStack>;

/// A PEM certificate shipped in the app bundle (apple-ios, apple-ios-g3, root).
X509 *BundledCertificate(NSString *name) {
    NSString *path = [[NSBundle mainBundle] pathForResource:name ofType:@"pem"];
    NSData *pem = path ? [NSData dataWithContentsOfFile:path] : nil;
    if (pem.length == 0) return nullptr;
    OwnedBio bio(BIO_new_mem_buf((void *)pem.bytes, (int)pem.length));
    return bio ? PEM_read_bio_X509(bio.ptr, nullptr, nullptr, nullptr) : nullptr;
}

/// Builds the PKCS#12 (empty password) ldid signs with: key + certificate + Apple's
/// intermediate that issued it + Apple's root. Empty string on failure.
std::string MakeIdentity(NSString *keyPEM, NSData *certificateDER, NSString **problem) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ OpenSSL_add_all_algorithms(); ERR_load_crypto_strings(); });

    NSData *keyData = [keyPEM dataUsingEncoding:NSUTF8StringEncoding];
    OwnedBio keyBio(BIO_new_mem_buf((void *)keyData.bytes, (int)keyData.length));
    OwnedKey key(keyBio ? PEM_read_bio_PrivateKey(keyBio.ptr, nullptr, nullptr, nullptr) : nullptr);
    if (!key) { *problem = @"The certificate's private key couldn't be read."; return ""; }

    const unsigned char *der = (const unsigned char *)certificateDER.bytes;
    OwnedX509 leaf(d2i_X509(nullptr, &der, (long)certificateDER.length));
    if (!leaf) { *problem = @"The certificate from Apple couldn't be read."; return ""; }

    // Pick the Apple intermediate that actually issued this certificate.
    OwnedX509 intermediate;
    for (NSString *name in @[@"apple-ios-g3", @"apple-ios"]) {
        OwnedX509 candidate(BundledCertificate(name));
        if (candidate && X509_check_issued(candidate.ptr, leaf.ptr) == X509_V_OK) { intermediate.ptr = candidate.release(); break; }
    }
    if (!intermediate) { *problem = @"Apple's intermediate certificate for this certificate isn't bundled."; return ""; }
    OwnedX509 root(BundledCertificate(@"root"));

    OwnedStack chain(sk_X509_new_null());
    if (root) sk_X509_push(chain.ptr, root.release());
    sk_X509_push(chain.ptr, intermediate.release());

    OwnedPKCS12 bundle(PKCS12_create((char *)"", (char *)"Sevenfold", key.ptr, leaf.ptr, chain.ptr, 0, 0, 0, 0, 0));
    if (!bundle) { *problem = @"Couldn't package the certificate for signing."; return ""; }

    OwnedBio out(BIO_new(BIO_s_mem()));
    if (i2d_PKCS12_bio(out.ptr, bundle.ptr) <= 0) { *problem = @"Couldn't package the certificate for signing."; return ""; }
    char *bytes = nullptr;
    long length = BIO_get_mem_data(out.ptr, &bytes);
    return std::string(bytes, (size_t)length);
}

} // namespace

static dispatch_queue_t SFLdidQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("com.t4mag0.sevenfold.ldid", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0)); });
    return queue;
}

@implementation SFSigning {
    std::string _identity;        // PKCS#12 bytes
    NSString *_identityProblem;   // why _identity is empty
}

+ (instancetype)signerWithCertificate:(NSData *)certificate privateKey:(NSString *)privateKey {
    SFSigning *signer = [self new];
    NSString *problem = nil;
    signer->_identity = MakeIdentity(privateKey, certificate, &problem);
    signer->_identityProblem = problem;
    if (problem) NSLog(@"[Sevenfold] signing identity: %@", problem);
    return signer;
}

+ (NSMutableDictionary *)getEntitlementsForBinaryAtLocation:(NSString *)binaryLocation {
    NSData *binary = [NSData dataWithContentsOfFile:binaryLocation options:NSDataReadingMappedIfSafe error:nil];
    if (binary.length == 0) return nil;
    std::string xml;
    try { xml = ldid::Analyze(binary.bytes, (size_t)binary.length); } catch (...) { xml.clear(); }
    if (xml.empty()) return [NSMutableDictionary dictionary];
    NSData *data = [NSData dataWithBytes:xml.data() length:xml.size()];
    id plist = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListMutableContainersAndLeaves format:NULL error:nil];
    return [plist isKindOfClass:[NSDictionary class]] ? plist : [NSMutableDictionary dictionary];
}

+ (NSDictionary *)updateEntitlementsForBinaryAtLocation:(NSString *)binaryLocation bundleIdentifier:(NSString *)bundleIdentifier teamID:(NSString *)teamid {
    NSMutableDictionary *entitlements = [self getEntitlementsForBinaryAtLocation:binaryLocation];
    if (!entitlements) return @{};
    // A free development profile only allows these to name the user's own team and app.
    entitlements[@"application-identifier"] = [NSString stringWithFormat:@"%@.%@", teamid, bundleIdentifier];
    entitlements[@"com.apple.developer.team-identifier"] = teamid;
    entitlements[@"keychain-access-groups"] = @[[NSString stringWithFormat:@"%@.*", teamid]];
    return entitlements;
}

- (void)signBundleAtPath:(NSString *)absolutePath entitlements:(NSDictionary *)entitlements identifier:(NSString *)bundleIdentifier withCallback:(void (^)(BOOL, NSString *))completionHandler {
    if (_identity.empty()) {
        completionHandler(NO, _identityProblem ?: @"No valid PKCS12 certificate is available to use for signing.");
        return;
    }
    NSData *xml = [NSPropertyListSerialization dataWithPropertyList:entitlements ?: @{} format:NSPropertyListXMLFormat_v1_0 options:0 error:nil];
    std::string topLevelEntitlements(xml ? (const char *)xml.bytes : "", xml ? xml.length : 0);
    std::string identity = _identity;
    NSString *bundleName = absolutePath.lastPathComponent;

    // Report exactly once: either ldid finishes, or the watchdog gives up after 90 s.
    auto reported = std::make_shared<std::atomic<bool>>(false);
    auto lastFile = std::make_shared<std::string>();
    NSObject *fileLock = [NSObject new];
    void (^report)(BOOL, NSString *) = ^(BOOL ok, NSString *message) {
        if (reported->exchange(true)) return;
        completionHandler(ok, message);
    };

    // ldid runs on its own serial queue: off the caller's thread, and one app at a time even
    // when several apps are signed together (it takes well under a second per app).
    dispatch_async(SFLdidQueue(), ^{
        SFLogEvent(SFLogLevelInfo, @"signing · ldid started on %@", bundleName);
        NSDate *started = [NSDate date];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(90 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            if (reported->exchange(true)) return;   // ldid already finished: nothing to report
            NSString *file;
            @synchronized (fileLock) { file = [NSString stringWithUTF8String:lastFile->c_str()] ?: @""; }
            SFLogEvent(SFLogLevelError, @"signing · ldid still busy on %@ after 90 s · last file: %@", bundleName, file.length ? file : @"(none yet)");
            completionHandler(NO, [NSString stringWithFormat:@"Signing %@ didn't finish (stuck on %@). Send Diagnostics › App activity.", bundleName, file.length ? file : @"the first file"]);
        });
        NSString *failure = nil;
        NSUInteger files = 0;
        try {
            ldid::DiskFolder folder(absolutePath.fileSystemRepresentation);
            // Empty requirements: iOS accepts them, and the requirement APIs don't exist on iOS.
            ldid::Sign("", folder, identity, "",
                       ldid::fun([&](const std::string &path, const std::string &existing) -> std::string {
                           return path.empty() ? topLevelEntitlements : existing;   // nested code keeps its own
                       }),
                       ldid::fun([&](const std::string &path) {
                           files++;
                           @synchronized (fileLock) { *lastFile = path; }
                       }),
                       ldid::fun([&](double) {}));
        } catch (const std::exception &e) {
            failure = [NSString stringWithFormat:@"Signing failed: %s", e.what()];
        } catch (const char *message) {
            failure = [NSString stringWithFormat:@"Signing failed: %s", message ?: "ldid error"];
        } catch (...) {
            failure = @"Signing failed inside ldid.";
        }
        NSTimeInterval took = -[started timeIntervalSinceNow];
        if (failure) SFLogEvent(SFLogLevelError, @"signing · ldid on %@ failed after %.1f s: %@", bundleName, took, failure);
        else SFLogEvent(SFLogLevelInfo, @"signing · ldid finished %@ · %lu files · %.1f s", bundleName, (unsigned long)files, took);
        report(failure == nil, failure ?: @"");
    });
}

@end
