import XCTest
@testable import TrackingCore

final class MemoryPreferences: TrackingPreferences {
    var state: TrackingState
    var writes: [TrackingState] = []
    var failRead = false
    var failSync = false
    var ignoreWrites = false
    var syncCount = 0
    var prepareCount = 0
    var failPrepare = false
    var stateOnPrepare: TrackingState?
    init(_ state: TrackingState) { self.state = state }
    func read() throws -> TrackingState {
        if failRead { throw CycleFailure("denied") }
        return state
    }
    func set(_ value: Bool, for key: String) {
        if !ignoreWrites {
            state = TrackingState(mouseToVO: key == TrackingKey.mouseToVO ? value : state.mouseToVO,
                                  voToMouse: key == TrackingKey.voToMouse ? value : state.voToMouse)
        }
        writes.append(state)
    }
    func prepareToWrite() throws {
        prepareCount += 1
        if failPrepare { throw CycleFailure("notification registration unavailable") }
        if let stateOnPrepare { state = stateOnPrepare }
    }
    func synchronize() throws {
        syncCount += 1
        if failSync { throw CycleFailure("sync failure") }
    }
}

final class TrackingTests: XCTestCase {
    func testSixCyclesFromEveryNormalStartingState() throws {
        for mode in TrackingMode.allCases {
            let prefs = MemoryPreferences(mode.state)
            for _ in 0..<6 {
                let initialState = try prefs.read()
                _ = try cycle(prefs, initialState: initialState)
            }
            XCTAssertEqual(prefs.state, mode.state)
            XCTAssertEqual(prefs.syncCount, 6)
            XCTAssertFalse(prefs.writes.contains { $0.mouseToVO && $0.voToMouse })
        }
    }
    func testSpecifiedOrderAndFeedback() throws {
        let prefs = MemoryPreferences(TrackingMode.ignore.state)
        for expected in [TrackingMode.mouseFollowsVoiceOver, .voiceOverFollowsMouse, .ignore] {
            let result = try cycle(prefs)
            XCTAssertEqual(result, expected.state)
            XCTAssertEqual(try XCTUnwrap(result.mode).feedback(in: .chinese), expected.feedback(in: .chinese))
        }
    }
    func testInvalidPairNormalizesToIgnore() throws {
        let prefs = MemoryPreferences(TrackingState(mouseToVO: true, voToMouse: true))
        let result = try cycle(prefs)
        XCTAssertEqual(result, TrackingMode.ignore.state)
        XCTAssertFalse(prefs.writes.contains { $0.mouseToVO && $0.voToMouse })
    }
    func testReadFailureNeverWrites() {
        let prefs = MemoryPreferences(TrackingMode.ignore.state)
        prefs.failRead = true
        XCTAssertThrowsError(try cycle(prefs))
        XCTAssertTrue(prefs.writes.isEmpty)
        XCTAssertEqual(prefs.syncCount, 0)
        XCTAssertEqual(prefs.prepareCount, 0)
    }
    func testNotificationSetupFailureNeverWrites() {
        let prefs = MemoryPreferences(TrackingMode.ignore.state)
        prefs.failPrepare = true
        XCTAssertThrowsError(try cycle(prefs))
        XCTAssertTrue(prefs.writes.isEmpty)
        XCTAssertEqual(prefs.syncCount, 0)
    }
    func testStateChangeDuringSetupNeverWrites() {
        let prefs = MemoryPreferences(TrackingMode.ignore.state)
        prefs.stateOnPrepare = TrackingMode.voiceOverFollowsMouse.state
        XCTAssertThrowsError(try cycle(prefs))
        XCTAssertTrue(prefs.writes.isEmpty)
        XCTAssertEqual(prefs.syncCount, 0)
    }
    func testReusedInitialReadStillRejectsStaleState() {
        let prefs = MemoryPreferences(TrackingMode.ignore.state)
        XCTAssertThrowsError(try cycle(prefs, initialState: TrackingMode.mouseFollowsVoiceOver.state))
        XCTAssertTrue(prefs.writes.isEmpty)
        XCTAssertEqual(prefs.prepareCount, 1)
        XCTAssertEqual(prefs.syncCount, 0)
    }
    func testWriteMismatchAndSyncFailureAreNotSuccess() {
        let prefs = MemoryPreferences(TrackingMode.ignore.state)
        prefs.ignoreWrites = true
        XCTAssertThrowsError(try cycle(prefs))
        prefs.ignoreWrites = false
        prefs.failSync = true
        XCTAssertThrowsError(try cycle(prefs))
    }
}
