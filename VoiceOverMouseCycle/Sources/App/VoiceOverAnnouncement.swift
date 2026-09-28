import AppKit
import Carbon
import Synchronization

@MainActor
enum VoiceOverAnnouncement {
    nonisolated private static let bundleID = "com.apple.VoiceOver"
    // VoiceOver.sdef: output = 'VOAS' / 'outp'. No System Events or GUI scripting.
    nonisolated private static let eventClass: AEEventClass = 0x564F4153
    nonisolated private static let eventID: AEEventID = 0x6F757470
    private static var preparedScript: NSAppleScript?

    /// Load the signed build artifact once per short-lived process. Never
    /// recompile source or launch an external script at runtime.
    static func prepare() -> Bool {
        if preparedScript != nil { return true }
        guard let url = Bundle.main.url(forResource: "AnnounceMode", withExtension: "scpt") else {
            return false
        }
        var error: NSDictionary?
        preparedScript = NSAppleScript(contentsOf: url, error: &error)
        return preparedScript != nil
    }

    static func hasPermission(askUserIfNeeded: Bool = false) -> Bool {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else {
            return false
        }
        let result = Mutex<OSStatus?>(nil)
        let completed = DispatchSemaphore(value: 0)
        // The synchronous Carbon API must not run on the main thread. This
        // standalone process uses a dedicated GCD worker, not a Swift task.
        // Mutex protects the result even if the bounded wait expires first.
        DispatchQueue.global(qos: .userInitiated).async {
            let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
            let status = AEDeterminePermissionToAutomateTarget(
                target.aeDesc, eventClass, eventID, askUserIfNeeded)
            result.withLock { $0 = status }
            completed.signal()
        }
        let limit: Double = askUserIfNeeded ? 60 : 1
        guard completed.wait(timeout: .now() + limit) == .success,
              let status = result.withLock({ $0 }) else {
            return false
        }
        return status == noErr
    }

    static func speak(_ text: String) {
        guard hasPermission(), prepare() else { return }
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kASAppleScriptSuite),
            eventID: AEEventID(kASSubroutineEvent), targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(NSAppleEventDescriptor(string: "announce"), forKeyword: AEKeyword(keyASSubroutineName))
        let parameters = NSAppleEventDescriptor.list()
        parameters.insert(NSAppleEventDescriptor(string: text), at: 1)
        event.setParam(parameters, forKeyword: AEKeyword(keyDirectObject))
        var error: NSDictionary?
        _ = preparedScript?.executeAppleEvent(event, error: &error)
    }
}
