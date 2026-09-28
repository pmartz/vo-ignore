import Foundation
#if canImport(FastPreferencesC)
import FastPreferencesC
#endif

struct FastPathFallback: Error, CustomStringConvertible {
    let description: String
}

/// Selects only before writes. Once commit starts, errors must never trigger a
/// second cycle through a different backend.
final class AdaptivePreferences: TrackingPreferences {
    private var active: any TrackingPreferences
    private let frameworkFactory: () throws -> any TrackingPreferences
    private var writesStaged = false

    convenience init() throws {
        let direct = VMCFastRuntimeSupported() ? DirectPreferences.production() : nil
        try self.init(candidate: direct, frameworkFactory: { try PrivatePreferences() })
    }

    // The injected factory lets tests prove fallback is impossible after writes.
    init(candidate: (any TrackingPreferences)?,
         frameworkFactory: @escaping () throws -> any TrackingPreferences) throws {
        self.frameworkFactory = frameworkFactory
        if let candidate { active = candidate }
        else { active = try frameworkFactory() }
    }
    private func fallback() throws {
        active = try frameworkFactory()
    }
    func read() throws -> TrackingState {
        do { return try active.read() }
        catch let error as FastPathFallback {
            guard !writesStaged else { throw error }
            try fallback()
            return try active.read()
        }
    }
    func prepareToWrite() throws {
        do { try active.prepareToWrite() }
        catch is FastPathFallback {
            try fallback()
            try active.prepareToWrite()
        }
    }
    func set(_ value: Bool, for key: String) {
        writesStaged = true
        active.set(value, for: key)
    }
    func synchronize() throws { try active.synchronize() }
}

final class DirectPreferences: TrackingPreferences {
    private let handle: OpaquePointer
    private var initialState: TrackingState?
    private var staged: [(String, Bool)] = []
    private var commitAttempted = false

    static func production() -> DirectPreferences? {
        let container = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.com.apple.VoiceOver").path
        return DirectPreferences(container: container, domain: "com.apple.VoiceOver4",
                                 notice: "SCRCUserDefaultsChangeDefaultsNotification")
    }
    // Internal injection for isolated tests; no command-line override exists.
    init?(container: String, domain: String, notice: String) {
        guard let handle = VMCFastCreate(container, domain, notice) else { return nil }
        self.handle = handle
    }
    deinit { VMCFastDestroy(handle) }

    private func check(_ result: VMCFastResult, allowFallback: Bool) throws {
        guard result != VMCFastOK else { return }
        if allowFallback && !commitAttempted && (result == VMCFastUnsupported || result == VMCFastUnavailable) {
            throw FastPathFallback(description: result == VMCFastUnsupported ? "profile-or-portable-scope" : "direct-value-unavailable")
        }
        if result == VMCFastUnavailable { throw TrackingValueUnavailable(key: "tracking") }
        throw CycleFailure("The lightweight preferences operation failed (code \(result.rawValue)); success was not reported. A changed configuration or post-write failure never triggers another cycle automatically.")
    }
    func read() throws -> TrackingState {
        var mouse = false, vo = false
        try check(VMCFastRead(handle, &mouse, &vo), allowFallback: true)
        return TrackingState(mouseToVO: mouse, voToMouse: vo)
    }
    func prepareToWrite() throws {
        guard initialState == nil, !commitAttempted else { throw CycleFailure("A tracking instance may commit only once") }
        initialState = try read()
    }
    func set(_ value: Bool, for key: String) {
        // Stage only; the C commit revalidates the profile/markers and expected
        // state before making its first real write.
        staged.append((key, value))
    }
    func synchronize() throws {
        guard let before = initialState, !commitAttempted else { throw CycleFailure("No valid initial tracking state was captured") }
        let expected = before.next.writes
        guard staged.count == 2, zip(staged, expected).allSatisfy({ $0.0 == $1.0 && $0.1 == $1.1 }) else {
            throw CycleFailure("The lightweight backend rejected an unexpected tracking write sequence")
        }
        commitAttempted = true
        try check(VMCFastCommit(handle, before.mouseToVO, before.voToMouse), allowFallback: false)
    }
}
