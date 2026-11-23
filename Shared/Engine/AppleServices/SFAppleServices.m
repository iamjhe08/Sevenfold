//
//  SFAppleServices.m
//  Sevenfold
//
//  BY: T4MAG0
//
//  Two kinds of calls go to developerservices2.apple.com:
//    actions   POST .../services/QH65B2/ios/<name>.action with an XML plist body, plist answer
//    v1 API    POST .../services/v1/<path> with a JSON body; the real method (GET, DELETE)
//              goes in X-HTTP-Method-Override, and the answer is JSON
//  Both carry the signed-in identity, the GS token and fresh anisette headers.
//

#import "SFAppleServices.h"
#import "SFAuthKit.h"
#import "NSData+GZIP.h"
#import "SFAuthentication.h"

static NSString *const SFXcodeClientID   = @"XABBG36SBA";
static NSString *const SFActionsVersion  = @"QH65B2";
static NSString *const SFServicesHost    = @"https://developerservices2.apple.com/services/";

/// Read-only actions that are safe to send again when Apple answers with an HTML error page.
static BOOL SFSafeToRepeat(NSString *action, NSString *override) {
    if ([override.uppercaseString isEqualToString:@"GET"]) return YES;
    static NSSet *reads;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        reads = [NSSet setWithArray:@[@"viewDeveloper.action", @"listTeams.action", @"listDevices.action",
                                      @"listAppIds.action", @"listApplicationGroups.action", @"listProvisioningProfiles.action"]];
    });
    return [reads containsObject:action];
}

/// What an unreadable answer looked like, for the error message.
static NSString *SFDescribeBody(NSData *data) {
    if (data.length == 0) return @"empty data";
    NSString *head = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, MIN(data.length, (NSUInteger)64))] encoding:NSUTF8StringEncoding];
    head = [[head ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
    if ([head hasPrefix:@"<!doctype html"] || [head hasPrefix:@"<html"]) return @"HTML data";
    if ([head hasPrefix:@"<?xml"] || [head hasPrefix:@"<plist"] || [head hasPrefix:@"bplist"]) return @"property-list data";
    if ([head hasPrefix:@"{"] || [head hasPrefix:@"["]) return @"JSON data";
    if (data.isGzippedData) return @"compressed data";
    return @"unknown data";
}

static NSError *SFServiceError(NSInteger code, NSString *text) {
    return [NSError errorWithDomain:NSURLErrorDomain code:code userInfo:@{ NSLocalizedDescriptionKey: text }];
}

/// One request to Apple, kept together so it can be sent again unchanged.
@interface SFServiceCall : NSObject
@property (nonatomic, copy) NSURL *url;
@property (nonatomic, copy) NSData *body;
@property (nonatomic, copy) NSString *override;      // nil for plist actions
@property (nonatomic, strong) NSURLCredential *credential;
@property (nonatomic) NSUInteger triesLeft;
@property (nonatomic, readonly) BOOL isAction;
@end

@implementation SFServiceCall
- (BOOL)isAction { return self.override == nil; }
@end

@interface SFAppleServices ()
@property (nonatomic, copy) NSString *teamID;
@property (nonatomic, strong) NSURLCredential *credential;
@property (nonatomic, strong) SFAuthentication *authentication;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSDate *teamCheckedAt;
@property (nonatomic, copy) NSString *teamCheckedFor;
@end

@implementation SFAppleServices

+ (instancetype)sharedInstance {
    static SFAppleServices *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [SFAppleServices new]; });
    return shared;
}

- (instancetype)init {
    if ((self = [super init])) {
        _teamID = @"";
        _authentication = [SFAuthentication new];
        // One session for everything, so the connection to Apple stays open between calls.
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        config.waitsForConnectivity = YES;
        config.timeoutIntervalForRequest = 20;
        config.timeoutIntervalForResource = 45;
        config.HTTPMaximumConnectionsPerHost = 6;
        _session = [NSURLSession sessionWithConfiguration:config];
    }
    return self;
}

#pragma mark - Sending

