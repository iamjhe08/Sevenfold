//
//  SFCodeSignatureCore.h
//  Sevenfold
//
//  Plain C: finds the signing certificate's serial in a Mach-O executable.
//

#ifndef SFCodeSignatureCore_h
#define SFCodeSignatureCore_h

#include <stddef.h>
#include <stdint.h>

/// Writes the uppercase hex serial (no leading zeros) into `out`.
/// Returns 1 on success, 0 if there is no certificate signature.
int SFSigningSerialFromExecutable(const uint8_t *data, size_t length, char *out, size_t outLength);

#endif
