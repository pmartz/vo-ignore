import Foundation

// One-time setup remains separate from normal launches and never changes tracking.
if CommandLine.arguments.count > 1 {
    guard Array(CommandLine.arguments.dropFirst()) == ["--request-announcement-access"] else { exit(2) }
    exit(VoiceOverAnnouncement.hasPermission(askUserIfNeeded: true) ? 0 : 1)
}
// Global ownership is intentional: NSApplication.delegate is weak.
let controller = LaunchController()
controller.run()