- (void)applyHeadersTo:(NSMutableURLRequest *)request call:(SFServiceCall *)call {
    NSString *type = call.isAction ? @"text/x-xml-plist" : @"application/vnd.api+json";
    NSDictionary *fixed = @{
        @"Content-Type": type,
        @"Accept": type,
        @"User-Agent": @"Xcode",
        @"Accept-Language": @"en-us",
        @"Connection": @"keep-alive",
        @"X-Xcode-Version": @"14.2 (14C18)",
        @"X-Apple-I-Identity-Id": [call.credential.user componentsSeparatedByString:@"|"].firstObject ?: @"",
        @"X-Apple-GS-Token": call.credential.password ?: @"",
        @"X-Mme-Device-Id": [(AKDevice *)[AKDevice currentDevice] uniqueDeviceIdentifier] ?: @"",
    };
    [fixed enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) { [request setValue:value forHTTPHeaderField:key]; }];
    if (call.override) [request setValue:call.override forHTTPHeaderField:@"X-HTTP-Method-Override"];

    // Anisette headers last, once the rest of the request is final.
    NSDictionary *anisette = [self.authentication appleIDHeadersForRequest:request];
    [anisette enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) { [request setValue:value forHTTPHeaderField:key]; }];
    NSString *locale = anisette[@"X-Apple-I-Locale"];
    if (locale.length) [request setValue:locale forHTTPHeaderField:@"X-Apple-Locale"];   // the actions API wants both spellings
}

- (void)send:(SFServiceCall *)call completion:(SFAppleAnswer)completion {
    [self.authentication prepareDeveloperServicesAnisetteWithCompletion:^(NSError *anisetteError) {
        if (anisetteError) { completion(anisetteError, nil); return; }

        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:call.url];
        request.HTTPMethod = @"POST";
        request.HTTPBody = call.body;
        [self applyHeadersTo:request call:call];

        [[self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error || !data) {
                completion(error ?: SFServiceError(NSURLErrorBadServerResponse, @"Apple returned an empty answer."), nil);
                return;
            }
            [self handleBody:data response:(NSHTTPURLResponse *)response call:call completion:completion];
        }] resume];
    }];
}

- (void)handleBody:(NSData *)data response:(NSHTTPURLResponse *)response call:(SFServiceCall *)call completion:(SFAppleAnswer)completion {
    NSData *body = data.isGzippedData ? data.gunzippedData : data;
    NSError *parseError = nil;
    id parsed = nil;
    if (call.isAction) {
        parsed = [NSPropertyListSerialization propertyListWithData:body options:NSPropertyListImmutable format:NULL error:&parseError];
        // Some action errors come back as JSON instead of a plist.
        if (![parsed isKindOfClass:[NSDictionary class]]) {
            id json = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
            if ([json isKindOfClass:[NSDictionary class]]) { parsed = json; parseError = nil; }
        }
    } else {
        parsed = [NSJSONSerialization JSONObjectWithData:body options:0 error:&parseError];
    }
    if ([parsed isKindOfClass:[NSDictionary class]]) { completion(nil, parsed); return; }

    NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]] ? response.statusCode : 0;
    // A successful DELETE answers "204 No Content": success, not an unreadable answer.
    if (status == 204 || (body.length == 0 && status >= 200 && status < 300 && ![call.override isEqualToString:@"GET"])) {
        completion(nil, @{});
        return;
    }

    NSString *action = call.url.lastPathComponent ?: @"request";
    NSString *kind = SFDescribeBody(body);
    // Apple sometimes answers with an HTML page for a moment; read-only calls get a fresh try.
    if (call.triesLeft > 0 && SFSafeToRepeat(action, call.override)) {
        NSLog(@"[Sevenfold] unreadable %@ for %@ (HTTP %ld), trying again", kind, action, (long)status);
        [self.authentication invalidateDeveloperServicesAnisette];
        NSTimeInterval wait = call.triesLeft == 2 ? 0.75 : 1.5;
        call.triesLeft--;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(wait * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            [self send:call completion:completion];
        });
        return;
    }

    NSString *detail = status ? [NSString stringWithFormat:@"HTTP %ld, %@", (long)status, response.MIMEType ?: kind] : kind;
    NSMutableDictionary *info = [@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Apple's answer for %@ couldn't be read (%@).", action, detail] } mutableCopy];
    if (parseError) info[NSUnderlyingErrorKey] = parseError;
    completion([NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotParseResponse userInfo:info], nil);
}

