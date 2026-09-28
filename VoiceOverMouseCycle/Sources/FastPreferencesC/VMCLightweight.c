#include "VMCLightweight.h"
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

typedef CFPropertyListRef (*CopyValue)(CFStringRef, CFStringRef, CFStringRef);
typedef void (*SetValue)(CFStringRef, CFPropertyListRef, CFStringRef, CFStringRef);
typedef Boolean (*Sync)(CFStringRef, CFStringRef, CFStringRef, CFStringRef);
struct VMCFastPreferences {
    CopyValue copy;
    SetValue set;
    Sync sync;
    CFStringRef container, normal, master, journal, local, notification, profile;
    char preferencesPath[4096], portablePath[4096];
    bool baselineCaptured, committed;
};
#define VMC_MOUSE CFSTR("SCRConfigurationCursorTrackingMToVO")
#define VMC_VO CFSTR("SCRConfigurationCursorTrackingVOToM")

static bool image_matches(const char *suffix, const unsigned char uuid[16]) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; ++i) {
        const char *name = _dyld_get_image_name(i);
        if (!name || strlen(name) < strlen(suffix) || strcmp(name + strlen(name) - strlen(suffix), suffix)) continue;
        const struct mach_header *header = _dyld_get_image_header(i);
        if (!header || header->magic != MH_MAGIC_64) return false;
        const struct mach_header_64 *h = (const struct mach_header_64 *)header;
        const unsigned char *cursor = (const unsigned char *)(h + 1), *end = cursor + h->sizeofcmds;
        for (uint32_t j = 0; j < h->ncmds; ++j) {
            if ((size_t)(end - cursor) < sizeof(struct load_command)) return false;
            const struct load_command *command = (const struct load_command *)cursor;
            if (command->cmdsize < sizeof(*command) || command->cmdsize > (size_t)(end - cursor)) return false;
            if (command->cmd == LC_UUID && command->cmdsize >= sizeof(struct uuid_command))
                return memcmp(((const struct uuid_command *)command)->uuid, uuid, 16) == 0;
            cursor += command->cmdsize;
        }
        return false;
    }
    return false;
}

bool VMCFastRuntimeSupported(void) {
    // Exact inspected binary contracts, NOT an OS version heuristic. An update
    // or another architecture falls back to the selector/ABI-checked backend.
    // No sharedUserDefaults or object initialization is performed here.
    if (!dlopen("/System/Library/PrivateFrameworks/ScreenReaderCore.framework/ScreenReaderCore", RTLD_LAZY | RTLD_LOCAL)) return false;
    static const unsigned char scr[] = {0xee,0x2f,0xce,0xa2,0xa4,0xa2,0x30,0x02,0xbf,0x08,0x04,0x3a,0xc5,0x03,0x0a,0x23};
    static const unsigned char cf[] = {0xfd,0xba,0x22,0x43,0xa7,0xab,0x35,0x24,0x9b,0x94,0xf3,0x03,0x4a,0xc3,0x6e,0x41};
    return image_matches("/ScreenReaderCore.framework/Versions/A/ScreenReaderCore", scr) &&
           image_matches("/CoreFoundation.framework/Versions/A/CoreFoundation", cf);
}

