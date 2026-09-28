// Derived from pmartz/vo-ignore, Copyright (c) 2026 Paul Martz (MIT).
// Private Apple API: see Docs/PrivateAPI.md. No OS-version-based dispatch.
import Foundation
import ObjectiveC.runtime
import CoreFoundation

struct TrackingValueUnavailable: Error, CustomStringConvertible {
    let key: String
    var description: String {
        "Cannot reliably read \(key). VoiceOver App Group access may be denied or the private API may have changed; nil is not treated as false."
    }
}

final class PrivatePreferences: TrackingPreferences {
    private typealias Shared = @convention(c) (AnyClass, Selector) -> AnyObject?
    private typealias Get = @convention(c) (AnyObject, Selector, NSString) -> AnyObject?
    private typealias Set = @convention(c) (AnyObject, Selector, NSNumber, NSString) -> Void
    private typealias Sync = @convention(c) (AnyObject, Selector) -> Void
    private typealias SetFamily = @convention(c) (AnyObject, Selector, Int64) -> Void

    private let bundle: Bundle
    private let object: AnyObject
    private let getter: Get
    private let setter: Set
    private let sync: Sync
    private let setFamily: SetFamily
    private let familyStringIvar: Ivar
    private let getSelector = NSSelectorFromString("valueForKey:")
    private let setSelector = NSSelectorFromString("setValue:forKey:")
    private let syncSelector = NSSelectorFromString("synchronizeWhileIWait")
    private let familySelector = NSSelectorFromString("setFamilyMember:")

    init() throws {
        let path = "/System/Library/PrivateFrameworks/ScreenReaderCore.framework"
        guard let bundle = Bundle(path: path) else { throw CycleFailure("Cannot locate ScreenReaderCore.framework") }
        try bundle.loadAndReturnError()
        self.bundle = bundle
        guard let cls = NSClassFromString("SCRCUserDefaults") else { throw CycleFailure("Cannot find SCRCUserDefaults") }
        let sharedSelector = NSSelectorFromString("sharedUserDefaults")
        let shared = try Self.validate(class_getClassMethod(cls, sharedSelector),
                                       name: "sharedUserDefaults", result: "@", arguments: ["@", ":"])
        let sharedFunction = unsafeBitCast(method_getImplementation(shared), to: Shared.self)
        guard let object = sharedFunction(cls, sharedSelector), let actualClass = object_getClass(object) else {
            throw CycleFailure("sharedUserDefaults returned no object")
        }
        self.object = object
        let get = try Self.validate(class_getInstanceMethod(actualClass, getSelector),
                                   name: "valueForKey:", result: "@", arguments: ["@", ":", "@"])
        let set = try Self.validate(class_getInstanceMethod(actualClass, setSelector),
                                   name: "setValue:forKey:", result: "v", arguments: ["@", ":", "@", "@"])
        // synchronize is asynchronous on 26.6. The checked synchronous equivalent
        // completes framework work before this one-shot process exits.
        let synchronize = try Self.validate(class_getInstanceMethod(actualClass, syncSelector),
                                            name: "synchronizeWhileIWait", result: "v", arguments: ["@", ":"])
        let family = try Self.validate(class_getInstanceMethod(actualClass, familySelector),
                                       name: "setFamilyMember:", result: "v", arguments: ["@", ":", "q"])
        guard let ivar = class_getInstanceVariable(actualClass, "_familyMemberString"),
              let encoding = ivar_getTypeEncoding(ivar),
              ["@", "@\"NSString\""].contains(String(cString: encoding)) else {
            throw CycleFailure("Cannot validate the private notification identity; nothing was written.")
        }
        familyStringIvar = ivar
        getter = unsafeBitCast(method_getImplementation(get), to: Get.self)
        setter = unsafeBitCast(method_getImplementation(set), to: Set.self)
        sync = unsafeBitCast(method_getImplementation(synchronize), to: Sync.self)
        setFamily = unsafeBitCast(method_getImplementation(family), to: SetFamily.self)

    }

    func prepareToWrite() throws {
        // On 26.6, sharedUserDefaults alone leaves _familyMemberString nil and
        // _setValue:forKey:proxy: SKIPS distributed notifications entirely.
        // The framework's family table maps 4 to "bcst". Register using its
        // method, then check the actual identity; never write the ivar or rely
        // on a hard-coded offset. Missing/changed identity fails before writes.
        // Registration also posts the framework's launch notice. See PrivateAPI
        // for its portable-preference behavior and the untested macOS 27 limit.
        setFamily(object, familySelector, 4)
        guard let name = object_getIvar(object, familyStringIvar) as? String, name == "bcst" else {
            throw CycleFailure("The private notification member mapping changed; nothing was written.")
        }
    }

    private static func validate(_ method: Method?, name: String, result: String, arguments: [String]) throws -> Method {
        guard let method, method_getNumberOfArguments(method) == arguments.count else {
            throw CycleFailure("Private method missing or argument count changed: \(name). Nothing was written.")
        }
        func take(_ pointer: UnsafeMutablePointer<CChar>?) -> String {
            guard let pointer else { return "" }
            defer { free(pointer) }
            return String(cString: pointer)
        }
        let returnType = take(method_copyReturnType(method))
        let argumentTypes = arguments.indices.map { take(method_copyArgumentType(method, UInt32($0))) }
        guard returnType == result, argumentTypes == arguments else {
            throw CycleFailure("Private method ABI changed: \(name), \(returnType) \(argumentTypes). Nothing was written.")
        }
        return method
    }

    func read() throws -> TrackingState {
        func boolean(_ key: String) throws -> Bool {
            guard let raw = getter(object, getSelector, key as NSString) else {
                throw TrackingValueUnavailable(key: key)
            }
            guard let value = raw as? NSNumber,
                  CFGetTypeID(value) == CFBooleanGetTypeID() || value == 0 || value == 1 else {
                throw CycleFailure("\(key) is not a Boolean value; nothing was written.")
            }
            return value.boolValue
        }
        return try TrackingState(mouseToVO: boolean(TrackingKey.mouseToVO), voToMouse: boolean(TrackingKey.voToMouse))
    }

    func set(_ value: Bool, for key: String) {
        setter(object, setSelector, NSNumber(value: value), key as NSString)
    }

    func synchronize() throws { sync(object, syncSelector) }
}
