#!/bin/zsh
set -eu
app_path=/Applications/VoiceOverMouseCycle.app
if [[ ! -d "$app_path" ]]; then
  print 'Move VoiceOverMouseCycle.app into /Applications first.'
  exit 1
fi
print 'Requesting VoiceOver announcement permission; tracking is unchanged.'
# Launch Services attributes the request to the signed app, not this shell.
/usr/bin/open -n "$app_path" --args --request-announcement-access
