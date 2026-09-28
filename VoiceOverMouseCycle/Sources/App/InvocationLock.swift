import Foundation
import Darwin

final class InvocationLock {
    private let descriptor: Int32
    init() throws {
        let identifier = Bundle.main.bundleIdentifier ?? "org.example.VoiceOverMouseCycle"
        let path = NSTemporaryDirectory() + identifier + ".lock"
        descriptor = Darwin.open(path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw CycleFailure("Cannot create the invocation lock") }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw CycleFailure("Another tracking change is in progress; try again after it finishes")
        }
    }
    deinit { flock(descriptor, LOCK_UN); close(descriptor) }
}
