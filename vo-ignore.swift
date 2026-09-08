// Copyright (c) 2026 Paul Martz

import AVFoundation
import Foundation
import ObjectiveC.runtime

// Use VoiceOver's private preferences API so changes reach the running process.
let framework = "/System/Library/PrivateFrameworks/ScreenReaderCore.framework"

guard let bundle = Bundle(path: framework) else {
fatalError("Cannot locate ScreenReaderCore")
}

try bundle.loadAndReturnError()

guard let cls: AnyClass = NSClassFromString("SCRCUserDefaults") else {
fatalError("Cannot find SCRCUserDefaults")
}

// Get the shared VoiceOver preferences object.
let sharedSelector = NSSelectorFromString("sharedUserDefaults")

guard let sharedMethod = class_getClassMethod(cls, sharedSelector) else {
fatalError("Cannot find sharedUserDefaults")
}

typealias SharedFunction =
@convention(c) (AnyClass, Selector) -> AnyObject

let sharedFunction = unsafeBitCast(
method_getImplementation(sharedMethod),
to: SharedFunction.self
)

let defaults = sharedFunction(cls, sharedSelector)

// Set both cursor-tracking directions off.
let setSelector = NSSelectorFromString("setValue:forKey:")

guard let setMethod = class_getInstanceMethod(cls, setSelector) else {
fatalError("Cannot find setValue:forKey:")
}

typealias SetFunction =
@convention(c) (AnyObject, Selector, AnyObject, AnyObject) -> Void

let setFunction = unsafeBitCast(
method_getImplementation(setMethod),
to: SetFunction.self
)

let off = NSNumber(value: false)

setFunction(
defaults,
setSelector,
off,
"SCRConfigurationCursorTrackingMToVO" as NSString
)

setFunction(
defaults,
setSelector,
off,
"SCRConfigurationCursorTrackingVOToM" as NSString
)

// Flush preferences and propagate the change.
let syncSelector = NSSelectorFromString("synchronize")

guard let syncMethod = class_getInstanceMethod(cls, syncSelector) else {
fatalError("Cannot find synchronize")
}

typealias SyncFunction =
@convention(c) (AnyObject, Selector) -> Void

let syncFunction = unsafeBitCast(
method_getImplementation(syncMethod),
to: SyncFunction.self
)

syncFunction(defaults, syncSelector)

// Speak a short confirmation.
class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {
var finished = false

func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
finished = true
}
}

let speechDelegate = SpeechDelegate()
let synthesizer = AVSpeechSynthesizer()
synthesizer.delegate = speechDelegate

let utterance = AVSpeechUtterance(string: "Mouse set to ignores.")
utterance.prefersAssistiveTechnologySettings = true
synthesizer.speak(utterance)

while !speechDelegate.finished {
RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
}