static void *cf_symbol(const char *name) {
    void *value = dlsym(RTLD_DEFAULT, name);
    Dl_info info = {0};
    if (!value || !dladdr(value, &info) || !info.dli_fname ||
        !strstr(info.dli_fname, "/System/Library/Frameworks/CoreFoundation.framework/")) return NULL;
    return value;
}
VMCFastPreferences *VMCFastCreate(const char *container, const char *prefix, const char *notice) {
    if (!container || container[0] != '/' || !prefix || !notice || strchr(prefix, '/')) return NULL;
    VMCFastPreferences *p = calloc(1, sizeof(*p));
    if (!p) return NULL;
    p->copy = (CopyValue)cf_symbol("_CFPreferencesCopyAppValueWithContainer");
    p->set = (SetValue)cf_symbol("_CFPreferencesSetAppValueWithContainer");
    p->sync = (Sync)cf_symbol("_CFPreferencesSynchronizeWithContainer");
    p->container = CFStringCreateWithCString(NULL, container, kCFStringEncodingUTF8);
    p->notification = CFStringCreateWithCString(NULL, notice, kCFStringEncodingUTF8);
    CFStringRef base = CFStringCreateWithCString(NULL, prefix, kCFStringEncodingUTF8);
    if (base) {
        p->normal = CFStringCreateWithFormat(NULL, NULL, CFSTR("%@/default"), base);
        p->master = CFStringCreateWithFormat(NULL, NULL, CFSTR("%@/master"), base);
        p->journal = CFStringCreateWithFormat(NULL, NULL, CFSTR("%@/journal"), base);
        p->local = CFStringCreateWithFormat(NULL, NULL, CFSTR("%@.local"), base);
        CFRelease(base);
    }
    int a = snprintf(p->preferencesPath, sizeof(p->preferencesPath), "%s/Library/Preferences", container);
    int b = snprintf(p->portablePath, sizeof(p->portablePath), "%s/%s.portable", p->preferencesPath, prefix);
    if (!p->copy || !p->set || !p->sync || !p->container || !p->notification || !p->normal || !p->master ||
        !p->journal || !p->local || a < 0 || (size_t)a >= sizeof(p->preferencesPath) || b < 0 || (size_t)b >= sizeof(p->portablePath)) {
        VMCFastDestroy(p); return NULL;
    }
    return p;
}
void VMCFastDestroy(VMCFastPreferences *p) {
    if (!p) return;
    const CFTypeRef fields[] = {p->container,p->normal,p->master,p->journal,p->local,p->notification,p->profile};
    for (unsigned i = 0; i < sizeof(fields)/sizeof(fields[0]); i++) if (fields[i]) CFRelease(fields[i]);
    free(p);
}
static bool sync_domain(VMCFastPreferences *p, CFStringRef domain) {
    return p->sync(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost, p->container);
}
static VMCFastResult markers(VMCFastPreferences *p) {
    // lstat distinguishes a missing marker from denied inspection, and catches
    // dangling links. Any portable linkage or merge marker uses the old backend.
    int fd = open(p->preferencesPath, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    if (fd < 0) return VMCFastUnavailable;
    close(fd);
    struct stat st;
    if (lstat(p->portablePath, &st) == 0) return VMCFastUnsupported;
    if (errno != ENOENT) return VMCFastUnavailable;
    if (lstat("/private/tmp/vosynchronizing", &st) == 0) return VMCFastUnsupported;
    if (errno != ENOENT) return VMCFastUnsupported;
    return VMCFastOK;
}
static bool boolean(CFTypeRef value, bool *out) {
    if (!value) return false;
    if (CFGetTypeID(value) == CFBooleanGetTypeID()) { *out = CFBooleanGetValue(value); return true; }
    double n;
    if (CFGetTypeID(value) != CFNumberGetTypeID() || !CFNumberGetValue(value, kCFNumberDoubleType, &n) || (n != 0 && n != 1)) return false;
    *out = n != 0; return true;
}
VMCFastResult VMCFastRead(VMCFastPreferences *p, bool *mouse, bool *vo) {
    if (!p || !mouse || !vo) return VMCFastUnavailable;
    VMCFastResult result = markers(p);
    if (result != VMCFastOK) return result;
    // Refresh before comparison; never cache permission or profile selection.
    if (!sync_domain(p, p->master) || !sync_domain(p, p->normal)) return VMCFastSyncFailed;
    CFTypeRef profile = p->copy(CFSTR("currentProfile"), p->master, p->container);
    // The inspected implementation uses nil for the default profile. A nil
    // TRACKING value is always unavailable, never false.
    if (profile && (CFGetTypeID(profile) != CFStringGetTypeID() || !CFEqual(profile, CFSTR("default")))) {
        CFRelease(profile); return VMCFastUnsupported;
    }
    if (p->baselineCaptured && !((!profile && !p->profile) || (profile && p->profile && CFEqual(profile,p->profile)))) {
        if (profile) CFRelease(profile);
        return VMCFastChanged;
    }
    CFTypeRef a = p->copy(VMC_MOUSE, p->normal, p->container);
    CFTypeRef b = p->copy(VMC_VO, p->normal, p->container);
    result = !a || !b ? VMCFastUnavailable : (boolean(a,mouse) && boolean(b,vo) ? VMCFastOK : VMCFastInvalidValue);
    if (a) CFRelease(a);
    if (b) CFRelease(b);
    if (result == VMCFastOK && !p->baselineCaptured) {
        p->profile = profile; profile = NULL; p->baselineCaptured = true;
    }
    if (profile) CFRelease(profile);
    return result;
}
static CFDictionaryRef notice(VMCFastPreferences *p, CFStringRef key, bool value) {
    CFMutableDictionaryRef info = CFDictionaryCreateMutable(NULL, 3, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    if (!info) return NULL;
    int zero = 0;
    CFNumberRef proxy = CFNumberCreate(NULL, kCFNumberIntType, &zero);
    if (!proxy) { CFRelease(info); return NULL; }
    CFDictionarySetValue(info, CFSTR("SCRCUserDefaultsProxyType"), proxy);
    CFRelease(proxy);
    if (p->profile) CFDictionarySetValue(info, CFSTR("profileKey"), p->profile);
    CFDictionarySetValue(info, key, value ? kCFBooleanTrue : kCFBooleanFalse);
    return info;
}
VMCFastResult VMCFastCommit(VMCFastPreferences *p, bool expectedMouse, bool expectedVO) {
    if (!p || !p->baselineCaptured || p->committed) return VMCFastChanged;
    bool mouse, vo;
    VMCFastResult result = VMCFastRead(p, &mouse, &vo);
    if (result != VMCFastOK) return result;
    if (mouse != expectedMouse || vo != expectedVO) return VMCFastChanged;
    const bool nextMouse = !mouse && !vo, nextVO = mouse && !vo;
    CFStringRef keys[] = {nextMouse ? VMC_VO : VMC_MOUSE, nextMouse ? VMC_MOUSE : VMC_VO};
    bool values[] = {false, nextMouse || nextVO};
    CFDictionaryRef messages[] = {notice(p,keys[0],values[0]),notice(p,keys[1],values[1])};
    double now = CFAbsoluteTimeGetCurrent();
    CFNumberRef timestamp = CFNumberCreate(NULL,kCFNumberDoubleType,&now);
    if (!messages[0] || !messages[1] || !timestamp) {
        if (messages[0]) CFRelease(messages[0]);
        if (messages[1]) CFRelease(messages[1]);
        if (timestamp) CFRelease(timestamp);
        return VMCFastUnavailable;
    }
    // Last check immediately before the first write. There is no atomic lock
    // shared with VoiceOver; profile/device changes can still race the operation.
    result = markers(p);
    if (result == VMCFastOK) {
        p->committed = true; // No fallback/retry after even one real write.
        for (int i=0; i<2; i++) {
            p->set(keys[i],values[i] ? kCFBooleanTrue : kCFBooleanFalse,p->normal,p->container);
            p->set(keys[i],timestamp,p->journal,p->container);
        }
        // In the inspected non-portable path currentPortableIdentifier is nil.
        // The framework clears lastTouchedKey on its first journal update.
        p->set(CFSTR("lastTouchedKey"),NULL,p->local,p->container);
        bool normalSynced = sync_domain(p,p->normal);
        bool journalSynced = sync_domain(p,p->journal);
        bool localSynced = sync_domain(p,p->local);
        if (!normalSynced || !journalSynced || !localSynced) result = VMCFastSyncFailed;
        if (result == VMCFastOK) result = VMCFastRead(p,&mouse,&vo);
        if (result == VMCFastOK && (mouse != nextMouse || vo != nextVO)) result = VMCFastReadbackFailed;
        if (result == VMCFastOK) {
            CFNotificationCenterRef center = CFNotificationCenterGetDistributedCenter();
            for (int i=0; i<2; i++) CFNotificationCenterPostNotification(center,p->notification,CFSTR("bcst"),messages[i],false);
        }
    }
    CFRelease(timestamp);
    CFRelease(messages[0]); CFRelease(messages[1]);
    return result;
}
