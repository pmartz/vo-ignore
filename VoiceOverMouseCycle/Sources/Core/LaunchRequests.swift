// One logical cycle for every delivered open/reopen request. Speech is a
// replaceable consequence, not a lock around the requests themselves.
struct LaunchRequests {
    private(set) var received = 0
    private(set) var completed = 0
    var pending: Int { received - completed }
    mutating func receive() { received += 1 }
    mutating func complete() { precondition(pending > 0); completed += 1 }
    func mayAnnounce(_ revision: Int) -> Bool { pending == 0 && completed == revision }
}
