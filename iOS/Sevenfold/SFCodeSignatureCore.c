//
//  SFCodeSignatureCore.c
//  Sevenfold
//

#include "SFCodeSignatureCore.h"
#include <string.h>
#include <openssl/pkcs7.h>
#include <openssl/x509.h>
#include <openssl/bn.h>
#include <openssl/objects.h>
#include <openssl/crypto.h>

static uint32_t sf_be32(const uint8_t *p) { return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | p[3]; }
static uint32_t sf_le32(const uint8_t *p) { return ((uint32_t)p[3] << 24) | ((uint32_t)p[2] << 16) | ((uint32_t)p[1] << 8) | p[0]; }

// Finds the CMS blob in a thin 64-bit little-endian Mach-O.
static const uint8_t *sf_cms_from_macho(const uint8_t *base, size_t size, size_t *cmsLength) {
    if (size < 32 || sf_le32(base) != 0xfeedfacfu) return NULL;
    uint32_t ncmds = sf_le32(base + 16);
    size_t cursor = 32;
    for (uint32_t i = 0; i < ncmds && cursor + 8 <= size; i++) {
        uint32_t type = sf_le32(base + cursor), cmdsize = sf_le32(base + cursor + 4);
        if (cmdsize < 8 || cursor + cmdsize > size) break;
        if (type == 0x1d && cmdsize >= 16) { // LC_CODE_SIGNATURE
            uint32_t dataoff = sf_le32(base + cursor + 8), datasize = sf_le32(base + cursor + 12);
            if ((size_t)dataoff + datasize > size || datasize < 12) return NULL;
            const uint8_t *sb = base + dataoff;
            if (sf_be32(sb) != 0xfade0cc0u) return NULL; // embedded signature superblob
            uint32_t count = sf_be32(sb + 8);
            for (uint32_t j = 0; j < count && 12 + (size_t)(j + 1) * 8 <= datasize; j++) {
                uint32_t offset = sf_be32(sb + 12 + j * 8 + 4);
                if ((size_t)offset + 8 > datasize) continue;
                const uint8_t *blob = sb + offset;
                if (sf_be32(blob) == 0xfade0b01u) { // CMS signature blob
                    uint32_t length = sf_be32(blob + 4);
                    if (length <= 8 || (size_t)offset + length > datasize) return NULL;
                    *cmsLength = length - 8;
                    return blob + 8;
                }
            }
            return NULL;
        }
        cursor += cmdsize;
    }
    return NULL;
}

static const uint8_t *sf_find_cms(const uint8_t *data, size_t length, size_t *cmsLength) {
    if (length < 8) return NULL;
    uint32_t magic = sf_be32(data);
    if (magic == 0xcafebabeu || magic == 0xcafebabfu) {
        int fat64 = magic == 0xcafebabfu;
        uint32_t n = sf_be32(data + 4);
        size_t entry = fat64 ? 32 : 20;
        for (uint32_t i = 0; i < n && 8 + (size_t)(i + 1) * entry <= length; i++) {
            const uint8_t *e = data + 8 + i * entry;
            if (sf_be32(e) != 0x0100000cu) continue; // arm64
            uint64_t off = fat64 ? (((uint64_t)sf_be32(e + 8) << 32) | sf_be32(e + 12)) : sf_be32(e + 8);
            uint64_t sz = fat64 ? (((uint64_t)sf_be32(e + 16) << 32) | sf_be32(e + 20)) : sf_be32(e + 12);
            if (off + sz > length) continue;
            const uint8_t *cms = sf_cms_from_macho(data + off, (size_t)sz, cmsLength);
            if (cms) return cms;
        }
        return NULL;
    }
    return sf_cms_from_macho(data, length, cmsLength);
}

int SFSigningSerialFromExecutable(const uint8_t *data, size_t length, char *out, size_t outLength) {
    size_t cmsLength = 0;
    const uint8_t *cms = sf_find_cms(data, length, &cmsLength);
    if (!cms || !out || outLength < 2) return 0;
    const unsigned char *cursor = cms;
    PKCS7 *p7 = d2i_PKCS7(NULL, &cursor, (long)cmsLength);
    if (!p7) return 0;
    int ok = 0;
    if (PKCS7_type_is_signed(p7) && p7->d.sign) {
        STACK_OF(X509) *certs = p7->d.sign->cert;
        STACK_OF(PKCS7_SIGNER_INFO) *signers = p7->d.sign->signer_info;
        X509 *signer = NULL;
        if (certs && signers && sk_PKCS7_SIGNER_INFO_num(signers) > 0) {
            PKCS7_SIGNER_INFO *si = sk_PKCS7_SIGNER_INFO_value(signers, 0);
            if (si && si->issuer_and_serial)
                signer = X509_find_by_issuer_and_serial(certs, si->issuer_and_serial->issuer, si->issuer_and_serial->serial);
        }
        for (int i = 0; !signer && certs && i < sk_X509_num(certs); i++) {
            X509 *candidate = sk_X509_value(certs, i);
            char cn[256] = {0};
            X509_NAME_get_text_by_NID(X509_get_subject_name(candidate), NID_commonName, cn, sizeof(cn) - 1);
            if (strstr(cn, "Development") || strstr(cn, "Developer:")) signer = candidate;
        }
        if (signer) {
            BIGNUM *bn = ASN1_INTEGER_to_BN(X509_get_serialNumber(signer), NULL);
            char *hex = bn ? BN_bn2hex(bn) : NULL;
            if (hex) {
                const char *p = hex;
                while (*p == '0' && p[1]) p++;
                strncpy(out, p, outLength - 1);
                out[outLength - 1] = 0;
                for (char *c = out; *c; c++) if (*c >= 'a' && *c <= 'f') *c -= 32;
                ok = 1;
                OPENSSL_free(hex);
            }
            if (bn) BN_free(bn);
        }
    }
    PKCS7_free(p7);
    return ok;
}
