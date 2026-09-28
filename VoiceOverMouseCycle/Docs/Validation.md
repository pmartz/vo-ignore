# Validation and remaining acceptance work

## Environment and evidence boundaries

Implementation investigation and automated validation took place on Apple
silicon, macOS 26.6 (25G72). The application targets macOS 26.0 or later and was
built with a Swift 6 toolchain. Building with a macOS 27 SDK is not equivalent
to running the app on macOS 27.

The submitted source is a sanitized copy of the implementation: signing defaults
are external parameters, example bundle identifiers replace personal ones, and
developer-facing errors and documentation are English. The two translation
resources, C backend, mode order, notification mechanism, announcement handler,
and 10-second idle behavior are retained. Personal logs and signed artifacts
are deliberately not part of this PR.

## Automated coverage

The Swift package has 26 XCTest cases covering:

- Six transitions from every normal starting mode, specified mode order, and
  normalization of the invalid double-true pair.
- Read/setup/synchronization failure, changed starting state, readback mismatch,
  and absence of writes when preflight fails.
- The actual C backend against isolated temporary containers: six cycles,
  journal handling, preservation of unrelated settings, and notification key
  order/payload with both missing and explicit default-profile identifiers.
- Missing/invalid values, custom-profile fallback, dangling portable links,
  profile changes before commit, and refusal to fall back after failed commit.
- Request accounting and superseding unsent speech without losing state changes.
- 59 translation entries, language aliases/regions, English fallback, and
  permission-guide language coverage.

Run from the companion directory:

```sh
swift test --scratch-path "$(mktemp -d /private/tmp/vo-ignore-tests.XXXXXX)"
```

On unknown framework UUIDs the C integration tests explicitly skip. A passing
suite with skips must not be described as verification of that OS's private C
ABI. No test uses the real VoiceOver domain or asks for privacy consent.

Compile the app separately because SwiftPM tests cover the core, not all AppKit
entry points:

```sh
scripts/build.zsh unsigned
```

Both commands passed on the sanitized contribution source on macOS 26.6:
26 XCTest cases, zero failures and zero skips; the complete unsigned Release
App build also succeeded. The only build warning was skipped App Intents
metadata extraction because the app does not use AppIntents. Machine-specific
logs and build products are excluded from the contribution.

## Prior runtime checks, with limits

Before sanitization, a separate development App compiled the production
controller/entry-point sources while substituting configuration and speech
dependencies. Twelve native Launch Services opens completed twelve simulated
cycles; a thirteenth open during the idle interval completed one more. The
process exited approximately 10 seconds after the final work. No window, app
activation, foreground change, or leftover test process was observed, and the
running VoiceOver instance was left alone. This is lifecycle validation, not
physical mouse or speech validation. Test hooks are not included in this app.

Earlier framework-backed builds received operator confirmation of the three
real cursor behaviors and short VoiceOver output, and a six-launch sequence
returned to its initial mode. Those observations predate the final C fast path
and do not establish complete physical acceptance of this exact submitted build.
The final implementation received a positive responsiveness report, but that is
not a measured 5/10/20 ms latency claim.

No runtime acceptance is claimed for macOS 27, portable preferences, arbitrary
custom profiles, all localization pronunciations, or every Commander binding.

## Physical acceptance checklist for each target macOS version

Use a consistently signed installed build with its own permissions. Keep
VoiceOver running. Use a normal accessible application with controls in visibly
different positions; VoiceOver Utility need not remain open for the test.

1. Establish **Ignore VoiceOver cursor**. Do not touch the mouse or trackpad.
   Move the VoiceOver cursor among different controls. Verify the pointer stays
   in place.
2. Open the app once. In **Mouse follows VoiceOver cursor**, leave the physical
   pointing device untouched and navigate VoiceOver among distant controls.
   Verify the actual mouse pointer follows.
3. Open once more. In **VoiceOver cursor follows mouse**, move only the mouse
   across accessible controls, pausing briefly without clicking. Verify that
   VoiceOver's cursor and narration follow those controls. Where useful, compare
   VO-F3 (VoiceOver cursor) and VO-F5 (mouse item), using Fn if needed. Do not use
   VO-Shift-F5; that manually moves the cursor and invalidates the check.
4. Open again to return to Ignore. Continue until at least six consecutive
   launches have completed two stable cycles, checking each resulting mode.
5. Confirm the short announcement matches each state and does not move keyboard
   focus or the VoiceOver cursor merely to deliver speech.
6. Repeat with the user's actual Commander command, including rapid presses.
   Check the state after presses stop and the absence of stale unsent feedback.
   Count delivered actions carefully; OS-level event coalescing is outside the
   app's request queue.
7. Verify that the frontmost app remains frontmost, no normal window or Dock icon
   appears, VoiceOver stays running, and no Utility window is opened.
8. Wait at least 10 seconds after work completes and check that the process exits.
   Open again before expiry and verify the exit interval resets.
9. Separately test permission guidance on a deliberately ungranted test identity:
   readable text/buttons, Return and Escape, cancellation without a write, and
   opening Settings only after choosing that button. Do not change a production
   app's consent just to run an automated probe.
10. Repeat on macOS 27 before labeling that version supported by actual testing.

Record the OS version, application version, backend assumptions, permission
state, and actual user-visible behavior. Configuration readback and observed
notifications are supporting evidence, not replacements for these checks.

## Distribution checks

No prebuilt binary or local signing identity is supplied in this PR. For a
maintainer-produced release, verify Developer ID, Hardened Runtime, a secure
signing timestamp, the intended bundle identifier, and only the necessary
Apple Events entitlement. After notarization is accepted, staple the App,
package it, and verify the extracted copy again. Assess outside any command
execution sandbox so trust evaluation can access the system services it needs.

A successful `stapler validate` verifies an attached ticket using the ticketing
service. Document any actual disconnected-Mac test separately rather than
presenting that online validation as an offline test.
