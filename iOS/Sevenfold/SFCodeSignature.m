//
//  SFCodeSignature.m
//  Sevenfold
//

#import "SFCodeSignature.h"
#include "SFCodeSignatureCore.h"

NSString *SFSigningCertificateSerialForApp(NSURL *appBundleURL) {
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfURL:[appBundleURL URLByAppendingPathComponent:@"Info.plist"]];
    NSString *executable = info[@"CFBundleExecutable"];
    if (![executable isKindOfClass:[NSString class]] || executable.length == 0) return nil;
    NSData *file = [NSData dataWithContentsOfURL:[appBundleURL URLByAppendingPathComponent:executable] options:NSDataReadingMappedIfSafe error:nil];
    if (file.length == 0) return nil;
    char serial[128] = {0};
    if (!SFSigningSerialFromExecutable(file.bytes, file.length, serial, sizeof(serial))) return nil;
    return [NSString stringWithUTF8String:serial];
}
