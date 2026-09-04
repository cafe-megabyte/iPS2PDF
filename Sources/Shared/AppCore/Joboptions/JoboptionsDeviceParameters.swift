import Foundation

/// Transport only: these pdfwrite device parameters are ignored by
/// setdistillerparams. Values are already resolved by the consistency engine.
/// ICC parameters are applied separately once their file paths are resolved.
enum JoboptionsDeviceParameters {
    static let keys = [
        "PDFACompatibilityPolicy", "PDFXNoTrimBoxError", "EncryptionR",
        "OwnerPassword", "UserPassword", "Permissions",
        "BlendConversionStrategy", "ProcessColorModel"
    ]

    static func program(in document: LosslessJoboptionsDocument) -> String {
        let entries = keys.compactMap { key -> String? in
            guard let value = document.value(forKey: key) else { return nil }
            return "/\(key) \(value.postScript)"
        }
        guard !entries.isEmpty else { return "" }
        // The lock is write-only in Ghostscript. Restore the configured value
        // after applying the rest of our own settings, before running the input.
        let locked = JoboptionsRuntimeDefaults.booleanValue(forKey: "LockDistillerParams", in: document)
        return """
        << /LockDistillerParams false \(entries.joined(separator: " ")) >> setpagedevice
        << /LockDistillerParams \(locked) >> setdistillerparams
        """
    }

    static func runtimeData(in document: LosslessJoboptionsDocument) throws -> Data {
        try document.data(appendingPostScript: program(in: document))
    }
}
