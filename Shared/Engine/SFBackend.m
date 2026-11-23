//
//  SFBackend.m
//  Sevenfold
//
//  Sevenfold · BY: T4MAG0
//

#import "SFBackend.h"
#import "SFProvisioning.h"
#import "SFSigning.h"
#import "SSZipArchive.h"
#import "SFLog.h"

/// Info.plist key holding the app's bundle ID before Sevenfold added the team suffix.
static NSString *const SFOriginalBundleIDKey = @"SFOriginalBundleIdentifier";

@implementation SFBackend

+ (NSError *)errorWithText:(NSString *)text {
    return [NSError errorWithDomain:@"Sevenfold.Signing" code:-1 userInfo:@{ NSLocalizedDescriptionKey: text ?: @"Signing failed." }];
}

// MARK: - Device and certificate helpers

+ (void)provisionDevice:(NSString *)udid name:(NSString *)name identity:(NSString *)identity gsToken:(NSString *)gsToken priorChosenTeamID:(NSString *)teamId systemType:(SFSystemType)systemType withCallback:(void (^)(NSError *))completionHandler {
    SFProvisioning *provisioner = [SFProvisioning provisionerWithCredentials:identity :gsToken];
    [provisioner provisionDevice:udid name:name withTeamIDCheck:^NSString *(NSArray *teams) { return teamId; }
                      systemType:systemType andCallback:completionHandler];
}

+ (void)revokeDevelopmentCertificatesForCurrentMachineWithIdentity:(NSString *)identity gsToken:(NSString *)gsToken priorChosenTeamID:(NSString *)teamId systemType:(SFSystemType)systemType withCallback:(void (^)(NSError *))completionHandler {
    SFProvisioning *provisioner = [SFProvisioning provisionerWithCredentials:identity :gsToken];
    [provisioner revokeCertificatesWithTeamIDCheck:^NSString *(NSArray *teams) { return teamId; }
                                        systemType:systemType andCallback:completionHandler];
}

// MARK: - Signing

/// Nested bundles that need their own profile: app extensions and Watch apps.
+ (NSArray<NSString *> *)nestedBundlesInApp:(NSString *)appPath {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray *nested = [NSMutableArray array];
    for (NSString *folder in @[@"PlugIns", @"Watch"]) {
        NSString *dir = [appPath stringByAppendingPathComponent:folder];
        for (NSString *item in [[fm contentsOfDirectoryAtPath:dir error:nil] sortedArrayUsingSelector:@selector(compare:)]) {
            BOOL isDir = NO;
            NSString *full = [dir stringByAppendingPathComponent:item];
            if ([fm fileExistsAtPath:full isDirectory:&isDir] && isDir) [nested addObject:full];
        }
    }
    return nested;
}

+ (SFSystemType)systemTypeForInfo:(NSDictionary *)info {
    NSString *platform = [info[@"DTPlatformName"] lowercaseString];
    if ([platform isEqualToString:@"watchos"]) return SFSystemTypewatchOS;
    if ([platform isEqualToString:@"appletvos"] || [platform isEqualToString:@"tvos"]) return SFSystemTypetvOS;
    return SFSystemTypeiOS;
}

/// The app's original bundle ID, with any ".TEAMID" Sevenfold added earlier taken off.
+ (NSString *)originalBundleIDFromInfo:(NSDictionary *)info teamID:(NSString *)teamId {
    NSString *identifier = info[SFOriginalBundleIDKey] ?: info[@"ALTBundleIdentifier"] ?: info[@"CFBundleIdentifier"];
    NSString *suffix = teamId.length ? [@"." stringByAppendingString:teamId] : nil;
    while (suffix && [identifier hasSuffix:suffix] && identifier.length > suffix.length)
        identifier = [identifier substringToIndex:identifier.length - suffix.length];
    return identifier;
}

+ (void)signBundleAtPath:(NSString *)path identity:(NSString *)identity gsToken:(NSString *)gsToken priorChosenTeamID:(NSString *)teamId withCompletionHandler:(void (^)(NSError *))completionHandler {
    // Nested bundles first, one after another, so the outer signature covers their final state.
    NSArray<NSString *> *nested = [self nestedBundlesInApp:path];
    [self signNested:nested index:0 appPath:path identity:identity gsToken:gsToken teamID:teamId completion:completionHandler];
}

+ (void)signNested:(NSArray<NSString *> *)nested index:(NSUInteger)i appPath:(NSString *)path identity:(NSString *)identity gsToken:(NSString *)gsToken teamID:(NSString *)teamId completion:(void (^)(NSError *))completion {
    if (i >= nested.count) {
        if (nested.count) SFLogEvent(SFLogLevelInfo, @"signing · extensions done, now %@", path.lastPathComponent);
        [self signSingleBundleAtPath:path identity:identity gsToken:gsToken teamID:teamId completion:completion];
        return;
    }
    NSString *child = nested[i];
    SFLogEvent(SFLogLevelInfo, @"signing · nested %@ (%lu of %lu)", child.lastPathComponent, (unsigned long)(i + 1), (unsigned long)nested.count);
    [self signBundleAtPath:child identity:identity gsToken:gsToken priorChosenTeamID:teamId withCompletionHandler:^(NSError *error) {
        if (error) {
            SFLogEvent(SFLogLevelError, @"signing · %@ failed: %@", child.lastPathComponent, error.localizedDescription);
            completion(error);
            return;
        }
        [self signNested:nested index:i + 1 appPath:path identity:identity gsToken:gsToken teamID:teamId completion:completion];
    }];
}

