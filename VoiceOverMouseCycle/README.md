# VoiceOverMouseCycle

An optional, windowless macOS application that cycles VoiceOver's three mouse
pointer tracking modes. Launch it directly from VoiceOver Keyboard Commander or
another custom command that opens an application.

This is a companion to the root `vo-ignore` command, which remains unchanged.
Use `vo-ignore` when you always want to turn tracking off. Use this app when you
want to cycle between all three modes and hear the resulting mode.

Start with [the change and design notes](Docs/Changes.md) for a comparison with
upstream. The [private API notes](Docs/PrivateAPI.md) describe the live-update
mechanism and its compatibility risks. [Validation](Docs/Validation.md) separates
automated checks from physical cursor and speech acceptance.

## Requirements

- Apple silicon Mac running macOS 26 or later. Development and local runtime
  investigation used macOS 26.6. **This app has not been tested on macOS 27.**
- VoiceOver should already be running when using the app.
- Full Disk Access for the installed app where macOS protects VoiceOver's
  preferences container.
- Optional spoken feedback: permission for the app to send Apple Events to
  VoiceOver, and VoiceOver's own setting that allows AppleScript control.
- To build: full Xcode with a Swift 6 toolchain and the macOS SDK. The generated
  Xcode project is included. XcodeGen is only needed after editing `project.yml`.

There are no third-party runtime dependencies. Apple private frameworks are
used, so this is not a Mac App Store submission and future OS updates may break
compatibility.

## Build from source

All commands in this guide run from the `VoiceOverMouseCycle` directory.

For a compile-only check without a signing identity:

```sh
scripts/build.zsh unsigned
```

This does not install or launch the app. Do not distribute or use this unsigned
build as a substitute for a consistently signed app with established permissions.

For development, choose your own bundle identifiers in `project.yml` and then
regenerate the project with `xcodegen generate`. The checked-in identifiers use
`org.example` as placeholders. Debug uses a separate `.Development` identifier
so test builds do not replace a release app's privacy identity.

```sh
export DEVELOPMENT_TEAM=YOURTEAMID
scripts/build.zsh development
```

Alternatively, open `VoiceOverMouseCycle.xcodeproj`, choose your own development
team in Signing & Capabilities, and build. If you regenerate the project later,
make the corresponding changes in `project.yml` too.

For direct distribution, use your own Developer ID Application identity:

```sh
export DEVELOPMENT_TEAM=YOURTEAMID
export DEVELOPER_ID_APPLICATION='Developer ID Application: Your Name (YOURTEAMID)'
scripts/build.zsh release
```

The release script enables Hardened Runtime and requests a secure signing
timestamp. It never installs, launches, uploads, or notarizes the app. Each build
uses a new temporary directory and prints the resulting App path; its ZIP is
written under `build/`. Building outside cloud-synced source directories avoids
unexpected resource attributes interfering with signatures.

Signing, notarization, and packaging instructions are below. This source
contribution includes no certificate, developer-team assignment, credentials,
prebuilt app, or notarization ticket.

## Install and grant access

1. Copy the signed `VoiceOverMouseCycle.app` to the system Applications folder:
   `/Applications/VoiceOverMouseCycle.app`.
2. Keep VoiceOver running and open the app once. If the initial tracking read
   fails and access to its preferences directory is denied, an accessible native
   alert offers **Open System Settings** and **Cancel**.
3. In System Settings > Privacy & Security > Full Disk Access, enable the app.
   If it is missing, use the plus button and select it from Applications.
4. Run the app again after granting access. The permission-guidance invocation
   itself does not change tracking or wait in the background for approval.

The permission alert follows the system preferred languages. Return chooses
Open System Settings; Escape cancels. The alert is the only normal-launch case
that intentionally takes keyboard focus. The app never changes a permission
switch or edits the TCC database itself.

Full Disk Access is broader than the two tracking settings this app uses. The
implementation accesses VoiceOver's preference machinery; it does not scan the
user's documents. Signing and notarization do not grant Full Disk Access or
Apple Events consent. An inaccessible value is never assumed to mean `false`.

Use the same installed path and signing identity when updating. Rebuilding with
a different bundle identifier or signing requirement creates a different app
identity and can require fresh permissions. Do not reuse a release identifier
for an unrelated development probe.

## Enable optional spoken feedback

With VoiceOver running, double-click `Distribution/Enable Announcements.command`
(or the same file next to the App in a packaged release). It runs this command:

```sh
open -n /Applications/VoiceOverMouseCycle.app --args --request-announcement-access
```

Approve the macOS automation request if you want the app to announce modes. This
one-time setup only requests permission; it does not read or change tracking and
does not speak a mode. If VoiceOver is not running, the app does not start it.
VoiceOver must also allow AppleScript control. The app does not open VoiceOver
Utility or change that setting for you.

During normal use, permission checks do not display automation prompts. Missing
speech permission skips the announcement without undoing a successful tracking
change. Speech comes from VoiceOver's own AppleScript `output` command, not a
separate speech synthesizer. No window is opened to make the announcement.

## Assign a VoiceOver command

