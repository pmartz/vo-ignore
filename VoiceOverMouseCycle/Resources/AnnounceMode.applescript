-- Compiled by the build, never compiled from a mode string at runtime.
-- The target command is VoiceOver's output (VOAS/outp), not GUI scripting.
on announce(modeName)
    with timeout of 2 seconds
        if application id "com.apple.VoiceOver" is running then
            tell application id "com.apple.VoiceOver" to output modeName
            return true
        end if
    end timeout
    return false
end announce
