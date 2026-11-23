//
//  SFServiceLink.m
//  Sevenfold
//
//  BY: T4MAG0
//
//  Everything runs on the main queue. Each connection gets a generation number,
//  so callbacks from a connection that was already replaced are ignored.
//

#import "SFServiceLink.h"
#import "SFLocalization.h"
#import "SFDaemonProtocol.h"
#import "SFBackgroundSigningManager.h"
#import "SFNotificationManager.h"
#import "SFResources.h"
#import "SFSigningSession.h"
#import "SFErrors.h"
#import "SFLog.h"
#import <UIKit/UIKit.h>

static NSString *const SFTestErrorDomain = @"com.t4mag0.sevenfold.background-signing";
static const NSUInteger SFReconnectLimit = 5;

#define SF_ON_MAIN(call) if (![NSThread isMainThread]) { dispatch_async(dispatch_get_main_queue(), ^{ call; }); return; }

@interface NSXPCConnection (SFMachService)
- (id)initWithMachServiceName:(NSString *)name;
@end

@interface SFServiceLink ()
@property (nonatomic, strong) NSXPCConnection *connection;
@property (nonatomic) NSUInteger generation;
@property (nonatomic) NSUInteger reconnectAttempts;
@property (nonatomic) BOOL reconnectPlanned;
@property (nonatomic) BOOL appActive;
@property (nonatomic) BOOL showFailureWhenActive;

// Things to send once connected
@property (nonatomic) BOOL preferencesPending;
@property (nonatomic) BOOL testPending;

// The signing pass the service is keeping us awake for
@property (nonatomic, copy) NSString *leaseID;

// Diagnostics test
@property (nonatomic) BOOL testRunning;
@property (nonatomic) BOOL testAwaitingRun;     // sent; waiting for the service to start the run
@property (nonatomic) NSUInteger testGeneration;
@property (nonatomic, strong) NSMutableArray *testCallbacks;
@end

@implementation SFServiceLink

+ (instancetype)shared {
    static SFServiceLink *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [SFServiceLink new]; });
    return shared;
}

- (instancetype)init {
    if ((self = [super init])) {
        _testCallbacks = [NSMutableArray array];
        [[SFApplicationSigning sharedInstance] addSigningUpdatesObserver:self];
    }
    return self;
}

- (BOOL)connected {
    return self.connection != nil;
}

/// The service's proxy; on an XPC error, `failure` runs on the main queue (if this connection is still current).
- (id<SFDaemonProtocol>)serviceWithFailure:(void (^)(NSError *error))failure {
    NSUInteger generation = self.generation;
    __weak SFServiceLink *weakSelf = self;
    return [self.connection remoteObjectProxyWithErrorHandler:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (weakSelf && weakSelf.generation == generation && failure) failure(error);
        });
    }];
}

#pragma mark - Connection

- (void)connect {
    SF_ON_MAIN([self connect]);
    [self drop];

    NSXPCConnection *connection = [[NSXPCConnection alloc] initWithMachServiceName:@"com.t4mag0.sevenfoldd"];
    connection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SFDaemonProtocol)];
    connection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SFApplicationProtocol)];
    connection.exportedObject = self;
    self.connection = connection;
    NSUInteger generation = ++self.generation;

    __weak SFServiceLink *weakSelf = self;
    void (^lost)(NSString *) = ^(NSString *why) {
        dispatch_async(dispatch_get_main_queue(), ^{
            SFServiceLink *link = weakSelf;
            if (!link || link.generation != generation) return;
            NSLog(@"[Sevenfold] background service connection %@", why);
            [link drop];
            [link planReconnect];
        });
    };
    connection.interruptionHandler = ^{ lost(@"interrupted"); };
    connection.invalidationHandler = ^{ lost(@"invalidated"); };
    [connection resume];

    // Hello: the service then sends anything it queued for us.
    [[self serviceWithFailure:^(NSError *error) {
        NSLog(@"[Sevenfold] background service didn't answer: %@", error);
        [weakSelf drop];
        [weakSelf planReconnect];
    }] applicationDidLaunch];

    if (self.preferencesPending) [self sendPreferencesUpdate];
    if (self.leaseID) [self requestLease];
    if (self.testPending) [self sendTest];

    // Staying connected for 2 seconds ends a retry sequence.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        SFServiceLink *link = weakSelf;
        if (link && link.generation == generation && link.connection) {
            link.reconnectAttempts = 0;
            link.showFailureWhenActive = NO;
        }
    });
}

- (void)drop {
    NSXPCConnection *old = self.connection;
    if (!old) return;
    self.connection = nil;
    self.generation++;
    [old invalidate];
}

/// Reconnects after 1, 2, 4, 8, 8 s; after that, tells the user once the app is in front.
- (void)planReconnect {
    SF_ON_MAIN([self planReconnect]);
    if (self.connection || self.reconnectPlanned) return;
    if (self.reconnectAttempts >= SFReconnectLimit) { [self reportNoService]; return; }

    NSTimeInterval delay = (NSTimeInterval)(1u << MIN(self.reconnectAttempts, (NSUInteger)3));
    self.reconnectAttempts++;
    self.reconnectPlanned = YES;
    __weak SFServiceLink *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SFServiceLink *link = weakSelf;
        if (!link) return;
        link.reconnectPlanned = NO;
        if (!link.connection) [link connect];
    });
}

