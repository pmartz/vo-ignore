// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "VoiceOverMouseCycle",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "FastPreferencesC", path: "Sources/FastPreferencesC", publicHeadersPath: "include",
                linkerSettings: [.linkedFramework("CoreFoundation")]),
        .target(name: "TrackingCore", dependencies: ["FastPreferencesC"], path: "Sources/Core", resources: [.process("Resources")]),
        .testTarget(name: "TrackingCoreTests", dependencies: ["TrackingCore"], path: "Tests")
    ]
)
