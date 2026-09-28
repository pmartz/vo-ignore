#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
flavor=${1:-unsigned}
case "$flavor" in
  unsigned)
    configuration=Release
    signing=(CODE_SIGNING_ALLOWED=NO)
    ;;
  development)
    : "${DEVELOPMENT_TEAM:?Set your own Apple Developer team ID}"
    configuration=Debug
    signing=("DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM" CODE_SIGN_STYLE=Automatic 'CODE_SIGN_IDENTITY=Apple Development')
    ;;
  release)
    : "${DEVELOPMENT_TEAM:?Set your own Apple Developer team ID}"
    : "${DEVELOPER_ID_APPLICATION:?Set the full name of your own Developer ID Application identity}"
    configuration=Release
    signing=("DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM" CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$DEVELOPER_ID_APPLICATION" 'OTHER_CODE_SIGN_FLAGS=--timestamp')
    ;;
  *) print -u2 'Usage: scripts/build.zsh [unsigned|development|release]'; exit 2 ;;
esac
# A unique temporary directory avoids mixing identities with an installed build.
# Keep it for review; a new invocation never overwrites a previous signed app.
derived=$(mktemp -d /private/tmp/vo-ignore-build.XXXXXX)
mkdir -p build
xcodebuild -project VoiceOverMouseCycle.xcodeproj -scheme VoiceOverMouseCycle \
  -configuration "$configuration" -derivedDataPath "$derived" \
  ENABLE_HARDENED_RUNTIME=YES "${signing[@]}" build > "build/${flavor}-build.log" 2>&1
app_path="$derived/Build/Products/$configuration/VoiceOverMouseCycle.app"
if [[ "$flavor" != unsigned ]]; then
  codesign --verify --deep --strict --verbose=2 "$app_path"
  codesign -dvvv "$app_path"
fi
ditto -c -k --norsrc --noextattr --keepParent "$app_path" "build/VoiceOverMouseCycle-${flavor}.zip"
print "Built: ${app_path}"
print "ZIP: ${PWD}/build/VoiceOverMouseCycle-${flavor}.zip"
print 'Unsigned builds are compile checks, not trusted distribution builds.'
print 'This script does not install, launch, upload, or notarize anything.'
