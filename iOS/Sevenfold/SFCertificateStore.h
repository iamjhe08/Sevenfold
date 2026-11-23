//
//  SFCertificateStore.h
//  Sevenfold
//
//  Lists the Apple ID's signing certificates, works out which iPhones use
//  each one, and moves a certificate between your own iPhones.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SFCertificate : NSObject
@property (nonatomic, copy) NSString *identifier;      // Apple's certificate id (for revoking)
@property (nonatomic, copy) NSString *serialNumber;
@property (nonatomic, copy) NSString *machineName;     // raw label from Apple
@property (nonatomic, copy) NSString *machineId;
@property (nonatomic, strong, nullable) NSDate *expirationDate;
@property (nonatomic) BOOL usedByThisDevice;
@property (nonatomic) BOOL madeBySevenfold;
/// Names of apps on this iPhone whose signature uses this certificate.
@property (nonatomic, copy) NSArray<NSString *> *appsSignedHere;
/// Models of the Apple ID's other registered iPhones (filled in by the Certificates screen).
@property (nonatomic, copy, nullable) NSArray<NSString *> *otherRegisteredModels;
/// "Sevenfold", "iloader", "AltStore / SideStore", …
- (NSString *)toolName;
/// "iPhone 15 Pro Max" for Sevenfold certificates, else the raw label.
- (NSString *)creatorName;
/// Models known to use this certificate: this iPhone and any shared with/from.
- (NSArray<NSString *> *)usedByDescriptions;
@end

@interface SFRegisteredDevice : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *model;
@property (nonatomic, copy) NSString *udid;
@property (nonatomic) BOOL isThisDevice;
@end

@interface SFCertificateStore : NSObject

+ (void)fetchCertificatesWithCompletion:(void (^)(NSArray<SFCertificate *> * _Nullable certificates, NSError * _Nullable error))completion;
+ (void)fetchRegisteredDevicesWithCompletion:(void (^)(NSArray<SFRegisteredDevice *> * _Nullable devices, NSError * _Nullable error))completion;
+ (void)revokeCertificate:(SFCertificate *)certificate completion:(void (^)(NSError * _Nullable error))completion;

/// Called after a successful run: notes that this iPhone signs with the active certificate.
+ (void)recordThisDeviceUsesActiveCertificate;
+ (BOOL)hasPrivateKey;

/// Writes an encrypted .sevenfold-cert file and returns its URL.
+ (nullable NSURL *)exportCertificateWithPassword:(NSString *)password error:(NSError **)error;
/// Imports a .sevenfold-cert file. On success this iPhone uses the shared certificate.
+ (BOOL)importCertificateAtURL:(NSURL *)url password:(NSString *)password summary:(NSString * _Nullable * _Nullable)summary error:(NSError **)error;

/// Number of iPhones this one has shared its certificate with.
+ (NSInteger)sharedWithCount;

@end

NS_ASSUME_NONNULL_END
