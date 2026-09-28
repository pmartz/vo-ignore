# Changes relative to vo-ignore

## Scope of the contribution

The root `vo-ignore.swift`, `vo-ignore.scpt`, `Makefile`, installation targets, and
MIT license are unchanged. The root README only gains a link to this optional
companion. All new code, tests, resources, build settings, and documentation live
under `VoiceOverMouseCycle/`.

The existing utility solves the useful and narrower problem of always forcing
Ignore. The new app addresses users who want one Commander command to cycle all
three modes, including rapid repeated invocations, without bringing another app
to the foreground. Those are different operations; the companion does not change
the meaning of `vo-ignore`.

## User-visible differences

| Area | Root vo-ignore at c7641a1 | Optional VoiceOverMouseCycle app |
|---|---|---|
| Tracking operation | Always writes both flags false | Reads both flags and advances through three modes |
| Entry point | Executable, optionally through an AppleScript wrapper | App opened directly by Commander/Launch Services |
| Feedback engine | AVSpeechSynthesizer with assistive-technology speech settings | VoiceOver's own AppleScript output command |
| Feedback language | Fixed English confirmation | 59 local variants, selected by system preferred languages |
| Lifecycle | Waits for synthesizer completion, then exits | Reuses its process for repeated opens; exits after 10 idle seconds |
| AppleScript role | Starts the executable through a shell wrapper | Precompiled in-app handler submits a text argument to VoiceOver |
| Access setup | Existing command-line installation model | Native Full Disk Access guidance only on confirmed directory denial |
| Speech consent | No AppleScript output consent in the utility | Separate, explicit Apple Events authorization helper |
| Build | swiftc through make | Swift + small C backend; Xcode project and independent SwiftPM tests |

## Configuration and live-update changes

The implementation began with the same private framework and two keys as the
original. It does not automate VoiceOver Utility or use `defaults write`.

A macOS 26.6 investigation found that retrieving `sharedUserDefaults` alone left
the private notification-family identity unset. In that state the setter's
notification branch could be skipped even though values could be saved and read
back. The framework backend therefore calls the checked `setFamilyMember:4`,
verifies the resulting string is `bcst`, and rereads the starting state before
writing. It uses `synchronizeWhileIWait` so framework synchronization completes
before the short-lived process exits. This is a finding about the investigated
26.6 implementation, not a claim that the upstream author's macOS 27 test was
incorrect.

A smaller C path avoids shared-object initialization only for the exact inspected
ScreenReaderCore/CoreFoundation binaries and the default, non-portable profile.
It reproduces the observed preference, journal, synchronization, and distributed
notification sequence. Custom profiles, portable markers, unsupported binaries,
and eligible pre-write read failures select the checked framework path instead.
There is no OS-version string switch and no fallback after a commit begins.

See [PrivateAPI.md](PrivateAPI.md) for method signatures, UUIDs, notification
payloads, limits, and upgrade risks. These checks cannot prove future private
implementations remain semantically compatible.

## State and error handling

- Normal state order is Ignore -> Mouse follows VoiceOver -> VoiceOver follows
  mouse -> Ignore. Both flags true is treated as an abnormal state and normalized
  to Ignore, not exposed as a fourth mode.
- Missing tracking values never become false implicitly. Booleans and numeric
  0/1 are accepted; incompatible values stop the operation.
- The opposite tracking direction is cleared before enabling the next direction,
  avoiding an intermediate double-true value when starting from a normal state.
- Starting state is checked again after setup, and completed writes are synced
  and read back. These checks reduce stale writes but are not a transaction with
  VoiceOver, its utility, or another preference writer.
- A nonblocking file lock serializes overlapping configuration work by this app.
  It is released before speech. It cannot lock the system's own writers.
- Configuration errors do not trigger another automatic cycle. Speech failure
  does not roll back a completed configuration change.

## Repeated launches and focus

`LaunchController` handles the first configuration operation before creating
`NSApplication`. Reopen events are counted as new requests, and configuration
work is serialized on the main thread. Short yields between stages let AppKit
deliver additional reopen events before the next feedback submission. The app
retains only the latest unsent feedback, while still advancing once for every
request it actually received.

`LSBackgroundOnly` plus `.prohibited` activation is intentional: an earlier
`LSUIElement`-only arrangement could activate during reopen. There are no windows,
menu-bar items, keyboard event taps, login items, launch agents, or global
shortcuts in ordinary use. The 10-second timer is invalidated when a request
arrives and restarted after work is complete. No promise is made about a fixed
5/10/20 ms end-to-end response time.

The permission alert is an explicit exception to the no-focus rule: only a
failed initial read plus a denied open of the needed directory can present it.
It temporarily uses accessory activation and native NSAlert controls. Only the
user's Open System Settings action opens Settings. Cancelling, opening Settings,
or inability to present the alert ends that unsuccessful invocation.

## Speech and localization

The build compiles `Resources/AnnounceMode.applescript` once. Runtime code loads
that artifact once per process and passes text as an Apple Event descriptor; it
does not interpolate a mode name into script source or invoke an external shell.
The handler checks whether VoiceOver is running and sends only `output`.

Normal permission checks use `AEDeterminePermissionToAutomateTarget` without
asking for consent. An explicit setup argument requests consent separately. The
synchronous Carbon call runs on a GCD worker with a protected result and bounded
wait (one second normally, 60 seconds for requested consent). The output handler
has a two-second Apple Event timeout. These do not bound all private framework
calls, and returning from output does not prove audio was heard.

Localized feedback follows the system language to avoid initializing speech
settings solely to find a language. It intentionally does not follow VoiceOver's
selected voice/rotor. Both language catalogs are editable JSON; English fallback
keeps a missing localization resource from blocking tracking. Chinese strings
remain only as actual localizations and their tests; development explanations and
errors in this contribution are English.

## Source preparation and maintenance

The contribution removes personal developer-team and certificate identifiers,
local account paths, signing-profile names, machine logs, process identifiers,
notarization receipts, and packaged binaries. Build scripts take signing values
from the maintainer's environment and never upload automatically. Placeholder
bundle identifiers must be changed before maintaining a separately signed app.

Runtime diagnostics, performance probes, report output, focus-boundary queries,
and simulated launch entry points were removed before this contribution. Unit
tests remain outside the app target. Normal error logs and private-contract
checks remain because they are part of safe operation. No user preferences or
other local computer data are bundled.

The upstream MIT notice is retained. The framework image UUIDs in the C runtime
gate are identifiers of Apple binary builds, **not device or user identifiers**;
removing them would remove an important compatibility restriction.

Suggested review order:

1. [State transitions](../Sources/Core/TrackingMode.swift) and their tests.
2. [Framework backend](../Sources/Core/PrivatePreferences.swift) and the
   [private API explanation](PrivateAPI.md).
3. [Backend selection](../Sources/Core/AdaptivePreferences.swift) and the
   [guarded C implementation](../Sources/FastPreferencesC/VMCLightweight.c).
4. [Lifecycle](../Sources/App/LaunchController.swift), then speech and permission
   guide behavior in `Sources/App`.
5. [Build, installation and distribution](../README.md), then the
   [validation limits](Validation.md).
