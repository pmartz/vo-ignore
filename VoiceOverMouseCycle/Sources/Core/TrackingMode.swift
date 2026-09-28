import Foundation

enum TrackingMode: String, CaseIterable {
    case ignore
    case mouseFollowsVoiceOver
    case voiceOverFollowsMouse

    var state: TrackingState {
        switch self {
        case .ignore: TrackingState(mouseToVO: false, voToMouse: false)
        case .mouseFollowsVoiceOver: TrackingState(mouseToVO: true, voToMouse: false)
        case .voiceOverFollowsMouse: TrackingState(mouseToVO: false, voToMouse: true)
        }
    }

    // One definition for committing and validating the exact two-key sequence.
    var writes: [(String, Bool)] {
        self == .mouseFollowsVoiceOver
            ? [(TrackingKey.voToMouse, false), (TrackingKey.mouseToVO, true)]
            : [(TrackingKey.mouseToVO, false), (TrackingKey.voToMouse, self == .voiceOverFollowsMouse)]
    }

    func feedback(in language: FeedbackLanguage) -> String {
        switch self {
        case .ignore: language.phrases.ignore
        case .mouseFollowsVoiceOver: language.phrases.mouseFollowsVoiceOver
        case .voiceOverFollowsMouse: language.phrases.voiceOverFollowsMouse
        }
    }
}

struct TrackingState: Equatable {
    let mouseToVO: Bool
    let voToMouse: Bool

    var mode: TrackingMode? {
        TrackingMode.allCases.first { $0.state == self }
    }

    var next: TrackingMode {
        switch mode {
        case .ignore: .mouseFollowsVoiceOver
        case .mouseFollowsVoiceOver: .voiceOverFollowsMouse
        case .voiceOverFollowsMouse, nil: .ignore
        }
    }
}

protocol TrackingPreferences {
    func read() throws -> TrackingState
    func prepareToWrite() throws
    func set(_ value: Bool, for key: String)
    func synchronize() throws
}

enum TrackingKey {
    static let mouseToVO = "SCRConfigurationCursorTrackingMToVO"
    static let voToMouse = "SCRConfigurationCursorTrackingVOToM"
}

struct CycleFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

func cycle(_ preferences: any TrackingPreferences, initialState: TrackingState? = nil) throws -> TrackingState {
    // The App already reads once to decide whether access guidance is needed.
    // Reuse that value, but still recheck after notification setup before writing.
    let before = try initialState ?? preferences.read()
    try preferences.prepareToWrite()
    guard try preferences.read() == before else {
        throw CycleFailure("Tracking changed during notification setup; nothing was written. Launch again to retry.")
    }
    let next = before.next
    // Clear the opposite direction first; never introduce a transient true/true.
    for (key, value) in next.writes { preferences.set(value, for: key) }
    try preferences.synchronize()
    let after = try preferences.read()
    guard after == next.state else {
        throw CycleFailure("Tracking readback did not match; success was not reported. Check permissions or concurrent VoiceOver preference changes.")
    }
    return after
}