- (SFServiceCall *)callTo:(NSString *)url body:(NSData *)body override:(NSString *)override credential:(NSURLCredential *)credential {
    SFServiceCall *call = [SFServiceCall new];
    call.url = [NSURL URLWithString:url];
    call.body = body;
    call.override = override;
    call.credential = credential;
    call.triesLeft = 2;
    return call;
}

/// QH65B2 action with the standard fields plus `fields`.
- (void)action:(NSString *)name system:(SFSystemType)system fields:(NSDictionary *)fields credential:(NSURLCredential *)credential completion:(SFAppleAnswer)completion {
    NSString *platformPath = @"";
    NSMutableDictionary *body = [@{
        @"clientId": SFXcodeClientID,
        @"protocolVersion": SFActionsVersion,
        @"requestId": [NSUUID UUID].UUIDString,
        @"userLocale": @[@"en_US"],
    } mutableCopy];
    switch (system) {
        case SFSystemTypeiOS:     platformPath = @"ios/";  body[@"DTDK_Platform"] = @"ios"; break;
        case SFSystemTypewatchOS: platformPath = @"ios/";  body[@"DTDK_Platform"] = @"watchos"; break;
        case SFSystemTypetvOS:    platformPath = @"tvos/"; body[@"DTDK_Platform"] = @"tvos"; body[@"subPlatform"] = @"tvOS"; break;
        default: break;
    }
    [body addEntriesFromDictionary:fields ?: @{}];
    NSData *plist = [NSPropertyListSerialization dataWithPropertyList:body format:NSPropertyListXMLFormat_v1_0 options:0 error:nil];
    NSString *url = [NSString stringWithFormat:@"%@%@/%@%@?clientId=%@", SFServicesHost, SFActionsVersion, platformPath, name, SFXcodeClientID];
    [self send:[self callTo:url body:plist override:nil credential:credential] completion:completion];
}

- (void)action:(NSString *)name system:(SFSystemType)system fields:(NSDictionary *)fields completion:(SFAppleAnswer)completion {
    [self action:name system:system fields:fields credential:self.credential completion:completion];
}

/// v1 call with a JSON body, sent as POST with the real method in the override header.
- (void)v1:(NSString *)path method:(NSString *)method json:(NSDictionary *)json completion:(SFAppleAnswer)completion {
    NSError *jsonError = nil;
    NSData *body = [NSJSONSerialization dataWithJSONObject:json options:0 error:&jsonError];
    if (!body) { completion(jsonError ?: SFServiceError(NSURLErrorCannotCreateFile, @"The request to Apple couldn't be built."), nil); return; }
    NSString *url = [NSString stringWithFormat:@"%@v1/%@", SFServicesHost, path];
    [self send:[self callTo:url body:body override:method credential:self.credential] completion:completion];
}

/// v1 call whose parameters travel as one URL-encoded string inside the JSON body.
- (void)v1:(NSString *)path method:(NSString *)method query:(NSDictionary<NSString *, NSString *> *)query completion:(SFAppleAnswer)completion {
    NSURLComponents *components = [NSURLComponents new];
    NSMutableArray *items = [NSMutableArray array];
    [query enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) { [items addObject:[NSURLQueryItem queryItemWithName:key value:value]]; }];
    components.queryItems = items;
    [self v1:path method:method json:@{ @"urlEncodedQueryParams": components.query ?: @"" } completion:completion];
}

#pragma mark - Session and sign-in

- (NSString *)currentTeamID {
    return self.teamID ?: @"";
}

- (void)ensureSessionWithIdentity:(NSString *)identity gsToken:(NSString *)token andCompletionHandler:(SFAppleAnswer)completionHandler {
    self.credential = [NSURLCredential credentialWithUser:identity password:token persistence:NSURLCredentialPersistencePermanent];
    completionHandler(nil, @{ @"reason": @"authenticated", @"userString": @"" });
}

