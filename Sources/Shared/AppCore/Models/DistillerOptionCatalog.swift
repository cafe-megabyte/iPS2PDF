import Foundation

enum DistillerOptionCatalog {
    static let ghostscriptVersion = "10.07.1"

    static let options: [DistillerOptionDefinition] = [
        option("CompatibilityLevel", "PDF compatibility", .general, .literal(["1.1", "1.2", "1.3", "1.4", "1.5", "1.6", "1.7", "2.0"])),
        option("AutoRotatePages", "Auto-rotate pages", .general, .name(["None", "All", "PageByPage"])),
        option("Binding", "Binding", .general, .name(["Left", "Right"])),
        option("StartPage", "First page", .general, .integer(1...999_999)),
        option("EndPage", "Last page", .general, .integer(-1...999_999)),
        option("Optimize", "Optimize for fast web view", .general, .boolean),
        option("DoThumbnails", "Embed page thumbnails", .general, .boolean),
        option("PreserveEPSInfo", "Preserve EPS information", .general, .boolean),
        option("PreserveCopyPage", "Preserve copy-page semantics", .general, .boolean),
        option("UsePrologue", "Use prologue", .general, .boolean),
        option("HWResolution", "Device resolution", .general, .string),
        option("PageSize", "Default page size", .general, .string),

        option("Encrypt", "Encrypt PDF", .general, .boolean),
        option("EncryptionR", "Encryption revision", .general, .integer(0...6)),
        option("OwnerPassword", "Owner password", .general, .string),
        option("UserPassword", "User password", .general, .string),
        option("Permissions", "Document permissions", .general, .integer(-2_147_483_648...2_147_483_647)),

        option("DownsampleColorImages", "Downsample color images", .images, .boolean),
        option("ColorImageDownsampleType", "Color downsampling", .images, .name(["None", "Average", "Bicubic", "Subsample"])),
        option("ColorImageResolution", "Color image resolution", .images, .integer(1...9_600)),
        option("ColorImageDownsampleThreshold", "Color downsample threshold", .images, .number(1...10)),
        option("ColorImageMinResolution", "Minimum color resolution", .images, .integer(1...9_600)),
        option("ColorImageMinResolutionPolicy", "Low color resolution policy", .images, .name(["OK", "Warning", "Error"])),
        option("ColorImageFilter", "Color compression", .images, .name(["DCTEncode", "FlateEncode", "JPXEncode"])),
        option("AutoFilterColorImages", "Automatic color compression", .images, .boolean),
        option("EncodeColorImages", "Compress color images", .images, .boolean),
        option("AntiAliasColorImages", "Anti-alias color images", .images, .boolean),
        option("CropColorImages", "Crop color images to frames", .images, .boolean),
        option("DownsampleGrayImages", "Downsample grayscale images", .images, .boolean),
        option("GrayImageDownsampleType", "Grayscale downsampling", .images, .name(["None", "Average", "Bicubic", "Subsample"])),
        option("GrayImageResolution", "Grayscale image resolution", .images, .integer(1...9_600)),
        option("GrayImageDownsampleThreshold", "Grayscale downsample threshold", .images, .number(1...10)),
        option("GrayImageMinResolution", "Minimum grayscale resolution", .images, .integer(1...9_600)),
        option("GrayImageMinResolutionPolicy", "Low grayscale resolution policy", .images, .name(["OK", "Warning", "Error"])),
        option("GrayImageFilter", "Grayscale compression", .images, .name(["DCTEncode", "FlateEncode", "JPXEncode"])),
        option("AutoFilterGrayImages", "Automatic grayscale compression", .images, .boolean),
        option("EncodeGrayImages", "Compress grayscale images", .images, .boolean),
        option("AntiAliasGrayImages", "Anti-alias grayscale images", .images, .boolean),
        option("CropGrayImages", "Crop grayscale images to frames", .images, .boolean),
        option("DownsampleMonoImages", "Downsample monochrome images", .images, .boolean),
        option("MonoImageDownsampleType", "Monochrome downsampling", .images, .name(["None", "Average", "Bicubic", "Subsample"])),
        option("MonoImageResolution", "Monochrome image resolution", .images, .integer(1...9_600)),
        option("MonoImageDownsampleThreshold", "Monochrome downsample threshold", .images, .number(1...10)),
        option("MonoImageMinResolution", "Minimum monochrome resolution", .images, .integer(1...9_600)),
        option("MonoImageMinResolutionPolicy", "Low monochrome resolution policy", .images, .name(["OK", "Warning", "Error"])),
        option("MonoImageFilter", "Monochrome compression", .images, .name(["CCITTFaxEncode", "FlateEncode", "RunLengthEncode"])),
        option("EncodeMonoImages", "Compress monochrome images", .images, .boolean),
        option("AntiAliasMonoImages", "Anti-alias monochrome images", .images, .boolean),
        option("CropMonoImages", "Crop monochrome images to frames", .images, .boolean),
        option("Downsample16BitImages", "Downsample 16-bit images", .images, .boolean),
        option("PassThroughJPEGImages", "Pass through JPEG images", .images, .boolean),
        option("PassThroughJPXImages", "Pass through JPEG 2000 images", .images, .boolean),
        option("ConvertImagesToIndexed", "Convert suitable images to indexed color", .images, .boolean),

        option("EmbedAllFonts", "Embed all fonts", .fonts, .boolean),
        option("EmbedSubstituteFonts", "Embed substitute fonts", .fonts, .boolean),
        option("SubsetFonts", "Subset embedded fonts", .fonts, .boolean),
        option("MaxSubsetPct", "Subset fonts below", .fonts, .integer(1...100)),
        option("EmbedOpenType", "Embed OpenType fonts", .fonts, .boolean),
        option("CannotEmbedFontPolicy", "When embedding fails", .fonts, .name(["Ignore", "Warning", "Error"])),

        option("ColorConversionStrategy", "Color conversion strategy", .color, .name(["LeaveColorUnchanged", "RGB", "sRGB", "CMYK", "Gray", "UseDeviceIndependentColor"])),
        option("BlendConversionStrategy", "Blend conversion strategy", .color, .name(["None", "Simple", "Managed"])),
        option("ConvertCMYKImagesToRGB", "Convert CMYK images to RGB", .color, .boolean),
        option("ProcessColorModel", "Process color model", .color, .name(["DeviceGray", "DeviceRGB", "DeviceCMYK"])),
        option("DefaultRenderingIntent", "Default rendering intent", .color, .name(["Default", "Perceptual", "RelativeColorimetric", "Saturation", "AbsoluteColorimetric"])),
        option("PreserveOverprintSettings", "Preserve overprint settings", .color, .boolean),
        option("PreserveBlack", "Preserve black", .color, .boolean),
        option("PreserveDeviceN", "Preserve DeviceN colorants", .color, .boolean),
        option("PreserveSeparation", "Preserve separations", .color, .boolean),
        option("ParseICCProfilesInComments", "Honor ICC profiles in comments", .color, .boolean),
        option("CalGrayProfile", "Working grayscale profile", .color, .string),
        option("CalRGBProfile", "Working RGB profile", .color, .string),
        option("CalCMYKProfile", "Working CMYK profile", .color, .string),
        option("sRGBProfile", "sRGB profile", .color, .string),
        option("OutputICCProfile", "Output ICC profile", .color, .string),
        option("GraphicICCProfile", "Graphics ICC profile", .color, .string),
        option("ImageICCProfile", "Image ICC profile", .color, .string),
        option("TextICCProfile", "Text ICC profile", .color, .string),
        option("DeviceGrayToK", "Map device gray to black", .color, .boolean),

        option("ASCII85EncodePages", "ASCII85-encode page streams", .advanced, .boolean),
        option("CompressPages", "Compress page streams", .advanced, .boolean),
        option("CompressStreams", "Compress object streams", .advanced, .boolean),
        option("CompressObjects", "Object compression", .advanced, .name(["Off", "Tags", "All"])),
        option("WriteXRefStm", "Write cross-reference streams", .advanced, .boolean),
        option("WriteObjStms", "Write object streams", .advanced, .boolean),
        option("DetectBlends", "Detect blends", .advanced, .boolean),
        option("DetectCurves", "Curve detection tolerance", .advanced, .number(0...10)),
        option("PreserveFlatness", "Preserve flatness", .advanced, .boolean),
        option("PreserveHalftoneInfo", "Preserve halftone information", .advanced, .boolean),
        option("PreserveOPIComments", "Preserve OPI comments", .advanced, .boolean),
        option("ParseDSCComments", "Process DSC comments", .advanced, .boolean),
        option("ParseDSCCommentsForDocInfo", "Use DSC comments for document info", .advanced, .boolean),
        option("EmitDSCWarnings", "Report DSC warnings", .advanced, .boolean),
        option("DSCReportingLevel", "DSC reporting level", .advanced, .integer(0...2)),
        option("TransferFunctionInfo", "Transfer functions", .advanced, .name(["Preserve", "Apply", "Remove"])),
        option("UCRandBGInfo", "Undercolor removal and black generation", .advanced, .name(["Preserve", "Apply", "Remove"])),
        option("OPM", "Overprint mode", .advanced, .integer(0...1)),
        option("LockDistillerParams", "Lock Distiller parameters", .advanced, .boolean),
        option("AutoPositionEPSFiles", "Auto-position EPS files", .advanced, .boolean),
        option("AllowTransparency", "Allow transparency operators", .advanced, .boolean),
        option("HaveTransparency", "Enable transparency device", .advanced, .boolean),
        option("CreateJobTicket", "Create job ticket", .advanced, .boolean, compatibility: "Preserved; ignored by Ghostscript"),
        option("EmbedJobOptions", "Embed Joboptions", .advanced, .boolean, compatibility: "Preserved; not interpreted by Ghostscript pdfwrite"),

        option("iPS2PDFStandard", "PDF standard", .standards, .name(PDFStandard.allCases.map(\.rawValue))),
        option("PDFACompatibilityPolicy", "PDF/A compatibility policy", .standards, .integer(0...2)),
        option("PDFX1aCheck", "Check PDF/X-1", .standards, .boolean),
        option("PDFX3Check", "Check PDF/X-3", .standards, .boolean),
        option("PDFXOutputCondition", "PDF/X output condition", .standards, .string),
        option("PDFXOutputConditionIdentifier", "PDF/X condition identifier", .standards, .string),
        option("PDFXOutputIntentProfile", "PDF/X output intent profile", .standards, .string),
        option("PDFXRegistryName", "PDF/X registry", .standards, .string),
        option("PDFXTrapped", "PDF/X trapped state", .standards, .name(["True", "False", "Unknown"])),
        option("AbortPDFAX", "Abort nonconforming PDF/A or PDF/X jobs", .standards, .boolean)
    ]