- (void)reportNoService {
    if (!self.appActive) { self.showFailureWhenActive = YES; return; }
    NSLog(@"[Sevenfold] couldn't connect to the background service");
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:SFL(@"Background service not running")
                                                                    message:SFL(@"Sevenfold couldn't reach its background service, so automatic signing is paused.\n\nReinstall Sevenfold or restart your iPhone.")
                                                             preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SFL(@"OK") style:UIAlertActionStyleCancel handler:nil]];
    UIViewController *top = [UIApplication sharedApplication].delegate.window.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    [top presentViewController:alert animated:YES completion:nil];
}

- (void)appBecameActive {
    SF_ON_MAIN([self appBecameActive]);
    self.appActive = YES;
    if (!self.connection && !self.reconnectPlanned) {
        self.reconnectAttempts = 0;
        [self connect];
    }
    if (self.showFailureWhenActive) {
        self.showFailureWhenActive = NO;
        [self reportNoService];
    }
}

- (void)appBecameInactive {
    self.appActive = NO;
}

#pragma mark - Requests to the service

- (void)sendPreferencesUpdate {
    SF_ON_MAIN([self sendPreferencesUpdate]);
    if (!self.connection) { self.preferencesPending = YES; [self planReconnect]; return; }
    self.preferencesPending = NO;
    __weak SFServiceLink *weakSelf = self;
    [[self serviceWithFailure:^(NSError *error) {
        weakSelf.preferencesPending = YES;
        [weakSelf planReconnect];
    }] applicationRequestsPreferencesUpdate];
}

- (void)retryAfter:(double)seconds {
    SF_ON_MAIN([self retryAfter:seconds]);
    if (!self.connection) { SFLogEvent(SFLogLevelWarning, @"could not schedule retry: background service not connected"); return; }
    [[self serviceWithFailure:nil] applicationRequestsRetryAfter:seconds];
}

/// Tells the service we're done with what it woke us for (unless a signing pass still needs us).
- (void)doneWithTask {
    SF_ON_MAIN([self doneWithTask]);
    if (self.leaseID) return;
    [[self serviceWithFailure:nil] applicationDidFinishTask];
}

- (void)doneWithTaskIn:(NSTimeInterval)seconds {
    // The delay lets a just-posted notification get delivered first.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self doneWithTask]; });
}

#pragma mark - Staying awake while signing

- (void)requestLease {
    if (!self.leaseID) return;
    if (!self.connection) { [self planReconnect]; return; }
    NSString *leaseID = self.leaseID;
    __weak SFServiceLink *weakSelf = self;
    [[self serviceWithFailure:^(NSError *error) {
        if (![weakSelf.leaseID isEqualToString:leaseID]) return;
        NSLog(@"[Sevenfold] couldn't ask the background service to keep us awake: %@", error);
        [weakSelf planReconnect];
    }] applicationRequestsSigningAssertionWithIdentifier:leaseID];
}

- (void)applicationSigningDidStart {
    SF_ON_MAIN([self applicationSigningDidStart]);
    if (self.leaseID) return;   // a second request joins the pass that holds the lease
    self.leaseID = [NSUUID UUID].UUIDString;
    [self requestLease];
}

- (void)applicationSigningUpdateProgress:(int)percent forBundleIdentifier:(NSString *)bundleIdentifier {}
- (void)applicationSigningDidEncounterError:(NSError *)error forBundleIdentifier:(NSString *)bundleIdentifier {}

- (void)applicationSigningCompleteWithError:(NSError *)error {
    SF_ON_MAIN([self applicationSigningCompleteWithError:error]);
    if (error.code == SFErrorAlreadyUndertakingPipeline || !self.leaseID) return;
    NSString *finished = self.leaseID;
    self.leaseID = nil;
    [[self serviceWithFailure:nil] applicationDidFinishSigningWithIdentifier:finished];   // if lost, the service's 5-minute limit cleans up
}

#pragma mark - Calls from the service

- (void)daemonDidRequestNewBackgroundSigning {
    SF_ON_MAIN([self daemonDidRequestNewBackgroundSigning]);
    NSLog(@"[Sevenfold] background service asked for a run");

    BOOL answersTest = self.testAwaitingRun;
    if (answersTest) {
        self.testAwaitingRun = NO;
        NSUInteger generation = ++self.testGeneration;
        [self failTestIfStill:generation after:180 code:4 text:SFL(@"The background service started the test, but signing didn't finish. Check your connection and try again.")];
    }

    [[SFSigningSession shared] markNextRunAutomatic];
    UIApplication *application = [UIApplication sharedApplication];
    __block BOOL ended = NO;
    __block UIBackgroundTaskIdentifier task = UIBackgroundTaskInvalid;
    void (^end)(void) = ^{
        if (ended) return;
        ended = YES;
        if (task != UIBackgroundTaskInvalid) { [application endBackgroundTask:task]; task = UIBackgroundTaskInvalid; }
        [self doneWithTask];
    };
    task = [application beginBackgroundTaskWithName:@"Sevenfold automatic signing" expirationHandler:end];

    [[SFBackgroundSigningManager sharedInstance] attemptBackgroundSigningIfNecessaryWithCompletion:^(NSError *error) {
        if (answersTest) [self finishTest:error];
        // Give notifications 5 seconds to go out before letting the app be suspended.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), end);
    }];
}