+ (void)signSingleBundleAtPath:(NSString *)path identity:(NSString *)identity gsToken:(NSString *)gsToken teamID:(NSString *)teamId completion:(void (^)(NSError *))completion {
    NSString *infoPath = [path stringByAppendingPathComponent:@"Info.plist"];
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithContentsOfFile:infoPath];
    if (info.count == 0) { SFLogEvent(SFLogLevelError, @"signing · can't read %@ Info.plist", path.lastPathComponent); completion([self errorWithText:[NSString stringWithFormat:@"Couldn't read %@'s Info.plist.", path.lastPathComponent]]); return; }

    // Free accounts can't use someone else's bundle ID, so the app gets ".TEAMID" added.
    NSString *original = [self originalBundleIDFromInfo:info teamID:teamId];
    NSString *signedIdentifier = teamId.length ? [NSString stringWithFormat:@"%@.%@", original, teamId] : original;
    info[SFOriginalBundleIDKey] = original;
    info[@"CFBundleIdentifier"] = signedIdentifier;
    NSError *writeError = nil;
    if (![info writeToURL:[NSURL fileURLWithPath:infoPath] error:&writeError]) {
        completion(writeError ?: [self errorWithText:@"Couldn't update the app's Info.plist."]);
        return;
    }

    NSString *executable = info[@"CFBundleExecutable"];
    NSString *binary = executable.length ? [path stringByAppendingPathComponent:executable] : nil;
    NSString *name = info[@"CFBundleName"] ?: info[@"CFBundleDisplayName"] ?: path.lastPathComponent.stringByDeletingPathExtension;
    SFSystemType systemType = [self systemTypeForInfo:info];

    SFLogEvent(SFLogLevelInfo, @"signing · %@: getting App ID and profile from Apple", signedIdentifier);
    // Never wait forever on Apple: after 2 minutes, report it and stop.
    __block BOOL answered = NO;
    NSObject *lock = [NSObject new];
    BOOL (^claim)(void) = ^BOOL {
        @synchronized (lock) { if (answered) return NO; answered = YES; return YES; }
    };
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(120 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        if (!claim()) return;
        SFLogEvent(SFLogLevelError, @"signing · %@: Apple didn't finish the profile in 2 minutes", signedIdentifier);
        completion([self errorWithText:[NSString stringWithFormat:@"Apple didn't finish setting up the profile for %@ in 2 minutes. Check Diagnostics › App activity for the last step, then try again.", name]]);
    });

    SFProvisioning *provisioner = [SFProvisioning provisionerWithCredentials:identity :gsToken];
    [provisioner downloadProvisioningProfileForApplicationIdentifier:signedIdentifier applicationName:name binaryLocation:binary
                                                     withTeamIDCheck:^NSString *(NSArray *teams) { return teamId; }
                                                          systemType:systemType
                                                         andCallback:^(NSError *error, NSData *profile, NSString *privateKey, NSDictionary *certificate, NSDictionary *entitlements) {
        if (!claim()) return;   // already timed out
        if (error) {
            SFLogEvent(SFLogLevelError, @"signing · %@: %@", signedIdentifier, error.localizedDescription);
            completion(error);
            return;
        }
        SFLogEvent(SFLogLevelInfo, @"signing · %@: profile received, signing files", signedIdentifier);
        if (profile.length == 0 || privateKey.length == 0 || certificate == nil) {
            completion([self errorWithText:@"Apple didn't return a complete profile and certificate."]);
            return;
        }
        NSString *profilePath = [path stringByAppendingPathComponent:@"embedded.mobileprovision"];
        NSError *fileError = nil;
        [[NSFileManager defaultManager] removeItemAtPath:profilePath error:nil];
        if (![profile writeToFile:profilePath options:NSDataWritingAtomic error:&fileError]) {
            completion(fileError ?: [self errorWithText:@"Couldn't save the new profile into the app."]);
            return;
        }
        NSData *certificateDER = [[NSData alloc] initWithBase64EncodedString:certificate[@"certificateContent"] ?: @"" options:0];
        SFSigning *signer = [SFSigning signerWithCertificate:certificateDER ?: [NSData data] privateKey:privateKey];
        [signer signBundleAtPath:path entitlements:entitlements ?: @{} identifier:signedIdentifier withCallback:^(BOOL success, NSString *message) {
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                completion(success ? nil : [self errorWithText:message]);
            });
        }];
    }];
}

// MARK: - Files

+ (BOOL)repackIpaAtPath:(NSString *)extractedPath toPath:(NSString *)outputPath error:(NSError **)error {
    if (![outputPath.pathExtension.lowercaseString isEqualToString:@"ipa"]) {
        if (error) *error = [self errorWithText:@"The output file must end in .ipa."];
        return NO;
    }
    [[NSFileManager defaultManager] removeItemAtPath:outputPath error:nil];
    BOOL ok = [SSZipArchive createZipFileAtPath:outputPath withContentsOfDirectory:extractedPath keepParentDirectory:NO
                               compressionLevel:0 password:nil AES:NO progressHandler:nil];
    if (!ok && error) *error = [self errorWithText:@"Couldn't pack the signed app."];
    return ok;
}

+ (NSString *)applicationTemporaryDirectory {
    NSString *dir = NSTemporaryDirectory() ?: @"/tmp";
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

@end