/// Turns the sign-in result into the (reason, userString) answer the sign-in screen expects.
- (void)finishSignIn:(NSError *)error identity:(NSString *)identity token:(NSString *)token wrongCode:(BOOL)codeStep completion:(SFSignInResult)completion {
    if (!error) {
        NSURLCredential *credential = [NSURLCredential credentialWithUser:identity password:token persistence:NSURLCredentialPersistencePermanent];
        self.credential = credential;
        completion(nil, @{ @"reason": @"authenticated", @"userString": @"" }, credential);
        return;
    }
    NSString *reason = @"incorrectCredentials";
    NSString *message;
    if (!codeStep && error.code == -22406) {
        message = @"Your Apple ID or password is incorrect. App-specific passwords are not supported.";
    } else if (!codeStep && error.code == 5000) {
        message = error.localizedDescription;
    } else if (!codeStep && (error.code == 4010 || error.code == 4011)) {
        message = @"2FA code is required";
        reason = @"appSpecificRequired";
    } else if (codeStep && error.code == 4012) {
        message = @"2FA code is incorrect";
    } else {
        message = error.localizedDescription.length
            ? [NSString stringWithFormat:@"%@ (%ld)", error.localizedDescription, (long)error.code]
            : [NSString stringWithFormat:@"Unknown error occurred (%ld)", (long)error.code];
    }
    completion(nil, @{ @"reason": reason, @"userString": message ?: @"" }, nil);
}

- (void)signInWithUsername:(NSString *)username password:(NSString *)password andCompletionHandler:(SFSignInResult)completionHandler {
    [self.authentication authenticateWithUsername:username password:password withCompletion:^(NSError *error, NSString *identity, NSString *token) {
        [self finishSignIn:error identity:identity token:token wrongCode:NO completion:completionHandler];
    }];
}

- (void)requestTwoFactorLoginCodeWithCompletionHandler:(void (^)(NSError *))completion {
    [self.authentication requestLoginCodeWithCompletion:completion];
}

- (BOOL)hasActiveTwoFactorSession {
    return [self.authentication hasActiveTwoFactorSession];
}

- (void)validateLoginCode:(NSString *)code andCompletionHandler:(SFSignInResult)completionHandler {
    [self.authentication validateLoginCode:code withCompletion:^(NSError *error, NSString *identity, NSString *token) {
        [self finishSignIn:error identity:identity token:token wrongCode:YES completion:completionHandler];
    }];
}

#pragma mark - Teams

- (void)updateCurrentTeamIDWithTeamIDCheck:(NSString * (^)(NSArray *))teamIDCallback andCallback:(void (^)(NSError *, NSString *))completionHandler {
    // The team doesn't change during a run, so one lookup is reused for 10 minutes.
    NSString *user = self.credential.user ?: @"";
    if (self.teamID.length && self.teamCheckedAt && [self.teamCheckedFor isEqualToString:user] && -self.teamCheckedAt.timeIntervalSinceNow < 600) {
        completionHandler(nil, self.teamID);
        return;
    }
    [self listTeamsWithCompletionHandler:^(NSError *error, NSDictionary *answer) {
        NSArray *teams = [answer[@"teams"] isKindOfClass:[NSArray class]] ? answer[@"teams"] : nil;
        NSString *chosen = nil;
        if (!error && teams.count == 1) chosen = [teams.firstObject isKindOfClass:[NSDictionary class]] ? teams.firstObject[@"teamId"] : nil;
        else if (!error && teams.count > 1) chosen = teamIDCallback ? teamIDCallback(teams) : nil;
        if (![chosen isKindOfClass:[NSString class]]) chosen = @"";

        if (error) self.teamID = @"";
        else if (chosen.length) self.teamID = chosen;
        self.teamCheckedAt = (!error && chosen.length) ? [NSDate date] : nil;
        self.teamCheckedFor = user;
        completionHandler(error, chosen);
    }];
}

- (void)listTeamsWithCompletionHandler:(SFAppleAnswer)completionHandler {
    [self listTeamsWithCredentials:self.credential completionHandler:completionHandler];
}

- (void)listTeamsWithCredentials:(NSURLCredential *)credentials completionHandler:(SFAppleAnswer)completionHandler {
    if (credentials.user.length == 0 || credentials.password.length == 0) {
        completionHandler([NSError errorWithDomain:@"Sevenfold.Authentication" code:1 userInfo:@{ NSLocalizedDescriptionKey: @"Apple's sign-in didn't return usable developer credentials. Please sign in again." }], nil);
        return;
    }
    [self action:@"listTeams.action" system:SFSystemTypeUndefined fields:nil credential:credentials completion:completionHandler];
}

#pragma mark - Devices

