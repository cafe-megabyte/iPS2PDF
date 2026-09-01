import Foundation

enum DistillerOptionCatalog {
    static let ghostscriptVersion = "10.07.1"

    static let options: [DistillerOptionDefinition] = [
        option("Description", "Description", .general, .string, section: .description, semanticEditor: .description),
        option("CompatibilityLevel", "PDF compatibility", .general, .literal(["1.1", "1.2", "1.3", "1.4", "1.5", "1.6", "1.7", "2.0"]), disabledByStandard: true),
        option("CompressObjects", "Object compression", .general, .name(["Off", "Tags", "All"])),
        option("AutoRotatePages", "Auto-rotate pages", .general, .name(["None", "All", "PageByPage"])),
        option("Binding", "Binding", .general, .name(["Left", "Right"])),
        option("StartPage", "Pages", .general, .integer(1...999_999), section: .pageRange, keyPaths: ["/StartPage", "/EndPage"], semanticEditor: .pageRange),
        option("EndPage", "Last page", .general, .integer(-1...999_999), section: .pageRange, semanticEditor: .companion),
        option("Optimize", "Optimize for fast web view", .general, .boolean),
        option("DoThumbnails", "Embed page thumbnails", .general, .boolean),
        option("PreserveEPSInfo", "Preserve EPS information", .advanced, .boolean, section: .dsc),
        option("PreserveCopyPage", "Preserve copy-page semantics", .advanced, .boolean),
        option("UsePrologue", "Use prologue", .advanced, .boolean),
        option("HWResolution", "Device resolution", .general, .string, keyPaths: ["/HWResolution"], semanticEditor: .deviceResolution),
        option("PageSize", "Default page size", .general, .string, section: .pageSize, keyPaths: ["/PageSize"], semanticEditor: .pageSize),

        option("Encrypt", "Encrypt PDF", .general, .boolean, classification: .knownAdditional, disabledByStandard: true),
        option("EncryptionR", "Encryption revision", .general, .integer(0...6), classification: .knownAdditional, disabledByStandard: true),
        option("OwnerPassword", "Owner password", .general, .string, classification: .knownAdditional, disabledByStandard: true),
        option("UserPassword", "User password", .general, .string, classification: .knownAdditional, disabledByStandard: true),
        option("Permissions", "Document permissions", .general, .integer(-2_147_483_648...2_147_483_647), classification: .knownAdditional, disabledByStandard: true),

        option("DownsampleColorImages", "Downsampling", .images, .boolean, section: .colorImages, keyPaths: ["/DownsampleColorImages", "/ColorImageDownsampleType", "/ColorImageResolution", "/ColorImageDownsampleThreshold"], semanticEditor: .downsampling(.color)),
        option("ColorImageDownsampleType", "Color downsampling", .images, .name(["None", "Average", "Bicubic", "Subsample"]), section: .colorImages, semanticEditor: .companion),
        option("ColorImageResolution", "Color image resolution", .images, .integer(1...9_600), section: .colorImages, semanticEditor: .companion),
        option("ColorImageDownsampleThreshold", "Color downsample threshold", .images, .number(1...10), section: .colorImages, semanticEditor: .companion),
        option("ColorImageMinResolution", "Minimum color resolution", .images, .integer(1...9_600), section: .imagePolicies, keyPaths: ["/ColorImageMinResolution", "/ColorImageMinResolutionPolicy"], semanticEditor: .imagePolicy(.color)),
        option("ColorImageMinResolutionPolicy", "Low color resolution policy", .images, .name(["OK", "Warning", "Error"]), section: .imagePolicies, semanticEditor: .companion),
        option("ColorImageFilter", "Compression and image quality", .images, .name(["DCTEncode", "FlateEncode", "JPXEncode"]), section: .colorImages, keyPaths: ["/EncodeColorImages", "/AutoFilterColorImages", "/ColorImageFilter", "/ColorACSImageDict /QFactor", "/ColorImageDict /QFactor", "/JPEG2000ColorImageDict /Quality"], semanticEditor: .compression(.color)),
        option("AutoFilterColorImages", "Automatic color compression", .images, .boolean, section: .colorImages, semanticEditor: .companion),
        option("EncodeColorImages", "Compress color images", .images, .boolean, section: .colorImages, semanticEditor: .companion),
        option("AntiAliasColorImages", "Anti-alias color images", .images, .boolean, classification: .knownAdditional),
        option("CropColorImages", "Crop color images to frames", .images, .boolean),
        option("DownsampleGrayImages", "Downsampling", .images, .boolean, section: .grayscaleImages, keyPaths: ["/DownsampleGrayImages", "/GrayImageDownsampleType", "/GrayImageResolution", "/GrayImageDownsampleThreshold"], semanticEditor: .downsampling(.grayscale)),
        option("GrayImageDownsampleType", "Grayscale downsampling", .images, .name(["None", "Average", "Bicubic", "Subsample"]), section: .grayscaleImages, semanticEditor: .companion),
        option("GrayImageResolution", "Grayscale image resolution", .images, .integer(1...9_600), section: .grayscaleImages, semanticEditor: .companion),
        option("GrayImageDownsampleThreshold", "Grayscale downsample threshold", .images, .number(1...10), section: .grayscaleImages, semanticEditor: .companion),
        option("GrayImageMinResolution", "Minimum grayscale resolution", .images, .integer(1...9_600), section: .imagePolicies, keyPaths: ["/GrayImageMinResolution", "/GrayImageMinResolutionPolicy"], semanticEditor: .imagePolicy(.grayscale)),
        option("GrayImageMinResolutionPolicy", "Low grayscale resolution policy", .images, .name(["OK", "Warning", "Error"]), section: .imagePolicies, semanticEditor: .companion),
        option("GrayImageFilter", "Compression and image quality", .images, .name(["DCTEncode", "FlateEncode", "JPXEncode"]), section: .grayscaleImages, keyPaths: ["/EncodeGrayImages", "/AutoFilterGrayImages", "/GrayImageFilter", "/GrayACSImageDict /QFactor", "/GrayImageDict /QFactor", "/JPEG2000GrayImageDict /Quality"], semanticEditor: .compression(.grayscale)),
        option("AutoFilterGrayImages", "Automatic grayscale compression", .images, .boolean, section: .grayscaleImages, semanticEditor: .companion),
        option("EncodeGrayImages", "Compress grayscale images", .images, .boolean, section: .grayscaleImages, semanticEditor: .companion),
        option("AntiAliasGrayImages", "Anti-alias grayscale images", .images, .boolean, classification: .knownAdditional),
        option("CropGrayImages", "Crop grayscale images to frames", .images, .boolean, section: .grayscaleImages),
        option("DownsampleMonoImages", "Downsampling", .images, .boolean, section: .monochromeImages, keyPaths: ["/DownsampleMonoImages", "/MonoImageDownsampleType", "/MonoImageResolution", "/MonoImageDownsampleThreshold"], semanticEditor: .downsampling(.monochrome)),
        option("MonoImageDownsampleType", "Monochrome downsampling", .images, .name(["None", "Average", "Bicubic", "Subsample"]), section: .monochromeImages, semanticEditor: .companion),
        option("MonoImageResolution", "Monochrome image resolution", .images, .integer(1...9_600), section: .monochromeImages, semanticEditor: .companion),
        option("MonoImageDownsampleThreshold", "Monochrome downsample threshold", .images, .number(1...10), section: .monochromeImages, semanticEditor: .companion),
        option("MonoImageMinResolution", "Minimum monochrome resolution", .images, .integer(1...9_600), section: .imagePolicies, keyPaths: ["/MonoImageMinResolution", "/MonoImageMinResolutionPolicy"], semanticEditor: .imagePolicy(.monochrome)),
        option("MonoImageMinResolutionPolicy", "Low monochrome resolution policy", .images, .name(["OK", "Warning", "Error"]), section: .imagePolicies, semanticEditor: .companion),
        option("MonoImageFilter", "Compression", .images, .name(["CCITTFaxEncode", "FlateEncode", "RunLengthEncode"]), section: .monochromeImages, keyPaths: ["/EncodeMonoImages", "/MonoImageFilter"], semanticEditor: .compression(.monochrome)),
        option("EncodeMonoImages", "Compress monochrome images", .images, .boolean, section: .monochromeImages, semanticEditor: .companion),
        option("AntiAliasMonoImages", "Smooth monochrome images", .images, .boolean, section: .monochromeImages, keyPaths: ["/AntiAliasMonoImages", "/MonoImageDepth"], semanticEditor: .monoSmoothing),
        option("MonoImageDepth", "Monochrome image depth", .images, .integer(-1...8), section: .monochromeImages, semanticEditor: .companion),
        option("CropMonoImages", "Crop monochrome images to frames", .images, .boolean, section: .monochromeImages),
        option("Downsample16BitImages", "Downsample 16-bit images", .images, .boolean, classification: .knownAdditional),
        option("PassThroughJPEGImages", "Pass through JPEG images", .advanced, .boolean),
        option("PassThroughJPXImages", "Pass through JPEG 2000 images", .images, .boolean, classification: .knownAdditional),
        option("ConvertImagesToIndexed", "Convert suitable images to indexed color", .images, .boolean, classification: .knownAdditional),

        option("EmbedAllFonts", "Embed all fonts", .fonts, .boolean, disabledByStandard: true),
        option("EmbedSubstituteFonts", "Embed substitute fonts", .fonts, .boolean),
        option("SubsetFonts", "Subset embedded fonts", .fonts, .boolean),
        option("MaxSubsetPct", "Subset fonts below", .fonts, .integer(1...100), classification: .knownAdditional),
        option("EmbedOpenType", "Embed OpenType fonts", .fonts, .boolean),
        option("CannotEmbedFontPolicy", "When embedding fails", .fonts, .name(["Ignore", "Warning", "Error"]), classification: .knownAdditional, disabledByStandard: true),

        option("ColorSettingsFile", "Color settings file", .color, .string, section: .colorSettings, classification: .preserved),
        option("ColorConversionStrategy", "Color conversion strategy", .color, .name(["LeaveColorUnchanged", "RGB", "sRGB", "CMYK", "Gray", "UseDeviceIndependentColor"]), disabledByStandard: true),
        option("BlendConversionStrategy", "Blend conversion strategy", .color, .name(["None", "Simple", "Managed"]), classification: .knownAdditional),
        option("ConvertCMYKImagesToRGB", "Convert CMYK images to RGB", .color, .boolean, classification: .knownAdditional),
        option("ProcessColorModel", "Process color model", .color, .name(["DeviceGray", "DeviceRGB", "DeviceCMYK"]), classification: .knownAdditional),
        option("DefaultRenderingIntent", "Default rendering intent", .color, .name(["Default", "Perceptual", "RelativeColorimetric", "Saturation", "AbsoluteColorimetric"])),
        option("PreserveDICMYKValues", "Preserve CMYK values for calibrated CMYK color spaces", .color, .boolean, section: .workingSpaces),
        option("PreserveOverprintSettings", "Preserve overprint settings", .advanced, .boolean),
        option("PreserveBlack", "Preserve black", .color, .boolean, classification: .knownAdditional),
        option("PreserveDeviceN", "Preserve DeviceN colorants", .color, .boolean, classification: .knownAdditional),
        option("PreserveSeparation", "Preserve separations", .color, .boolean, classification: .knownAdditional),
        option("ParseICCProfilesInComments", "Honor ICC profiles in comments", .color, .boolean, classification: .knownAdditional),
        option("CalGrayProfile", "Working grayscale profile", .color, .string),
        option("CalRGBProfile", "Working RGB profile", .color, .string),
        option("CalCMYKProfile", "Working CMYK profile", .color, .string),
        option("sRGBProfile", "sRGB profile", .color, .string, classification: .knownAdditional),
        option("OutputICCProfile", "Output ICC profile", .color, .string, classification: .knownAdditional),
        option("GraphicICCProfile", "Graphics ICC profile", .color, .string, classification: .knownAdditional),
        option("ImageICCProfile", "Image ICC profile", .color, .string, classification: .knownAdditional),
        option("TextICCProfile", "Text ICC profile", .color, .string, classification: .knownAdditional),
        option("DeviceGrayToK", "Map device gray to black", .color, .boolean, classification: .knownAdditional),
        option("UCRandBGInfo", "Preserve undercolor removal and black generation", .color, .name(["Preserve", "Apply", "Remove"]), section: .deviceDependentColor),
        option("TransferFunctionInfo", "For transfer functions", .color, .name(["Preserve", "Apply", "Remove"]), section: .deviceDependentColor),
        option("PreserveHalftoneInfo", "Preserve halftone information", .color, .boolean, section: .deviceDependentColor),

        option("ASCII85EncodePages", "ASCII85-encode page streams", .advanced, .boolean, classification: .knownAdditional),
        option("CompressPages", "Compress page streams", .advanced, .boolean, classification: .knownAdditional),
        option("CompressStreams", "Compress object streams", .advanced, .boolean, classification: .knownAdditional),
        option("WriteXRefStm", "Write cross-reference streams", .advanced, .boolean, classification: .knownAdditional),
        option("WriteObjStms", "Write object streams", .advanced, .boolean, classification: .knownAdditional),
        option("DetectBlends", "Detect blends", .advanced, .boolean),
        option("DetectCurves", "Curve detection tolerance", .advanced, .number(0...10)),
        option("PreserveFlatness", "Preserve flatness", .advanced, .boolean),
        option("PreserveOPIComments", "Preserve OPI comments", .advanced, .boolean, section: .dsc),
        option("ParseDSCComments", "Process DSC comments", .advanced, .boolean, section: .dsc),
        option("ParseDSCCommentsForDocInfo", "Use DSC comments for document info", .advanced, .boolean, section: .dsc),
        option("EmitDSCWarnings", "Report DSC warnings", .advanced, .boolean, section: .dsc),
        option("DSCReportingLevel", "DSC reporting level", .advanced, .integer(0...2), classification: .knownAdditional),
        option("OPM", "Overprint mode", .advanced, .integer(0...1)),
        option("LockDistillerParams", "Allow PostScript files to override PDF settings", .advanced, .boolean, keyPaths: ["/LockDistillerParams"], semanticEditor: .distillerOverrides),
        option("AllowPSXObjects", "Allow PostScript XObjects", .advanced, .boolean),
        option("AutoPositionEPSFiles", "Auto-position EPS files", .advanced, .boolean, section: .dsc),
        option("AllowTransparency", "Allow transparency operators", .advanced, .boolean, classification: .knownAdditional),
        option("HaveTransparency", "Enable transparency device", .advanced, .boolean, classification: .knownAdditional),
        option("CreateJobTicket", "Create job ticket", .advanced, .boolean, compatibility: "Preserved; ignored by Ghostscript"),
        option("EmbedJobOptions", "Embed Joboptions", .advanced, .boolean, compatibility: "Preserved; not interpreted by Ghostscript pdfwrite"),

        option(
            "iPS2PDFEmbedOutputIntentProfile",
            "Embed output intent profile",
            .additional,
            .boolean,
            section: .application,
            classification: .preserved
        ),

        option("iPS2PDFStandard", "PDF standard", .standards, .name(PDFStandard.allCases.map(\.rawValue)), section: .conformance, semanticEditor: .standard),
        option("PDFACompatibilityPolicy", "PDF/A compatibility policy", .standards, .integer(0...2)),
        option("PDFX1aCheck", "Check PDF/X-1", .standards, .boolean),
        option("PDFX3Check", "Check PDF/X-3", .standards, .boolean),
        option("PDFXOutputCondition", "PDF/X output condition", .standards, .string, section: .outputIntent),
        option("PDFXOutputConditionIdentifier", "PDF/X condition identifier", .standards, .string, section: .outputIntent),
        option("PDFXOutputIntentProfile", "PDF/X output intent profile", .standards, .string, section: .outputIntent),
        option("PDFXRegistryName", "PDF/X registry", .standards, .string, section: .outputIntent),
        option("PDFXTrapped", "PDF/X trapped state", .standards, .name(["True", "False", "Unknown"]), section: .outputIntent),
        option("AbortPDFAX", "Abort nonconforming PDF/A or PDF/X jobs", .standards, .boolean),
        option("PDFXNoTrimBoxError", "Missing trim box behavior", .standards, .boolean, section: .pageBoxes, keyPaths: ["/PDFXNoTrimBoxError", "/PDFXTrimBoxToMediaBoxOffset", "/PDFXSetBleedBoxToMediaBox", "/PDFXBleedBoxToTrimBoxOffset"], semanticEditor: .pdfXBoxes),
        option("PDFXTrimBoxToMediaBoxOffset", "Trim box offsets", .standards, .string, section: .pageBoxes, semanticEditor: .companion),
        option("PDFXSetBleedBoxToMediaBox", "Set bleed box to media box", .standards, .boolean, section: .pageBoxes, semanticEditor: .companion),
        option("PDFXBleedBoxToTrimBoxOffset", "Bleed box offsets", .standards, .string, section: .pageBoxes, semanticEditor: .companion)
    ]

