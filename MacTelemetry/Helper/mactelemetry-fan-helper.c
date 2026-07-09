/*
 * macmonitor-fan-helper
 *
 * A tiny privileged helper that writes Apple SMC fan-control keys. Installed once at
 * /Library/PrivilegedHelperTools, owned by root with the setuid bit set, so MacMonitor
 * (running unprivileged) can force/restore fan speed without a password prompt on every write.
 *
 * SMC *reads* need no special privilege on macOS -- only writes do (IOConnectCallStructMethod
 * returns kIOReturnNotPrivileged / 0xe00002c1 for an unprivileged write attempt on every
 * current macOS release, Intel and Apple Silicon alike). Hence this helper exists.
 *
 * Commands:
 *   macmonitor-fan-helper set <fanIndex> <rpm>   Force fanIndex to spin at rpm.
 *   macmonitor-fan-helper auto <fanIndex>        Restore automatic control for fanIndex.
 *
 * Exit code 0 on success, non-zero otherwise (message on stderr).
 */

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    UInt32 dataSize;
    UInt32 dataType;
    UInt8 dataAttributes;
} SMCKeyInfo;

typedef struct {
    UInt32 key;
    UInt8 vers[6];
    UInt8 pLimitData[16];
    SMCKeyInfo keyInfo;
    UInt16 padding;
    UInt8 result;
    UInt8 status;
    UInt8 data8;
    UInt32 data32;
    UInt8 bytes[32];
} SMCParam;

enum { kSMCReadBytes = 5, kSMCWriteBytes = 6, kSMCReadKeyInfo = 9 };

static UInt32 fourCC(const char *s) {
    return ((UInt32)(unsigned char)s[0] << 24) | ((UInt32)(unsigned char)s[1] << 16) |
           ((UInt32)(unsigned char)s[2] << 8) | (UInt32)(unsigned char)s[3];
}

static kern_return_t smcCall(io_connect_t conn, SMCParam *in, SMCParam *out) {
    size_t outSize = sizeof(*out);
    return IOConnectCallStructMethod(conn, 2, in, sizeof(*in), out, &outSize);
}

static int smcOpen(io_connect_t *conn) {
    CFMutableDictionaryRef matching = IOServiceMatching("AppleSMC");
    if (!matching) return 0;

    io_iterator_t iterator;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) != kIOReturnSuccess) return 0;

    io_object_t device = IOIteratorNext(iterator);
    IOObjectRelease(iterator);
    if (!device) return 0;

    kern_return_t result = IOServiceOpen(device, mach_task_self(), 0, conn);
    IOObjectRelease(device);
    return result == kIOReturnSuccess;
}

static int readKeyInfo(io_connect_t conn, const char *key, UInt32 *dataSize) {
    SMCParam in = {0}, out = {0};
    in.key = fourCC(key);
    in.data8 = kSMCReadKeyInfo;
    if (smcCall(conn, &in, &out) != kIOReturnSuccess) return 0;
    *dataSize = out.keyInfo.dataSize;
    return 1;
}

static int readKeyBytes(io_connect_t conn, const char *key, UInt32 dataSize, UInt8 *outBytes) {
    SMCParam in = {0}, out = {0};
    in.key = fourCC(key);
    in.keyInfo.dataSize = dataSize;
    in.data8 = kSMCReadBytes;
    if (smcCall(conn, &in, &out) != kIOReturnSuccess) return 0;
    memcpy(outBytes, out.bytes, sizeof(out.bytes));
    return 1;
}

static int writeKeyBytes(io_connect_t conn, const char *key, UInt32 dataSize, const UInt8 *bytes) {
    SMCParam in = {0}, out = {0};
    in.key = fourCC(key);
    in.keyInfo.dataSize = dataSize;
    memcpy(in.bytes, bytes, dataSize);
    in.data8 = kSMCWriteBytes;
    return smcCall(conn, &in, &out) == kIOReturnSuccess;
}

static int readU8(io_connect_t conn, const char *key, UInt8 *value) {
    UInt32 dataSize;
    UInt8 bytes[32];
    if (!readKeyInfo(conn, key, &dataSize) || dataSize < 1) return 0;
    if (!readKeyBytes(conn, key, dataSize, bytes)) return 0;
    *value = bytes[0];
    return 1;
}

