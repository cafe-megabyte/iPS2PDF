// ExtensionFoundation may overlap helper processes; Ghostscript work must stay one request at a time.
actor EnhancedSecurityRequestSerializer {
    static let shared = EnhancedSecurityRequestSerializer()
    private var isAvailable = true
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isAvailable {
            isAvailable = false
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        if waiters.isEmpty {
            isAvailable = true
        } else {
            waiters.removeFirst().resume()
        }
    }
}
