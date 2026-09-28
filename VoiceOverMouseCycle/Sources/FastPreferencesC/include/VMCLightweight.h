#ifndef VMC_LIGHTWEIGHT_H
#define VMC_LIGHTWEIGHT_H
#include <stdbool.h>

// Private API adapter; see Docs/LightweightBackendRelease.md.
typedef struct VMCFastPreferences VMCFastPreferences;
typedef enum {
    VMCFastOK = 0,
    VMCFastUnsupported,
    VMCFastUnavailable,
    VMCFastInvalidValue,
    VMCFastChanged,
    VMCFastSyncFailed,
    VMCFastReadbackFailed
} VMCFastResult;

bool VMCFastRuntimeSupported(void);
// Caller must check runtime support before creation. Arguments allow isolated
// test domains; the App always supplies its fixed VoiceOver domain/notice.
VMCFastPreferences *VMCFastCreate(const char *container, const char *domainPrefix,
                                const char *notificationName);
void VMCFastDestroy(VMCFastPreferences *preferences);
VMCFastResult VMCFastRead(VMCFastPreferences *preferences, bool *mouse, bool *vo);
VMCFastResult VMCFastCommit(VMCFastPreferences *preferences, bool expectedMouse, bool expectedVO);
#endif
