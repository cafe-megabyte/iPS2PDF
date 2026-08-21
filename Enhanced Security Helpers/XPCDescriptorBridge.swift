import Darwin
import XPC

enum XPCDescriptorBridge {
    static func set(_ descriptor: Int32, forKey key: String, in dictionary: XPCDictionary) {
        dictionary.withUnsafeUnderlyingDictionary { object in
            key.withCString { xpc_dictionary_set_fd(object, $0, descriptor) }
        }
    }

    static func duplicate(forKey key: String, from dictionary: XPCDictionary) -> Int32 {
        dictionary.withUnsafeUnderlyingDictionary { object in
            key.withCString { xpc_dictionary_dup_fd(object, $0) }
        }
    }
}
