import XPC

/// Concurrency boundary wrapper for an XPC reply dictionary.
struct SendableXPCDictionary: @unchecked Sendable {
    let value: XPCDictionary
}
