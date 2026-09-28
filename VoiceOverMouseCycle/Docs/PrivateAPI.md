# Private API mechanism and compatibility limits

## Starting point: the existing utility

The reference is `pmartz/vo-ignore` at
`c7641a18acfea45625ffaefc98c5eb088e052d16`. Its Swift executable loads
`/System/Library/PrivateFrameworks/ScreenReaderCore.framework`, finds
`SCRCUserDefaults`, calls `sharedUserDefaults`, writes both tracking keys false
through `setValue:forKey:`, and calls `synchronize`. Its confirmation uses
AVFoundation. Its AppleScript wrapper launches that executable; it does not ask
VoiceOver itself to speak.

The companion retains that preference mechanism as its general backend and adds
a guarded, equivalent C path for one inspected binary/configuration contract.
It does not manipulate the VoiceOver Utility UI, restart VoiceOver, or assume a
raw plist edit will update the running screen reader.

## Tracking values

| Mode | SCRConfigurationCursorTrackingMToVO | SCRConfigurationCursorTrackingVOToM |
|---|---|---|
| Ignore VoiceOver cursor | false | false |
| Mouse follows VoiceOver cursor | true | false |
| VoiceOver cursor follows mouse | false | true |

Inspection of the macOS 26.6 VoiceOver Utility's mouse-menu handler found these
three combinations; it did not produce true/true. The companion treats true/true
as an invalid state and normalizes it to Ignore. Invalid-state tests operate on
isolated preferences, not a user's live configuration.

## Checked SCRCUserDefaults backend

`PrivatePreferences.swift` dynamically resolves each method and verifies its
return and argument types before converting its implementation to a C-compatible
function pointer. It checks methods on the actual returned object class, not
just the initial class name.

| Selector | Observed encoding on 26.6 | Use |
|---|---|---|
| `+sharedUserDefaults` | `@16@0:8` | Shared preference object |
| `-valueForKey:` | `@24@0:8@16` | Read tracking value |
| `-setValue:forKey:` | `v32@0:8@16@24` | Write tracking value |
| `-setFamilyMember:` | `v24@0:8q16` | Establish notification-family identity |
| `-synchronizeWhileIWait` | `v16@0:8` | Finish framework synchronization |

Runtime validation checks type components and argument counts, rather than
requiring an entire compiler-generated offset string to match. The declared
function-pointer types must still match the private implementation.

The important live-update finding on the investigated 26.6 framework was:

1. `sharedUserDefaults` alone left `_familyMemberString` nil.
2. `_setValue:forKey:proxy:` skipped its distributed-notification construction
   when that field was nil. Persisting and reading back a value therefore did
   not establish that running VoiceOver had received it.
3. `setFamilyMember:4` established the framework's `bcst` identity. The code
   locates `_familyMemberString` through Objective-C runtime metadata, checks
   that it is an object/NSString ivar, calls the method, and reads the actual
   string back. If it is not `bcst`, it stops before tracking writes.
4. The setter then uses the framework's distributed notification mechanism:
   `SCRCUserDefaultsChangeDefaultsNotification`, sent by
   `NSDistributedNotificationCenter` with sender identity `bcst`.
5. `synchronize` schedules work asynchronously in that implementation.
   `synchronizeWhileIWait` runs the corresponding synchronization work before
   returning. It does not replace the missing notification-family setup.

The inspected family table was `scrd`, `scro`, `vou`, `scui`, `bcst`. The code
checks the result of the numeric index instead of assuming it is unchanged on
another OS. It never writes the ivar or relies on a hard-coded memory offset.
Registration also sends the framework's member-launch notification; this may
interact with existing portable preferences. Portable-preference behavior is not
claimed as physically verified by this contribution.

The framework path is:

```text
load framework and validate private ABI
  -> sharedUserDefaults
  -> read both tracking values
  -> setFamilyMember:4 and verify bcst
  -> reread and require unchanged starting state
  -> clear opposite flag, write next flag
  -> synchronizeWhileIWait
  -> readback validation
  -> optional VoiceOver output
```

The framework synchronizer returns void; Swift cannot get a success Boolean from
it. Same-process readback can still involve framework caches. Real cursor
behavior and actual speech remain separate acceptance checks.

## Guarded C fast path

`VMCLightweight.c` avoids initializing the shared preference object only when
both loaded Apple framework image UUIDs match the inspected contract:

- ScreenReaderCore: `EE2FCEA2-A4A2-3002-BF08-043AC5030A23`
- CoreFoundation: `FDBA2243-A7AB-3524-9B94-F3034AC36E41`

These are Mach-O **framework build identifiers**, not identifiers of a user's
Mac. They are intentionally kept in the public source. An unknown binary or
architecture falls back to the checked framework backend. This is not a test of
the marketing OS version.

The private C functions are resolved with `dlsym`; `dladdr` must identify the
expected CoreFoundation provider:

```c
CFPropertyListRef _CFPreferencesCopyAppValueWithContainer(
    CFStringRef key, CFStringRef application, CFStringRef container);
void _CFPreferencesSetAppValueWithContainer(
    CFStringRef key, CFPropertyListRef value,
    CFStringRef application, CFStringRef container);
Boolean _CFPreferencesSynchronizeWithContainer(
    CFStringRef application, CFStringRef user,
    CFStringRef host, CFStringRef container);
```

These declarations describe observed private ABI, not public Apple headers.
Symbol existence alone is insufficient to enable this backend.

The container path is derived from the current user's home directory at runtime:
`Library/Group Containers/group.com.apple.VoiceOver`. The application domains are
`com.apple.VoiceOver4/master`, `/default`, `/journal`, and
`com.apple.VoiceOver4.local`.

Before a direct operation, the backend:

- Synchronizes master/default and validates both tracking values.
- Accepts only a missing `currentProfile` or the explicit string `default`.
  Missing profile is the observed default-profile convention; missing tracking
  values are always unavailable, never false.
- Checks for `Library/Preferences/com.apple.VoiceOver4.portable` with `lstat`,
  including dangling symlinks, and for `/private/tmp/vosynchronizing`.
- Treats denied/failed marker inspection as unavailable/unsupported, not proof
  that a portable configuration is absent.
- Records the starting state/profile and checks again before the first write.

Writes are staged by Swift and must match exactly the expected two-key
transition. At commit the C code writes the new values in the safe order,
records journal timestamps for both keys, clears local `lastTouchedKey` in the
observed non-portable case, synchronizes default/journal/local, and rereads.
Only after those checks does it post two distributed notifications in write
order. Each notification uses:

| Item | Value |
|---|---|
| Name | `SCRCUserDefaultsChangeDefaultsNotification` |
| Object | `bcst` |
| `SCRCUserDefaultsProxyType` | number 0 |
| Changed tracking key | Boolean next value |
| `profileKey` | Present only when master actually contained a profile string |

It does not invent `profileKey=default` when the original profile value was nil.
The observed receiver processes these through its existing preference commit
and KVO path. The two logical tracking settings, their journal entries, and the
associated local bookkeeping are the direct backend's write scope.

Custom profiles, portable linkage, unsupported binaries, and eligible
unavailable pre-write reads select `SCRCUserDefaults`. Once a commit begins,
errors do **not** trigger a fallback or a second automatic cycle. Direct sync
and readback failures are errors. The public app has no command-line override
for container, domain, notification name, or backend; test constructors inject
isolated locations only in tests.

## Speech, permissions and activation

Speech uses the VoiceOver scripting dictionary's `output` event (`VOAS`/`outp`),
through `NSAppleScript`. The script is compiled during the build. Text is an
Apple Event parameter, never shell input or dynamically interpolated script.
There are no runtime focus-boundary queries or GUI-scripting commands.

`AEDeterminePermissionToAutomateTarget` is a public Carbon API. The app checks
whether VoiceOver is running first. Normal calls pass `askUserIfNeeded=false`;
only the explicit permission-setup argument can request consent. Hardened
Runtime uses `com.apple.security.automation.apple-events` and an English
`NSAppleEventsUsageDescription`. There is no app-sandbox, Apple-reserved group
entitlement, TCC bypass, or permission-database modification.

macOS 26.6 protected the inspected VoiceOver preference directory behind Full
Disk Access for the app. Only a failed initial tracking read combined with
`EPERM`/`EACCES` from opening the required directory presents guidance. Those
POSIX errors can also represent other restrictions; this is a resource-access
check, not a universal API for querying Full Disk Access status.

The System Settings deep link is a system convention, not a stable public API.
The alert retains manual navigation instructions and falls back to opening the
Settings application if the deep link cannot be opened. A user click is required
before either action.

## Upgrade and failure risks

1. Apple may remove classes, methods, ivars, symbols, keys, or their meanings.
   Type and identity checks cannot prove unchanged semantics.
2. The C path is intentionally tied to inspected binary UUIDs. A system update
   may fall back to the slower framework implementation; do not widen the
   allowlist without inspecting synchronization and notification behavior again.
3. The file lock covers this app's invocations only. VoiceOver, Utility, profile
   changes, and portable-device changes can still race the read/write sequence.
4. Some private calls can raise Objective-C exceptions, which Swift error
   handling does not catch. There is no overall private-call watchdog.
5. A synchronization or readback error may occur after some state changed. The
   implementation makes no atomicity or automatic-rollback claim.
6. Correct notification payloads, saved values, codesigning, and notarization do
   not prove the running screen reader moved either cursor.
7. This companion has no macOS 27 runtime acceptance. The original utility's
   macOS 27 compatibility statement covers a different implementation and task.
