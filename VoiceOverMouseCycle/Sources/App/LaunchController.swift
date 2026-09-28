import AppKit
import OSLog

/// Frozen 0.1.8 behavior: one cycle per delivered request, then latest feedback.
@MainActor
final class LaunchController: NSObject, NSApplicationDelegate {
    static let idleSeconds: TimeInterval = 10
    private var requests = LaunchRequests()
    private var scheduled = false
    private var idleTimer: Timer?
    private var language: FeedbackLanguage?
    private var scriptPrepared = false
    private var announcedRevision = 0
    private var latest: TrackingState?

    func run() -> Never {
        // Handle the first request before AppKit; didFinishLaunching must not count it twice.
        requests.receive()
        step()
        let app = NSApplication.shared
        guard prohibitActivation() else { exit(1) }
        app.delegate = self
        withExtendedLifetime(self) { app.run() }
        exit(0)
    }

    // LSBackgroundOnly is required too; LSUIElement alone activated on reopen.
    private func prohibitActivation() -> Bool {
        let app = NSApplication.shared
        return app.activationPolicy() == .prohibited || app.setActivationPolicy(.prohibited)
    }

    func applicationWillFinishLaunching(_ notification: Notification) { _ = prohibitActivation() }
    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = prohibitActivation()
        if requests.received == 0 { receive() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        receive()
        return false
    }

    private func receive() {
        idleTimer?.invalidate()
        idleTimer = nil
        language = nil // Refresh the system language for each request.
        requests.receive()
        schedule()
    }

    private func schedule() {
        guard !scheduled else { return }
        scheduled = true
        // Keep the existing yield between stages so AppKit can deliver reopen events.
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(1)) { [self] in
            scheduled = false
            step()
        }
    }

    private func step() {
        if requests.pending > 0 {
            do { latest = try advance() }
            catch {
                Logger(subsystem: "org.example.VoiceOverMouseCycle", category: "cycle").error("\(String(describing: error), privacy: .public)")
                exit(1)
            }
            requests.complete()
            schedule()
            return
        }
        if language == nil {
            language = FeedbackLanguage.resolve()
            schedule(); return
        }
        if !scriptPrepared {
            if !VoiceOverAnnouncement.prepare() {
                scheduleFinish(); return
            }
            scriptPrepared = true
            schedule(); return
        }
        let revision = requests.completed
        if announcedRevision != revision, requests.mayAnnounce(revision), let mode = latest?.mode, let language {
            VoiceOverAnnouncement.speak(mode.feedback(in: language))
            announcedRevision = revision
        }
        scheduleFinish()
    }

    private func advance() throws -> TrackingState {
        let lock = try InvocationLock() // Covers configuration only, never speech.
        return try withExtendedLifetime(lock) {
            let preferences = try AdaptivePreferences()
            let state: TrackingState
            do { state = try preferences.read() }
            catch {
                if error is TrackingValueUnavailable, ConfigurationAccess.isDenied {
                    PermissionGuide.present()
                }
                throw error
            }
            return try cycle(preferences, initialState: state)
        }
    }

    private func scheduleFinish() {
        idleTimer?.invalidate()
        let timer = Timer(timeInterval: Self.idleSeconds, target: self,
                          selector: #selector(idleExpired(_:)), userInfo: nil, repeats: false)
        idleTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    @objc private func idleExpired(_ timer: Timer) {
        guard timer === idleTimer, requests.pending == 0, !scheduled else { return }
        idleTimer = nil
        exit(0)
    }
}
