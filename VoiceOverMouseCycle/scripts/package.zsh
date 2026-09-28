#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
app_path=${1:?Usage: scripts/package.zsh /absolute/path/VoiceOverMouseCycle.app}
[[ "$app_path" == /* && -d "$app_path" ]] || { print -u2 'Provide an existing app with an absolute path.'; exit 2; }
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")
codesign --verify --deep --strict "$app_path"
xcrun stapler validate "$app_path"
stage=$(mktemp -d /private/tmp/vo-ignore-package.XXXXXX)
folder="$stage/VoiceOverMouseCycle-$version"
mkdir -p "$folder" build
ditto --norsrc --noextattr "$app_path" "$folder/VoiceOverMouseCycle.app"
cp Distribution/'Read Me.txt' Distribution/'Enable Announcements.command' "$folder/"
chmod 755 "$folder/Enable Announcements.command"
spctl --assess --type execute --verbose=4 "$app_path" > "$folder/Signing Status.txt" 2>&1
codesign -dvvv "$app_path" >> "$folder/Signing Status.txt" 2>&1
xcrun stapler validate "$folder/VoiceOverMouseCycle.app" >> "$folder/Signing Status.txt" 2>&1
ditto -c -k --norsrc --noextattr --keepParent "$folder" "build/VoiceOverMouseCycle-$version.zip"
print "build/VoiceOverMouseCycle-$version.zip"