/* Per-fan forced-mode key ("F{n}Md": 0 = auto, 1 = forced). Not present on every SMC
 * generation -- that's not an error, it just means this Mac relies on the legacy "FS! "
 * bitmask instead (tried by the caller as a fallback). */
static int setFanMode(io_connect_t conn, int fan, UInt8 mode) {
    char key[5];
    snprintf(key, sizeof(key), "F%dMd", fan);
    UInt32 dataSize;
    if (!readKeyInfo(conn, key, &dataSize) || dataSize < 1) return 0;
    UInt8 bytes[32] = {0};
    bytes[0] = mode;
    return writeKeyBytes(conn, key, dataSize, bytes);
}

/* Legacy manual-control bitmask, one bit per fan (Intel Macs). */
static int setManualBit(io_connect_t conn, int fan, int enabled) {
    UInt32 dataSize;
    UInt8 bytes[32];
    if (!readKeyInfo(conn, "FS! ", &dataSize) || dataSize < 2) return 0;
    if (!readKeyBytes(conn, "FS! ", dataSize, bytes)) return 0;

    UInt16 mask = ((UInt16)bytes[0] << 8) | bytes[1];
    if (enabled) {
        mask |= (UInt16)(1u << fan);
    } else {
        mask &= (UInt16)~(1u << fan);
    }

    UInt8 out[32] = {0};
    out[0] = (mask >> 8) & 0xFF;
    out[1] = mask & 0xFF;
    return writeKeyBytes(conn, "FS! ", dataSize, out);
}

/* Encodes RPM into "F{n}Tg", auto-detecting fpe2 (2-byte fixed point, Intel) vs
 * flt (4-byte float, Apple Silicon) from the key's reported size. */
static int setFanTarget(io_connect_t conn, int fan, double rpm) {
    char key[5];
    snprintf(key, sizeof(key), "F%dTg", fan);
    UInt32 dataSize;
    if (!readKeyInfo(conn, key, &dataSize)) return 0;

    UInt8 bytes[32] = {0};
    if (dataSize == 4) {
        float f = (float)rpm;
        memcpy(bytes, &f, sizeof(f));
    } else if (dataSize == 2) {
        UInt16 fixed = (UInt16)(rpm * 4.0 + 0.5);
        bytes[0] = (fixed >> 8) & 0xFF;
        bytes[1] = fixed & 0xFF;
    } else {
        return 0;
    }
    return writeKeyBytes(conn, key, dataSize, bytes);
}

static int fanCount(io_connect_t conn) {
    UInt8 value = 0;
    return readU8(conn, "FNum", &value) ? value : 0;
}

int main(int argc, char **argv) {
    if (argc < 3 || (strcmp(argv[1], "set") != 0 && strcmp(argv[1], "auto") != 0)) {
        fprintf(stderr, "usage: %s set <fan> <rpm>\n       %s auto <fan>\n", argv[0], argv[0]);
        return 2;
    }

    io_connect_t conn;
    if (!smcOpen(&conn)) {
        fprintf(stderr, "error: could not open AppleSMC\n");
        return 1;
    }

    int fans = fanCount(conn);
    int fan = atoi(argv[2]);
    if (fans <= 0 || fan < 0 || fan >= fans) {
        fprintf(stderr, "error: fan index %d out of range (0..%d)\n", fan, fans - 1);
        IOServiceClose(conn);
        return 1;
    }

    int ok;
    if (strcmp(argv[1], "set") == 0) {
        if (argc < 4) {
            fprintf(stderr, "error: missing rpm\n");
            IOServiceClose(conn);
            return 2;
        }
        double rpm = atof(argv[3]);
        if (rpm < 0) rpm = 0;
        if (rpm > 10000) rpm = 10000;

        if (!setFanMode(conn, fan, 1)) {
            setManualBit(conn, fan, 1);
        }
        ok = setFanTarget(conn, fan, rpm);
    } else {
        int modeOk = setFanMode(conn, fan, 0);
        int bitOk = setManualBit(conn, fan, 0);
        ok = modeOk || bitOk;
    }

    IOServiceClose(conn);
    if (!ok) {
        fprintf(stderr, "error: SMC write failed\n");
        return 1;
    }
    return 0;
}