- (void)addDevice:(NSString *)udid deviceName:(NSString *)name forTeamID:(NSString *)teamID systemType:(SFSystemType)systemType withCompletionHandler:(SFAppleAnswer)completionHandler {
    [self action:@"addDevice.action" system:systemType fields:@{ @"teamId": teamID ?: @"", @"deviceNumber": udid ?: @"", @"name": name ?: @"" } completion:completionHandler];
}

- (void)listDevicesForTeamID:(NSString *)teamID systemType:(SFSystemType)systemType withCompletionHandler:(SFAppleAnswer)completionHandler {
    [self action:@"listDevices.action" system:systemType fields:@{ @"teamId": teamID ?: @"", @"pageSize": @"500", @"pageNumber": @"1",
                                                                   @"sort": @"name=asc", @"includeRemovedDevices": @"false" } completion:completionHandler];
}

#pragma mark - App IDs and app groups

- (void)listAllApplicationsForTeamID:(NSString *)teamID systemType:(SFSystemType)systemType withCompletionHandler:(SFAppleAnswer)completionHandler {
    [self action:@"listAppIds.action" system:systemType fields:@{ @"teamId": teamID ?: @"" } completion:completionHandler];
}

/// Fields for adding or updating an App ID: capabilities ("on"/level) and entitlements go in as is.
static NSMutableDictionary *SFAppIDFields(NSString *teamID, NSDictionary *features, NSDictionary *entitlements) {
    NSMutableDictionary *fields = [@{ @"teamId": teamID ?: @"", @"type": @"explicit" } mutableCopy];
    [fields addEntriesFromDictionary:features ?: @{}];
    fields[@"entitlements"] = entitlements ?: @{};
    return fields;
}

- (void)addApplicationId:(NSString *)applicationIdentifier name:(NSString *)applicationName enabledFeatures:(NSDictionary *)enabledFeatures teamID:(NSString *)teamID entitlements:(NSDictionary *)entitlements systemType:(SFSystemType)systemType withCompletionHandler:(SFAppleAnswer)completionHandler {
    NSMutableDictionary *fields = SFAppIDFields(teamID, enabledFeatures, entitlements);
    fields[@"identifier"] = applicationIdentifier ?: @"";
    fields[@"name"] = applicationName ?: @"";
    [self action:@"addAppId.action" system:systemType fields:fields completion:completionHandler];
}

- (void)updateApplicationIdId:(NSString *)appIdId enabledFeatures:(NSDictionary *)enabledFeatures teamID:(NSString *)teamID entitlements:(NSDictionary *)entitlements systemType:(SFSystemType)systemType withCompletionHandler:(SFAppleAnswer)completionHandler {
    NSMutableDictionary *fields = SFAppIDFields(teamID, enabledFeatures, entitlements);
    fields[@"appIdId"] = appIdId ?: @"";
    [self action:@"updateAppId.action" system:systemType fields:fields completion:completionHandler];
}

- (void)deleteApplicationIdId:(NSString *)appIdId teamID:(NSString *)teamID systemType:(SFSystemType)systemType withCompletionHandler:(SFAppleAnswer)completionHandler {
    [self action:@"deleteAppId.action" system:systemType fields:@{ @"teamId": teamID ?: @"", @"appIdId": appIdId ?: @"" } completion:completionHandler];
}

- (void)listAllApplicationGroupsForTeamID:(NSString *)teamID systemType:(SFSystemType)systemType withCompletionHandler:(SFAppleAnswer)completionHandler {
    [self action:@"listApplicationGroups.action" system:systemType fields:@{ @"teamId": teamID ?: @"" } completion:completionHandler];
}

- (void)addApplicationGroupWithIdentifier:(NSString *)identifier andName:(NSString *)groupName forTeamID:(NSString *)teamID systemType:(SFSystemType)systemType withCompletionHandler:(SFAppleAnswer)completionHandler {
    [self action:@"addApplicationGroup.action" system:systemType fields:@{ @"teamId": teamID ?: @"", @"identifier": identifier ?: @"", @"name": groupName ?: @"" } completion:completionHandler];
}

- (void)assignApplicationGroup:(NSString *)applicationGroup toApplicationIdId:(NSString *)appIdId teamID:(NSString *)teamID systemType:(SFSystemType)systemType withCompletionHandler:(SFAppleAnswer)completionHandler {
    [self action:@"assignApplicationGroupToAppId.action" system:systemType fields:@{ @"teamId": teamID ?: @"", @"appIdId": appIdId ?: @"", @"applicationGroups": applicationGroup ?: @"" } completion:completionHandler];
}

