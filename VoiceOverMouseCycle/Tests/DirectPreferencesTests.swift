import XCTest
import Foundation
import CoreFoundation
import Darwin
import FastPreferencesC
@testable import TrackingCore

private final class NoticeRecorder: NSObject {
    var payloads: [[String: Any]] = []
    @objc func receive(_ notification: Notification) {
        if let info = notification.userInfo as? [String: Any] { payloads.append(info) }
    }
}

private final class DirectFixture {
    typealias Set = @convention(c) (CFString, CFTypeRef?, CFString, CFString) -> Void
    typealias Copy = @convention(c) (CFString, CFString, CFString) -> Unmanaged<CFTypeRef>?
    typealias Sync = @convention(c) (CFString, CFString, CFString, CFString) -> Bool
    let root: URL
    let prefix: String
    let notification: String
    private let setValue: Set
    private let copyValue: Copy
    private let sync: Sync
    var container: CFString { root.path as CFString }
    init() throws {
        try XCTSkipUnless(VMCFastRuntimeSupported(), "Private C ABI requires the inspected framework binaries")
        func symbol(_ name: String) throws -> UnsafeMutableRawPointer {
            try XCTUnwrap(dlsym(UnsafeMutableRawPointer(bitPattern: -2), name))
        }
        setValue = unsafeBitCast(try symbol("_CFPreferencesSetAppValueWithContainer"), to: Set.self)
        copyValue = unsafeBitCast(try symbol("_CFPreferencesCopyAppValueWithContainer"), to: Copy.self)
        sync = unsafeBitCast(try symbol("_CFPreferencesSynchronizeWithContainer"), to: Sync.self)
        let id = UUID().uuidString
        root = URL(fileURLWithPath: "/private/tmp/VoiceOverMouseCycle-fast-test-\(id)")
        prefix = "org.example.VoiceOverMouseCycle.FastTest.\(id)"
        notification = prefix + ".Change"
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Library/Preferences/\(prefix)"),
                                               withIntermediateDirectories: true)
        try put(TrackingKey.mouseToVO, NSNumber(value: false))
        try put(TrackingKey.voToMouse, NSNumber(value: false))
        try put("unrelated", "untouched" as NSString)
    }
    deinit { try? FileManager.default.removeItem(at: root) }
    func domain(_ suffix: String) -> CFString { (prefix + suffix) as CFString }
    func put(_ key: String, _ value: AnyObject?, suffix: String = "/default") throws {
        setValue(key as CFString, value, domain(suffix), container)
        XCTAssertTrue(sync(domain(suffix), kCFPreferencesCurrentUser, kCFPreferencesAnyHost, container))
    }
    func get(_ key: String, suffix: String = "/default") -> AnyObject? {
        _ = sync(domain(suffix), kCFPreferencesCurrentUser, kCFPreferencesAnyHost, container)
        return copyValue(key as CFString, domain(suffix), container)?.takeRetainedValue()
    }
    func preferences() throws -> DirectPreferences {
        try XCTUnwrap(DirectPreferences(container: root.path, domain: prefix, notice: notification))
    }
}

