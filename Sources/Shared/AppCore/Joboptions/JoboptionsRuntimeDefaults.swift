import Foundation

/// Baseline defaults that apply when a Joboptions entry is absent.
///
/// Values supported by `setdistillerparams` mirror Ghostscript 10.07.1's
/// `/default` distiller configuration. Device- and application-level values
/// mirror the command-line setup used by iPS2PDF. Preserved Adobe-only keys
/// have no Ghostscript effect and therefore default to `false` in the UI.
enum JoboptionsRuntimeDefaults {
    static let maxSubsetPercentage = 100

    static let profileKeys: Set<String> = [
        "CalGrayProfile", "CalRGBProfile", "CalCMYKProfile", "sRGBProfile",
        "OutputICCProfile", "GraphicICCProfile", "ImageICCProfile", "TextICCProfile",
        "PDFXOutputIntentProfile"
    ]

    /// No default is invented for preserved Adobe-only numeric parameters
    /// such as DSCReportingLevel, or for free-text fields.
    static let scalarValues: [String: JoboptionsValue] = [
        "iPS2PDFStandard": .name("none"),
        "PDFACompatibilityPolicy": .number(0, original: "0"),
        "PDFXTrapped": .name("False"),
        "EncryptionR": .number(0, original: "0"),
        "Permissions": .number(-4, original: "-4"),
        "CannotEmbedFontPolicy": .name("Warning"),
        "BlendConversionStrategy": .name("Simple"),
        "ProcessColorModel": .name("DeviceRGB"),
        "PDFXTrimBoxToMediaBoxOffset": .array(Array(repeating: .number(0, original: "0"), count: 4)),
        "PDFXBleedBoxToTrimBoxOffset": .array(Array(repeating: .number(0, original: "0"), count: 4))
    ]

    static func value(forKey key: String) -> JoboptionsValue? {
        if let value = booleanValues[key] { return .boolean(value) }
        if profileKeys.contains(key) { return .string("") }
        return scalarValues[key]
    }

    /// These existing import representations all mean no explicit profile.
    /// This is a read-only normalization; the original bytes remain untouched.
    static func profileSelection(_ value: JoboptionsValue?) -> String {
        let text = value?.textualValue ?? value?.postScript ?? ""
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.caseInsensitiveCompare("None") == .orderedSame
            ? "" : text
    }

    static let booleanValues: [String: Bool] = [
        "Optimize": false,
        "DoThumbnails": false,
        "PreserveEPSInfo": true,
        "PreserveCopyPage": true,
        "UsePrologue": false,
        "Encrypt": false,

        "DownsampleColorImages": false,
        "AutoFilterColorImages": true,
        "EncodeColorImages": true,
        "AntiAliasColorImages": false,
        "CropColorImages": false,
        "DownsampleGrayImages": false,
        "AutoFilterGrayImages": true,
        "EncodeGrayImages": true,
        "AntiAliasGrayImages": false,
        "CropGrayImages": false,
        "DownsampleMonoImages": false,
        "EncodeMonoImages": true,
        "AntiAliasMonoImages": false,
        "CropMonoImages": false,
        "Downsample16BitImages": false,
        "PassThroughJPEGImages": true,
        "PassThroughJPXImages": true,
        "ConvertImagesToIndexed": true,

        "EmbedAllFonts": true,
        "EmbedSubstituteFonts": true,
        "SubsetFonts": true,

        "ConvertCMYKImagesToRGB": false,
        "PreserveDICMYKValues": false,
        "PreserveOverprintSettings": true,
        "PreserveBlack": false,
        "PreserveDeviceN": true,
        "PreserveSeparation": true,
        "ParseICCProfilesInComments": false,
        "DeviceGrayToK": true,
        "PreserveHalftoneInfo": false,

        "ASCII85EncodePages": false,
        "CompressPages": true,
        "CompressStreams": true,
        "WriteXRefStm": true,
        "WriteObjStms": true,
        "DetectBlends": true,
        "PreserveFlatness": false,
        "PreserveOPIComments": true,
        "ParseDSCComments": true,
        "ParseDSCCommentsForDocInfo": true,
        "EmitDSCWarnings": false,
        "LockDistillerParams": false,
        "AllowPSXObjects": false,
        "AutoPositionEPSFiles": true,
        "AllowTransparency": false,
        "HaveTransparency": true,
        "CreateJobTicket": false,
        "EmbedJobOptions": false,

        "iPS2PDFEmbedOutputIntentProfile": false,
        "PDFX1aCheck": false,
        "PDFX3Check": false,
        "AbortPDFAX": false,
        "PDFXNoTrimBoxError": true,
        "PDFXSetBleedBoxToMediaBox": true
    ]

    static func booleanValue(
        forKey key: String,
        in document: LosslessJoboptionsDocument?
    ) -> Bool {
        if let stored = document?.value(forKey: key)?.boolValue {
            return stored
        }
        guard let defaultValue = booleanValues[key] else {
            assertionFailure("Missing runtime default for Boolean Joboptions key /\(key)")
            return false
        }
        return defaultValue
    }
}
