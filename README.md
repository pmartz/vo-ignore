# vo-ignore

vo-ignore is a small macOS command-line utility that sets VoiceOver's Mouse Pointer option to "Ignores VoiceOver Cursor," regardless of its current setting.

This is useful because the Mouse Pointer setting can sometimes spontaneously change to "Follows VoiceOver Cursor." When that happens, VoiceOver menu navigation can behave unexpectedly, including VO-M entering the Apple menu directly and first-letter navigation within menus no longer working normally.

## How it works

vo-ignore uses Apple's private ScreenReaderCore framework and SCRCUserDefaults to set these two VoiceOver preferences to false:

SCRConfigurationCursorTrackingMToVO
SCRConfigurationCursorTrackingVOToM

It then synchronizes the preferences. Unlike directly editing the VoiceOver preference plist, this changes both the stored preference and VoiceOver's live state immediately.

## Building

Compile the Swift source with:

swiftc -O -o vo-ignore vo-ignore.swift

The resulting vo-ignore executable can be run directly from Terminal.

## AppleScript

vo-ignore.scpt is a small AppleScript wrapper that runs the command-line utility. It can be used with VoiceOver's custom commands or other macOS automation mechanisms.

The supplied script expects the executable to be located at:

$HOME/projects/vo-ignore/vo-ignore

Edit the script if you install the executable somewhere else.

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