#pragma mark - Certificates

- (void)listAllDevelopmentCertificatesWithFiltering:(BOOL)useFilter teamID:(NSString *)teamID systemType:(SFSystemType)systemType withCompletionHandler:(SFAppleAnswer)completionHandler {
    NSMutableDictionary *query = [@{ @"teamId": teamID ?: @"" } mutableCopy];
    if (useFilter) query[@"filter[certificateType]"] = @"IOS_DEVELOPMENT";
    [self v1:@"certificates" method:@"GET" query:query completion:completionHandler];
}

- (void)listAllDevelopmentCertificatesForTeamID:(NSString *)teamID systemType:(SFSystemType)systemType withCompletionHandler:(SFAppleAnswer)completionHandler {
    [self listAllDevelopmentCertificatesWithFiltering:NO teamID:teamID systemType:systemType withCompletionHandler:completionHandler];
}

- (void)revokeCertificateForIdentifier:(NSString *)identifier andTeamID:(NSString *)teamID systemType:(SFSystemType)systemType withCompletionHandler:(SFAppleAnswer)completionHandler {
    [self v1:[@"certificates/" stringByAppendingString:identifier ?: @""] method:@"DELETE" query:@{ @"teamId": teamID ?: @"" } completion:completionHandler];
}

- (void)submitCodeSigningRequestForTeamID:(NSString *)teamId machineName:(NSString *)machineName machineID:(NSString *)machineID codeSigningRequest:(NSData *)csr systemType:(SFSystemType)systemType withCompletionHandler:(SFAppleAnswer)completionHandler {
    NSDictionary *attributes = @{
        @"certificateType": @"DEVELOPMENT",
        @"teamId": teamId ?: @"",
        @"csrContent": [[NSString alloc] initWithData:csr encoding:NSUTF8StringEncoding] ?: @"",
        @"machineId": machineID ?: @"",
        @"machineName": machineName ?: @"",
    };
    // Sent the same way as before: JSON body with the override header set to "post".
    [self v1:@"certificates" method:@"post" json:@{ @"data": @{ @"type": @"certificates", @"attributes": attributes } } completion:completionHandler];
}

#pragma mark - Profiles

- (void)listAllProvisioningProfilesForTeamID:(NSString *)teamID systemType:(SFSystemType)systemType withCompletionHandler:(SFAppleAnswer)completionHandler {
    [self action:@"listProvisioningProfiles.action" system:systemType fields:@{ @"teamId": teamID ?: @"" } completion:completionHandler];
}

- (void)getProvisioningProfileForAppIdId:(NSString *)appIdId withTeamID:(NSString *)teamID systemType:(SFSystemType)systemType andCompletionHandler:(SFAppleAnswer)completionHandler {
    [self action:@"downloadTeamProvisioningProfile.action" system:systemType fields:@{ @"teamId": teamID ?: @"", @"appIdId": appIdId ?: @"" } completion:completionHandler];
}

- (void)deleteProvisioningProfileForApplication:(NSString *)applicationId andTeamID:(NSString *)teamID systemType:(SFSystemType)systemType withCompletionHandler:(SFAppleAnswer)completionHandler {
    [self listAllProvisioningProfilesForTeamID:teamID systemType:systemType withCompletionHandler:^(NSError *error, NSDictionary *answer) {
        if (error) { completionHandler(error, nil); return; }
        NSString *profileID = nil;
        for (NSDictionary *profile in answer[@"provisioningProfiles"]) {
            NSString *identifier = profile[@"appId"][@"identifier"];
            if ([identifier isKindOfClass:[NSString class]] && applicationId.length && [identifier isEqualToString:applicationId]) {
                profileID = profile[@"provisioningProfileId"];
                break;
            }
        }
        if (![profileID isKindOfClass:[NSString class]] || profileID.length == 0) {
            completionHandler([NSError errorWithDomain:NSInvalidArgumentException code:-1 userInfo:@{ NSLocalizedDescriptionKey: @"No profile matches this bundle ID." }], nil);
            return;
        }
        [self action:@"deleteProvisioningProfile.action" system:systemType fields:@{ @"teamId": teamID ?: @"", @"provisioningProfileId": profileID } completion:completionHandler];
    }];
}

@end
