import XCTest
@testable import TrackingCore

final class LaunchRequestsTests: XCTestCase {
    func testRapidRequestsAdvanceEveryCycleAndCancelStaleSpeech() {
        var queue = LaunchRequests()
        var state = TrackingMode.ignore.state
        queue.receive()
        state = state.next.state
        queue.complete()
        XCTAssertTrue(queue.mayAnnounce(1))
        // New launches arrive during preparation of the first utterance.
        for _ in 0..<11 { queue.receive() }
        XCTAssertFalse(queue.mayAnnounce(1))
        for _ in 0..<11 { state = state.next.state; queue.complete() }
        XCTAssertEqual(queue.received, 12)
        XCTAssertEqual(queue.completed, 12)
        XCTAssertEqual(state.mode, .ignore)
        XCTAssertFalse(queue.mayAnnounce(1))
        XCTAssertTrue(queue.mayAnnounce(12))
        queue.receive()
        state = state.next.state
        queue.complete()
        XCTAssertEqual(state.mode, .mouseFollowsVoiceOver)
        XCTAssertTrue(queue.mayAnnounce(13))
    }
}
