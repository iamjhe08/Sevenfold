//
//  libMobileGestalt.h
//  Sevenfold
//
//  BY: T4MAG0
//
//  The one MobileGestalt call Sevenfold uses: this iPhone's UDID.
//

#include <CoreFoundation/CoreFoundation.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Returns a +1 value for the given key (release it, or use CFBridgingRelease).
CFPropertyListRef MGCopyAnswer(CFStringRef key);

#define kMGUniqueDeviceID CFSTR("UniqueDeviceID")

#ifdef __cplusplus
}
#endif