In VoiceOver's Keyboard Commander or custom commands, choose **Open Application**
and select `/Applications/VoiceOverMouseCycle.app`. Use the labels appropriate
to your macOS version. The utility itself does not register a global shortcut.

For everyday use, open the App directly. Do not invoke the permission helper on
every key press, and do not use `open -n` for repeated mode changes. Plain `open`
lets Launch Services deliver reopen requests to the current instance:

```sh
open /Applications/VoiceOverMouseCycle.app
```

## Mode order and rapid presses

Each delivered launch/reopen request advances one step:

| Current mode | Next mode | English feedback for the next mode |
|---|---|---|
| Ignore VoiceOver cursor | Mouse follows VoiceOver cursor | Mouse follows VoiceOver |
| Mouse follows VoiceOver cursor | VoiceOver cursor follows mouse | VoiceOver follows mouse |
| VoiceOver cursor follows mouse | Ignore VoiceOver cursor | No tracking |
| Invalid combination: both flags true | Ignore VoiceOver cursor | No tracking |

The first request changes configuration before initializing `NSApplication`.
Further opens reuse the same process. Configuration requests are handled in
order; older feedback that has not yet been sent is superseded by the latest
completed state. Speech already handed to VoiceOver is controlled by VoiceOver.
The program does not claim that every physical key press is delivered by
Commander or Launch Services.

After work finishes, the process exits following **10 idle seconds**. A new
request cancels that timer and starts a new idle period after its work completes.
This is a short reuse interval, not a login item or background service. There is
no normal window, Dock icon, global key hook, VoiceOver restart, or automatic
opening of VoiceOver Utility. The app uses `LSBackgroundOnly` and a prohibited
activation policy during ordinary operation.

Announcements and the permission guide have 59 bundled language/region variants.
The first supported entry in the system preferred-language list wins; otherwise
English is used. This deliberately follows **system language**, not VoiceOver's
selected voice or rotor. Translations are editable JSON resources; broad locale
coverage does not imply every translation has received native-speaker review.

## Troubleshooting

- **Nothing changes:** check Full Disk Access for the exact installed App. Other
  private API or configuration failures also stop the operation; only confirmed
  directory-access denial produces the access guide.
- **Tracking changes but nothing is spoken:** run the one-time authorization
  helper, check System Settings > Privacy & Security > Automation, and check
  VoiceOver's AppleScript-control setting.
- **Fast presses sound behind:** unsent feedback is superseded, but VoiceOver
  owns speech already submitted. First test three slow launches to establish
  the actual cursor behavior, then test rapid presses.
- **A new macOS release stops working:** unknown framework binaries use the
  checked `SCRCUserDefaults` backend. Missing or changed private contracts stop
  the operation. Do not bypass checks just because symbols still exist.
- **Direct shell invocation behaves differently:** macOS can attribute terminal
  privacy requests differently from Launch Services. Test the installed App via
  the same Open Application path used by Commander.

There are no diagnostic/status/report command-line modes in this build. The
only supported argument is `--request-announcement-access`; other arguments exit
with code 2 without cycling. A configuration error exits with code 1 and is
logged. Successful work exits with code 0 after the idle period. An `open`
command's return code only describes the launch request, not the app's result.

The operation is not an atomic transaction with VoiceOver or its utility. A
failure after a write can leave a partial change. The app does not automatically
cycle again or restart VoiceOver to hide such a failure.

## Notarize and package a release

Use a consistently signed Release build and your own previously configured
Keychain notary profile. Upload only when you intend to submit that build:

```sh
xcrun notarytool submit build/VoiceOverMouseCycle-release.zip \
  --keychain-profile YOUR_NOTARY_PROFILE --wait
```

Proceed only after the service reports `Accepted`. Set `app_path` to the signed
App path printed by the release build, then attach and validate its ticket:

```sh
xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"
codesign --verify --deep --strict --verbose=4 "$app_path"
spctl --assess --type execute --verbose=4 "$app_path"
scripts/package.zsh "$app_path"
```

The packaging script requires valid signing, a stapled ticket, and an accepted
Gatekeeper assessment. It includes the App, an English quick-start guide, the
optional speech-authorization helper, and actual signing status. Re-extract the
final ZIP and repeat the signature and ticket checks on that copy.

The secure timestamp belongs to the code signature. The stapled notarization
ticket enables Gatekeeper to verify notarization offline. Merely submitting a
ZIP is not the same as attaching the ticket: staple the App **before** making
the final ZIP. `stapler validate` itself contacts Apple's ticketing service, so
passing that command is not a claim that a disconnected-Mac test was performed.

## Tests and license

```sh
swift test --scratch-path "$(mktemp -d /private/tmp/vo-ignore-tests.XXXXXX)"
```

Tests use in-memory preferences or isolated temporary containers and randomized
test notification names. They do not change real VoiceOver tracking or request
privacy permissions. C-backend integration tests skip on unknown framework
binaries; inspect skipped tests instead of counting them as runtime coverage.
See [Validation](Docs/Validation.md) for the physical acceptance checklist.

MIT, retaining Paul Martz's original copyright and license. This companion was
developed with assistance from OpenAI Codex. It is offered as an optional addition
rather than a replacement for the original deterministic `vo-ignore` utility.
