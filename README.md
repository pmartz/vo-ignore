# vo-ignore

vo-ignore is a small macOS command-line utility that sets VoiceOver's Mouse Pointer option to "Ignores VoiceOver Cursor," regardless of its current setting.

This is useful because the Mouse Pointer setting can sometimes spontaneously change to "Follows VoiceOver Cursor." When that happens, VoiceOver menu navigation can behave unexpectedly, including VO-M entering the Apple menu directly and first-letter navigation within menus no longer working normally.

## How it works

vo-ignore uses Apple's private ScreenReaderCore framework and SCRCUserDefaults to set these two VoiceOver preferences to false:

SCRConfigurationCursorTrackingMToVO
SCRConfigurationCursorTrackingVOToM

It then synchronizes the preferences. Unlike directly editing the VoiceOver preference plist, this changes both the stored preference and VoiceOver's live state immediately.

## Building

With Apple's Xcode Command Line Tools installed, build from the project directory:

```sh
make
```

The default target builds `vo-ignore` using the same command as a manual build:

```sh
swiftc -O -o vo-ignore vo-ignore.swift
```

Run the locally built executable with `./vo-ignore`.

## Installing

```sh
make install
```

This builds the executable if needed and installs:

- `vo-ignore` at `/usr/local/bin/vo-ignore`, the conventional location for locally built command-line executables on macOS (see `man hier`).
- `vo-ignore.scpt` at `~/Library/Scripts/vo-ignore.scpt`, Apple's [per-user scripts directory](https://developer.apple.com/library/archive/documentation/LanguagesUtilities/Conceptual/MacAutomationScriptingGuide/UsetheSystem-WideScriptMenu.html).

Run `make install` as your normal user, without prefixing it with `sudo`. The target uses `sudo` only to create `/usr/local/bin` and install the executable, and may prompt for your administrator password. The script is installed in your own Library folder. Both destination directories are created if needed.

Run the installed executable with `/usr/local/bin/vo-ignore`, or `vo-ignore` if `/usr/local/bin` is on your `PATH`.

## Cleaning and uninstalling

Remove the executable built in the project directory with:

```sh
make clean
```

This leaves the installed files in place. To remove both installed files:

```sh
make uninstall
```

Run this as your normal user as well; the target uses `sudo` only to remove `/usr/local/bin/vo-ignore`. Uninstalling leaves the local build and destination directories in place.

## AppleScript

vo-ignore.scpt is a small AppleScript wrapper that runs the command-line utility. It can be used with VoiceOver's custom commands or other macOS automation mechanisms.

The supplied script invokes `/usr/local/bin/vo-ignore` by its absolute path, so it does not depend on the repository location or the AppleScript environment's `PATH`. Run `make install` before using the wrapper, then select `~/Library/Scripts/vo-ignore.scpt` in your automation setup.

## Compatibility

This utility was developed and tested on macOS 27 Golden Gate.

It relies on a private Apple framework and undocumented APIs. Apple may change or remove these APIs in future macOS releases, so compatibility with future versions is not guaranteed.

## Why this exists

VoiceOver provides a keyboard command, VO-Shift-F3, related to mouse pointer tracking. On macOS 27 Golden Gate, repeated use can cycle the Mouse Pointer setting, but it does not provide a deterministic one-shot way to set the option specifically to "Ignores VoiceOver Cursor," nor does it verbally announce the option's new value.

vo-ignore sets the option to Ignores and confirms with a verbal announcement.

## Development Disclosure

This utility was developed by Paul Martz with assistance from ChatGPT, including code development and debugging.

## License

This project is released under the MIT License.

Copyright (c) 2026 Paul Martz

See the LICENSE file for the full license text.
