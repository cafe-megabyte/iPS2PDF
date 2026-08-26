#if os(macOS)
import CoreFoundation
import Foundation
import XPC

enum MacOSXPCMessageCodec {
    static func encode(_ dictionary: XPCDictionary) throws -> Data {
        var propertyList: [String: Any] = [:]
        try dictionary.forEach { key, value in
            switch xpc_get_type(value) {
            case XPC_TYPE_BOOL:
                propertyList[key] = xpc_bool_get_value(value)
            case XPC_TYPE_INT64:
                propertyList[key] = xpc_int64_get_value(value)
            case XPC_TYPE_STRING:
                guard let string = xpc_string_get_string_ptr(value) else {
                    throw CocoaError(.coderInvalidValue)
                }
                propertyList[key] = String(cString: string)
            default:
                throw CocoaError(.coderInvalidValue)
            }
        }
        return try PropertyListSerialization.data(
            fromPropertyList: propertyList,
            format: .binary,
            options: 0
        )
    }

    static func decode(_ data: Data) throws -> XPCDictionary {
        guard let propertyList = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any]
        else {
            throw CocoaError(.coderInvalidValue)
        }

        var dictionary = XPCDictionary()
        for (key, value) in propertyList {
            switch value {
            case let string as String:
                dictionary[key] = string
            case let number as NSNumber
                where CFGetTypeID(number) == CFBooleanGetTypeID():
                dictionary[key] = number.boolValue
            case let number as NSNumber:
                dictionary[key] = number.int64Value
            default:
                throw CocoaError(.coderInvalidValue)
            }
        }
        return dictionary
    }
}
#endif
