//
//  SFSRPLayout.m
//  Sevenfold
//
//  BY: T4MAG0
//
//  corecrypto's SRP context changed shape in iOS 14. The header's ccsrp_ctx_ccn()
//  calls this to find the number storage for whichever layout this iOS uses.
//

#import <Foundation/Foundation.h>
#import <corecrypto/ccsrp.h>

cc_unit *srp_ccn(void *srp) {
    static BOOL modern;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        modern = [[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){ 14, 0, 0 }];
    });
    return modern ? SRP_CCN((ccsrp_ctx_t)srp) : SRP_CCN((ccsrp_ctx_t_legacy)srp);
}
