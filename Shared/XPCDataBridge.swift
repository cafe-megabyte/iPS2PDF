import Foundation
import XPC

enum XPCDataBridge {
    static func set(_ data: Data, forKey key: String, in dictionary: XPCDictionary) {
        dictionary.withUnsafeUnderlyingDictionary { object in
            key.withCString { keyPointer in
                data.withUnsafeBytes { bytes in
                    xpc_dictionary_set_data(object, keyPointer, bytes.baseAddress, data.count)
                }
            }
        }
    }

    static func data(forKey key: String, from dictionary: XPCDictionary) -> Data? {
        dictionary.withUnsafeUnderlyingDictionary { object in
            key.withCString { keyPointer in
                var length = 0
                guard let pointer = xpc_dictionary_get_data(object, keyPointer, &length) else {
                    return nil
                }
                return Data(bytes: pointer, count: length)
            }
        }
    }
}
