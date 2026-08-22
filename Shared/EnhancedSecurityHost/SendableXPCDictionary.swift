import XPC

struct SendableXPCDictionary: @unchecked Sendable {
    let value: XPCDictionary
}