    static let byKey = Dictionary(uniqueKeysWithValues: options.map { ($0.key, $0) })

    static func options(in category: DistillerCategory) -> [DistillerOptionDefinition] {
        options.filter { $0.category == category }
    }

    static func localizedChoice(_ choice: String) -> String {
        switch choice {
        case "AbsoluteColorimetric": String(localized: "AbsoluteColorimetric")
        case "All": String(localized: "All")
        case "Apply": String(localized: "Apply")
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
        section: DistillerSection? = nil,
        keyPaths: [String] = [],
        semanticEditor: DistillerSemanticEditor = .scalar,
        classification: DistillerControlClassification = .distillerControl,
        disabledByStandard: Bool = false,
        compatibility: LocalizedStringResource? = nil
    ) -> DistillerOptionDefinition {
        DistillerOptionDefinition(
            key: key,
            title: title,
            category: category,
            section: section ?? defaultSection(for: category),
            kind: kind,
            keyPaths: (keyPaths.isEmpty ? ["/\(key)"] : keyPaths).map { JoboptionsKeyPath($0) },
            semanticEditor: semanticEditor,
            classification: classification,
            isDisabledBySelectedStandard: disabledByStandard,
            compatibilityNote: compatibility
        )
    }

    private static func defaultSection(for category: DistillerCategory) -> DistillerSection {
        switch category {
        case .general: .fileOptions
        case .images: .colorImages
        case .fonts: .fontEmbedding
        case .color: .colorManagement
        case .advanced: .advancedOptions
        case .standards: .conformance
        case .additional: .preserved
        }
    }
}