- (void)daemonDidRequestCredentialsCheck {
    SF_ON_MAIN([self daemonDidRequestCredentialsCheck]);
    NSLog(@"[Sevenfold] background service asked for a sign-in check");
    BOOL signedIn = [SFResources getUsername].length && [SFResources getPassword].length &&
                    [[SFResources getCredentialsVersion] isEqualToString:CURRENT_CREDENTIALS_VERSION];
    if (signedIn) { [self doneWithTask]; return; }
    [[SFNotificationManager sharedInstance] sendNotificationWithTitle:SFL(@"Sign-in needed")
                                                                   body:SFL(@"Tap to sign in to Sevenfold. It's needed to keep your apps signed.")
                                                         isDebugMessage:NO isUrgentMessage:YES andNotificationID:@"login"];
    [self doneWithTaskIn:5];
}

- (void)daemonDidRequestQueuedNotification {
    SF_ON_MAIN([self daemonDidRequestQueuedNotification]);
    NSLog(@"[Sevenfold] background service asked for the queued notice");
    SFNotificationManager *notifications = [SFNotificationManager sharedInstance];
    if ([[SFBackgroundSigningManager sharedInstance] anyApplicationsNeedingSigning])
        [notifications sendNotificationWithTitle:SFL(@"Signing waiting") body:SFL(@"Unlock your iPhone to sign your apps.") isDebugMessage:NO isUrgentMessage:YES andNotificationID:@"sf.queued"];
    else
        [notifications sendNotificationWithTitle:@"DEBUG" body:SFL(@"Background check has been queued for next unlock.") isDebugMessage:YES isUrgentMessage:NO andNotificationID:nil];
    [self doneWithTaskIn:5];
}

#pragma mark - Diagnostics test

- (void)testBackgroundRunWithCompletion:(void (^)(NSError *))completion {
    SF_ON_MAIN([self testBackgroundRunWithCompletion:completion]);
    if (completion) [self.testCallbacks addObject:[completion copy]];
    if (self.testRunning) return;   // repeated taps join the running test

    self.testRunning = YES;
    self.testPending = YES;
    NSUInteger generation = ++self.testGeneration;
    [self failTestIfStill:generation after:30 code:3 text:SFL(@"The background service didn't start the test. Reinstall Sevenfold or restart your iPhone, then try again.")];

    if (!self.connection) { [self planReconnect]; return; }
    [self sendTest];
}

- (void)sendTest {
    if (!self.testPending || !self.connection) return;
    self.testPending = NO;
    self.testAwaitingRun = YES;
    __weak SFServiceLink *weakSelf = self;
    [[self serviceWithFailure:^(NSError *error) {
        weakSelf.testAwaitingRun = NO;
        weakSelf.testPending = YES;
        [weakSelf drop];
        [weakSelf planReconnect];
    }] applicationRequestsDebuggingBackgroundSigning];
}

- (void)failTestIfStill:(NSUInteger)generation after:(NSTimeInterval)seconds code:(NSInteger)code text:(NSString *)text {
    __weak SFServiceLink *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SFServiceLink *link = weakSelf;
        if (!link || !link.testRunning || link.testGeneration != generation) return;
        if (code == 3 && !link.testPending && !link.testAwaitingRun) return;   // the run already started
        [link finishTest:[NSError errorWithDomain:SFTestErrorDomain code:code userInfo:@{ NSLocalizedDescriptionKey: text }]];
    });
}

- (void)finishTest:(NSError *)error {
    self.testPending = NO;
    self.testAwaitingRun = NO;
    self.testRunning = NO;
    self.testGeneration++;
    NSArray *callbacks = [self.testCallbacks copy];
    [self.testCallbacks removeAllObjects];

    // Settings is no longer on screen: say how it went in a notification.
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) {
        BOOL nothingToDo = error.code == SFErrorNoSigningRequired;
        NSString *title = (!error || nothingToDo) ? SFL(@"Background signing works") : SFL(@"Background signing failed");
        NSString *body = nothingToDo ? SFL(@"The background check finished. No apps need signing right now.")
                                     : (error ? error.localizedDescription : SFL(@"The background signing test finished successfully."));
        [[SFNotificationManager sharedInstance] sendNotificationWithTitle:title body:body isDebugMessage:NO isUrgentMessage:YES andNotificationID:@"backgroundSigningTest"];
    }
    for (void (^callback)(NSError *) in callbacks) callback(error);
}

@end