    static let byKey = Dictionary(uniqueKeysWithValues: options.map { ($0.key, $0) })

    static func options(in category: DistillerCategory) -> [DistillerOptionDefinition] {
        options.filter { $0.category == category }
    }

    static func localizedChoice(_ choice: String) -> String {
        switch choice {
        case "AbsoluteColorimetric": String(localized: "AbsoluteColorimetric")
        case "All": String(localized: "All")
        case "Average": String(localized: "Average")
        case "Bicubic": String(localized: "Bicubic")
        case "CCITTFaxEncode": String(localized: "CCITTFaxEncode")
        case "CMYK": String(localized: "CMYK")
        case "DCTEncode": String(localized: "DCTEncode")
        case "Default": String(localized: "Default")
        case "DeviceCMYK": String(localized: "DeviceCMYK")
        case "DeviceGray": String(localized: "DeviceGray")
        case "DeviceRGB": String(localized: "DeviceRGB")
        case "Error": String(localized: "Error")
        case "False": String(localized: "False")
        case "FlateEncode": String(localized: "FlateEncode")
        case "Gray": String(localized: "Gray")
        case "Ignore": String(localized: "Ignore")
        case "JPXEncode": String(localized: "JPXEncode")
        case "LeaveColorUnchanged": String(localized: "LeaveColorUnchanged")
        case "Left": String(localized: "Left")
        case "None": String(localized: "None")
        case "Off": String(localized: "Off")
        case "PageByPage": String(localized: "PageByPage")
        case "Perceptual": String(localized: "Perceptual")
        case "Preserve": String(localized: "Preserve")
        case "RGB": String(localized: "RGB")
        case "RelativeColorimetric": String(localized: "RelativeColorimetric")
        case "Remove": String(localized: "Remove")
        case "Right": String(localized: "Right")
        case "RunLengthEncode": String(localized: "RunLengthEncode")
        case "Saturation": String(localized: "Saturation")
        case "sRGB": String(localized: "sRGB")
        case "Subsample": String(localized: "Subsample")
        case "Tags": String(localized: "Tags")
        case "True": String(localized: "True")
        case "Unknown": String(localized: "Unknown")
        case "UseDeviceIndependentColor": String(localized: "UseDeviceIndependentColor")
        case "Warning": String(localized: "Warning")
        default: choice
        }
    }

    private static func option(
        _ key: String,
        _ title: LocalizedStringResource,
        _ category: DistillerCategory,
        _ kind: DistillerOptionKind,
        compatibility: LocalizedStringResource? = nil
    ) -> DistillerOptionDefinition {
        DistillerOptionDefinition(
            key: key,
            title: title,
            category: category,
            kind: kind,
            help: "/\(key)",
            compatibilityNote: compatibility
        )
    }
}
