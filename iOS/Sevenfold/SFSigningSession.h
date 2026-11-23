//
//  SFSigningSession.h
//  Sevenfold
//
//  Tracks the current signing run for the progress screen, and when it ends
//  records the result and sends the success / failure notification.
//

#import <UIKit/UIKit.h>
#import "SFApplicationSigning.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const SFSigningSessionDidChangeNotification;

typedef NS_ENUM(NSInteger, SFSigningItemState) {
    SFSigningItemWaiting,
    SFSigningItemActive,
    SFSigningItemDone,
    SFSigningItemFailed,
};

@interface SFSigningItem : NSObject
@property (nonatomic, copy) NSString *bundleIdentifier;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong, nullable) UIImage *icon;
@property (nonatomic) int progress;
@property (nonatomic) SFSigningItemState state;
@property (nonatomic, copy, nullable) NSString *errorMessage;
/// Apple's full error text, shown when the row is tapped.
@property (nonatomic, copy, nullable) NSString *fullError;
- (NSString *)stepText;
@end

@interface SFSigningSession : NSObject <SFApplicationSigningProtocol>

+ (instancetype)shared;

@property (nonatomic, readonly) BOOL running;
@property (nonatomic, readonly) BOOL finished;
@property (nonatomic, readonly) BOOL automatic;
@property (nonatomic, readonly, nullable) NSDate *startDate;
@property (nonatomic, readonly, nullable) NSDate *endDate;
@property (nonatomic, readonly) NSArray<SFSigningItem *> *items;
@property (nonatomic, readonly, nullable) NSString *runError;
@property (nonatomic, readonly) BOOL stopRequested;

/// Called before a run starts so the screen can list the apps straight away.
- (void)prepareWithApplications:(NSArray *)applications automatic:(BOOL)automatic;
- (void)markNextRunAutomatic;
- (void)requestStopAfterCurrent;

- (float)overallProgress;
- (NSUInteger)doneCount;
- (NSUInteger)failedCount;
- (nullable SFSigningItem *)activeItem;

/// Sign every app from this Apple ID now (the "Sign all apps now" button).
- (BOOL)signAllNow;
/// Sign the given SFApplication objects now.
- (BOOL)signApplications:(NSArray *)applications;

@end

NS_ASSUME_NONNULL_END
