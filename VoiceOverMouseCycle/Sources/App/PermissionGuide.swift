import AppKit

@MainActor
enum PermissionGuide {
    /// Only called for a denied initial configuration read during a cycle.
    /// Native NSAlert supplies accessible text, buttons and modal keyboard focus.
    static func present() {
        let selection = PermissionGuideLanguage.resolve()
        let copy = selection.text
        let application = NSApplication.shared
        // With lazy NSApplication creation, LSUIElement may already have set
        // accessory policy. No policy transition is necessary in that case.
        guard application.activationPolicy() == .accessory || application.setActivationPolicy(.accessory) else {
            return
        }
        if !application.isRunning { application.finishLaunching() }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = copy.title
        alert.informativeText = copy.message
        alert.addButton(withTitle: copy.settings).keyEquivalent = "\r"
        alert.addButton(withTitle: copy.cancel).keyEquivalent = "\u{1b}"
        alert.window.makeKeyAndOrderFront(nil)
        application.activate()
        let response = alert.runModal()
        alert.window.orderOut(nil)
        guard response == .alertFirstButtonReturn else {
            return
        }

        // This deep link is a system convention, not a stable public API contract.
        // Opening Settings never changes consent. Keep manual navigation in the text.
        let destination = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        if NSWorkspace.shared.open(destination) {
            return
        }
        if let settings = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences"),
           NSWorkspace.shared.open(settings) {
            return
        }
    }
}