final class DirectPreferencesTests: XCTestCase {
    func testProductionNotificationPayloadWithAndWithoutDefaultProfileKey() throws {
        let fixture = try DirectFixture()
        let recorder = NoticeRecorder()
        let center = DistributedNotificationCenter.default()
        center.addObserver(recorder, selector: #selector(NoticeRecorder.receive(_:)),
                           name: Notification.Name(fixture.notification), object: "bcst", suspensionBehavior: .deliverImmediately)
        defer { center.removeObserver(recorder) }
        _ = try cycle(fixture.preferences())
        try fixture.put("currentProfile", "default" as NSString, suffix: "/master")
        _ = try cycle(fixture.preferences())
        let deadline = Date(timeIntervalSinceNow: 2)
        while recorder.payloads.count < 4 && Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
        XCTAssertEqual(recorder.payloads.count, 4)
        guard recorder.payloads.count == 4 else { return }
        for (i, info) in recorder.payloads.enumerated() {
            XCTAssertEqual((info["SCRCUserDefaultsProxyType"] as? NSNumber)?.intValue, 0)
            XCTAssertEqual(info.count, i < 2 ? 2 : 3)
            if i < 2 { XCTAssertNil(info["profileKey"]) }
            else { XCTAssertEqual(info["profileKey"] as? String, "default") }
        }
        XCTAssertEqual((recorder.payloads[0][TrackingKey.voToMouse] as? NSNumber)?.boolValue, false)
        XCTAssertEqual((recorder.payloads[1][TrackingKey.mouseToVO] as? NSNumber)?.boolValue, true)
        XCTAssertEqual((recorder.payloads[2][TrackingKey.mouseToVO] as? NSNumber)?.boolValue, false)
        XCTAssertEqual((recorder.payloads[3][TrackingKey.voToMouse] as? NSNumber)?.boolValue, true)
    }
    func testProductionCBackendSixCyclesAndJournalInIsolatedContainer() throws {
        let fixture = try DirectFixture()
        for i in 0..<6 {
            let result = try cycle(fixture.preferences())
            XCTAssertEqual(result, [TrackingMode.mouseFollowsVoiceOver, .voiceOverFollowsMouse, .ignore][i % 3].state)
            XCTAssertEqual((fixture.get(TrackingKey.mouseToVO) as? NSNumber)?.boolValue, result.mouseToVO)
            XCTAssertEqual((fixture.get(TrackingKey.voToMouse) as? NSNumber)?.boolValue, result.voToMouse)
            XCTAssertGreaterThan((fixture.get(TrackingKey.mouseToVO, suffix: "/journal") as? NSNumber)?.doubleValue ?? 0, 0)
            XCTAssertGreaterThan((fixture.get(TrackingKey.voToMouse, suffix: "/journal") as? NSNumber)?.doubleValue ?? 0, 0)
            XCTAssertNil(fixture.get("lastTouchedKey", suffix: ".local"))
            XCTAssertEqual(fixture.get("unrelated") as? String, "untouched")
        }
    }
    func testMissingAndInvalidTrackingValuesNeverWrite() throws {
        let fixture = try DirectFixture()
        for value: AnyObject? in [nil, "false" as NSString, NSNumber(value: 2)] {
            try fixture.put(TrackingKey.voToMouse, value)
            XCTAssertThrowsError(try cycle(fixture.preferences()))
            XCTAssertEqual((fixture.get(TrackingKey.mouseToVO) as? NSNumber)?.boolValue, false)
            XCTAssertNil(fixture.get(TrackingKey.mouseToVO, suffix: "/journal"))
        }
    }
    func testDefaultProfileAndDoubleTrueNormalization() throws {
        let fixture = try DirectFixture()
        try fixture.put("currentProfile", "default" as NSString, suffix: "/master")
        try fixture.put(TrackingKey.mouseToVO, NSNumber(value: true))
        try fixture.put(TrackingKey.voToMouse, NSNumber(value: true))
        let result = try cycle(fixture.preferences())
        XCTAssertEqual(result, TrackingMode.ignore.state)
    }
    func testProfileChangeBeforeCommitPreventsWrites() throws {
        let fixture = try DirectFixture()
        let prefs = try fixture.preferences()
        _ = try prefs.read()
        try prefs.prepareToWrite()
        prefs.set(false, for: TrackingKey.voToMouse)
        prefs.set(true, for: TrackingKey.mouseToVO)
        try fixture.put("currentProfile", "custom" as NSString, suffix: "/master")
        XCTAssertThrowsError(try prefs.synchronize())
        XCTAssertEqual((fixture.get(TrackingKey.mouseToVO) as? NSNumber)?.boolValue, false)
        XCTAssertNil(fixture.get(TrackingKey.mouseToVO, suffix: "/journal"))
    }
    func testPortableLinkIncludingDanglingLinkRequiresFallback() throws {
        let fixture = try DirectFixture()
        let link = fixture.root.appendingPathComponent("Library/Preferences/\(fixture.prefix).portable")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: fixture.root.appendingPathComponent("missing-device").path)
        XCTAssertThrowsError(try cycle(fixture.preferences())) { XCTAssertTrue($0 is FastPathFallback) }
        XCTAssertEqual((fixture.get(TrackingKey.mouseToVO) as? NSNumber)?.boolValue, false)
    }
    func testCustomProfileUsesFrameworkBeforeAnyDirectWrites() throws {
        let fixture = try DirectFixture()
        try fixture.put("currentProfile", "custom" as NSString, suffix: "/master")
        let original = MemoryPreferences(TrackingMode.ignore.state)
        var fallbackCount = 0
        let adaptive = try AdaptivePreferences(candidate: fixture.preferences()) {
            fallbackCount += 1
            return original
        }
        let result = try cycle(adaptive)
        XCTAssertEqual(fallbackCount, 1)
        XCTAssertEqual(result, TrackingMode.mouseFollowsVoiceOver.state)
        XCTAssertEqual(original.writes.count, 2)
        XCTAssertEqual((fixture.get(TrackingKey.mouseToVO) as? NSNumber)?.boolValue, false)
        XCTAssertNil(fixture.get(TrackingKey.mouseToVO, suffix: "/journal"))
    }
    func testFailedCommitNeverFallsBackOrCyclesAgain() throws {
        let fixture = try DirectFixture()
        let direct = try fixture.preferences()
        var fallbackCount = 0
        let adaptive = try AdaptivePreferences(candidate: direct) {
            fallbackCount += 1
            return MemoryPreferences(TrackingMode.ignore.state)
        }
        _ = try adaptive.read()
        try adaptive.prepareToWrite()
        adaptive.set(false, for: TrackingKey.voToMouse)
        adaptive.set(true, for: TrackingKey.mouseToVO)
        try fixture.put(TrackingKey.mouseToVO, NSNumber(value: true))
        XCTAssertThrowsError(try adaptive.synchronize())
        XCTAssertEqual(fallbackCount, 0)
        XCTAssertNil(fixture.get(TrackingKey.mouseToVO, suffix: "/journal"))
    }
}
