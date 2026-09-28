import Darwin
import Foundation

/// Check the resource we need. EPERM/EACCES can mean access restrictions other
/// than FDA; never infer denial from a nil tracking value alone.
enum ConfigurationAccess {
    static var isDenied: Bool {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.com.apple.VoiceOver/Library/Preferences/com.apple.VoiceOver4")
        let descriptor = Darwin.open(directory.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        if descriptor >= 0 {
            close(descriptor)
            return false
        }
        let code = errno
        return code == EPERM || code == EACCES
    }
}
