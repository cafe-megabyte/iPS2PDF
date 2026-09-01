import Foundation

struct SemanticJoboptions: Sendable {
    static let defaultPDFXOutputIntentProfile = "Generic CMYK Profile"
    static let embedOutputIntentProfileKey = "iPS2PDFEmbedOutputIntentProfile"

    struct DeviceResolution: Equatable, Sendable {
        let x: Double
        let y: Double
    }

    struct PageSize: Equatable, Sendable {
        let widthInPoints: Double
        let heightInPoints: Double
    }

    enum PageSelection: Equatable, Sendable {
        case all
        case range(start: Int, end: Int)
        case custom(start: JoboptionsValue?, end: JoboptionsValue?)
    }

    enum MeasurementUnit: String, CaseIterable, Sendable {
        case points
        case inches
        case millimeters

        var pointsPerUnit: Double {
            switch self {
            case .points: 1
            case .inches: 72
            case .millimeters: 72 / 25.4
            }
        }
    }

    enum ImageKind: String, CaseIterable, Equatable, Sendable {
        case color = "Color"
        case grayscale = "Gray"
        case monochrome = "Mono"
    }

    enum DownsamplingMode: String, CaseIterable, Sendable {
        case average = "Average"
        case bicubic = "Bicubic"
        case subsample = "Subsample"
    }

    enum DownsamplingConfiguration: Equatable, Sendable {
        case off
        case configured(mode: DownsamplingMode, resolution: Int, threshold: Double)
        case custom
    }

    enum ImageCompression: Equatable, Sendable {
        case automaticJPEG
        case jpeg
        case flate
        case jpeg2000
        case ccittGroup4
        case runLength
        case off
        case custom(encode: JoboptionsValue?, automatic: JoboptionsValue?, filter: JoboptionsValue?)
    }

    enum ImageQuality: Equatable, Sendable {
        case minimum
        case low
        case medium
        case high
        case maximum
        case custom(Double?)

        var qFactor: Double? {
            switch self {
            case .maximum: 0.15
            case .high: 0.40
            case .medium: 0.76
            case .low: 1.30
            case .minimum: 2.00
            case let .custom(value): value
            }
        }
    }

    struct ImageCompressionConfiguration: Equatable, Sendable {
        let compression: ImageCompression
        let quality: ImageQuality?
    }

    enum ImagePolicy: String, CaseIterable, Sendable {
        case ignore = "OK"
        case warn = "Warning"
        case error = "Error"
    }

    struct ImagePolicyConfiguration: Equatable, Sendable {
        let minimumResolution: Int?
        let policy: ImagePolicy?
    }

    enum MonoSmoothingConfiguration: Equatable, Sendable {
        case off
        case depth(Int)
        case custom
    }

    enum PDFXBoxRule: Equatable, Sendable {
        case error
        case mediaBox(offsets: [Double])
        case trimBox(offsets: [Double])
        case custom
    }

    struct PDFXBoxRules: Equatable, Sendable {
        let trim: PDFXBoxRule
        let bleed: PDFXBoxRule
    }

    static func description(
        in document: LosslessJoboptionsDocument,
        languageCode: String = Locale.current.language.languageCode?.identifier ?? "en"
    ) -> String? {
        if case .dictionary = document.value(forKey: "Description") {
            return document.value(forPath: descriptionPath(languageCode: languageCode))?.textualValue
        }
        return document.value(forKey: "Description")?.textualValue
    }

    static func changeDescription(
        to value: String,
        in document: LosslessJoboptionsDocument,
        languageCode: String = Locale.current.language.languageCode?.identifier ?? "en"
    ) -> JoboptionsChangeSet {
        if case .dictionary = document.value(forKey: "Description") {
            return JoboptionsChangeSet([
                JoboptionsChange(
                    descriptionPath(languageCode: languageCode),
                    .string(value),
                    stringInsertionStyle: .adobeUnicodeHex
                )
            ])
        }
        return JoboptionsChangeSet([JoboptionsChange("/Description", .string(value))])
    }

    static func pageSelection(in document: LosslessJoboptionsDocument) -> PageSelection {
        let start = document.value(forKey: "StartPage")
        let end = document.value(forKey: "EndPage")
        if start?.numberValue == 1, end?.numberValue == -1 { return .all }
        if let startValue = start?.numberValue,
           let endValue = end?.numberValue,
           startValue.rounded() == startValue,
           endValue.rounded() == endValue,
           startValue >= 1,
           endValue >= startValue {
            return .range(start: Int(startValue), end: Int(endValue))
        }
        return .custom(start: start, end: end)
    }

    static func changePageSelection(_ selection: PageSelection) -> JoboptionsChangeSet {
        switch selection {
        case .all:
            JoboptionsChangeSet([
                integerChange("/StartPage", 1),
                integerChange("/EndPage", -1)
            ])
        case let .range(start, end):
            JoboptionsChangeSet([
                integerChange("/StartPage", max(1, start)),
                integerChange("/EndPage", max(max(1, start), end))
            ])
        case .custom:
            JoboptionsChangeSet([])
        }
    }

    static func deviceResolution(in document: LosslessJoboptionsDocument) -> DeviceResolution? {
        guard let values = numericArray(document.value(forKey: "HWResolution")), values.count == 2 else {
            return nil
        }
        return DeviceResolution(x: values[0], y: values[1])
    }

    static func changeDeviceResolution(x: Int, y: Int) -> JoboptionsChangeSet {
        JoboptionsChangeSet([
            JoboptionsChange("/HWResolution", .array([number(x), number(y)]))
        ])
    }

    static func pageSize(in document: LosslessJoboptionsDocument) -> PageSize? {
        guard let values = numericArray(document.value(forKey: "PageSize")), values.count == 2 else {
            return nil
        }
        return PageSize(widthInPoints: values[0], heightInPoints: values[1])
    }

    static func changePageSize(
        width: Double,
        height: Double,
        unit: MeasurementUnit
    ) -> JoboptionsChangeSet {
        JoboptionsChangeSet([
            JoboptionsChange(
                "/PageSize",
                .array([
                    decimal(width * unit.pointsPerUnit),
                    decimal(height * unit.pointsPerUnit)
                ])
            )
        ])
    }

    static func downsampling(
        in document: LosslessJoboptionsDocument,
        kind: ImageKind
    ) -> DownsamplingConfiguration {
        let prefix = kind.rawValue
        if document.value(forKey: "Downsample\(prefix)Images")?.boolValue == false {
            return .off
        }
        guard document.value(forKey: "Downsample\(prefix)Images")?.boolValue == true,
              let rawMode = document.value(forKey: "\(prefix)ImageDownsampleType")?.textualValue,
              let mode = DownsamplingMode(rawValue: rawMode),
              let resolutionValue = document.value(forKey: "\(prefix)ImageResolution")?.numberValue,
              resolutionValue.rounded() == resolutionValue,
              let threshold = document.value(forKey: "\(prefix)ImageDownsampleThreshold")?.numberValue
        else { return .custom }
        return .configured(mode: mode, resolution: Int(resolutionValue), threshold: threshold)
    }

    static func changeDownsampling(
        kind: ImageKind,
        enabled: Bool,
        mode: DownsamplingMode,
        resolution: Int,
        threshold: Double
    ) -> JoboptionsChangeSet {
        let prefix = kind.rawValue
        guard enabled else {
            return JoboptionsChangeSet([
                JoboptionsChange("/Downsample\(prefix)Images", .boolean(false))
            ])
        }
        return JoboptionsChangeSet([
            JoboptionsChange("/Downsample\(prefix)Images", .boolean(true)),
            JoboptionsChange("/\(prefix)ImageDownsampleType", .name(mode.rawValue)),
            integerChange("/\(prefix)ImageResolution", max(1, resolution)),
            JoboptionsChange("/\(prefix)ImageDownsampleThreshold", decimal(max(1, threshold)))
        ])
    }

    static func changeCompression(
        kind: ImageKind,
        compression: ImageCompression,
        quality: ImageQuality? = nil
    ) -> JoboptionsChangeSet {
        let prefix = kind.rawValue
        var changes: [JoboptionsChange]
        switch compression {
        case .automaticJPEG:
            changes = [
                JoboptionsChange("/Encode\(prefix)Images", .boolean(true)),
                JoboptionsChange("/AutoFilter\(prefix)Images", .boolean(true)),
                JoboptionsChange("/\(prefix)ImageFilter", .name("DCTEncode"))
            ]
        case .jpeg:
            changes = [
                JoboptionsChange("/Encode\(prefix)Images", .boolean(true)),
                JoboptionsChange("/AutoFilter\(prefix)Images", .boolean(false)),
                JoboptionsChange("/\(prefix)ImageFilter", .name("DCTEncode"))
            ]
        case .flate:
            changes = [
                JoboptionsChange("/Encode\(prefix)Images", .boolean(true)),
                JoboptionsChange("/AutoFilter\(prefix)Images", .boolean(false)),
                JoboptionsChange("/\(prefix)ImageFilter", .name("FlateEncode"))
            ]
        case .jpeg2000:
            changes = [
                JoboptionsChange("/Encode\(prefix)Images", .boolean(true)),
                JoboptionsChange("/AutoFilter\(prefix)Images", .boolean(false)),
                JoboptionsChange("/\(prefix)ImageFilter", .name("JPXEncode"))
            ]
        case .ccittGroup4:
            changes = [
                JoboptionsChange("/Encode\(prefix)Images", .boolean(true)),
                JoboptionsChange("/\(prefix)ImageFilter", .name("CCITTFaxEncode"))
            ]
        case .runLength:
            changes = [
                JoboptionsChange("/Encode\(prefix)Images", .boolean(true)),
                JoboptionsChange("/\(prefix)ImageFilter", .name("RunLengthEncode"))
            ]
        case .off:
            changes = [JoboptionsChange("/Encode\(prefix)Images", .boolean(false))]
        case .custom:
            return JoboptionsChangeSet([])
        }

        if kind != .monochrome, let qFactor = quality?.qFactor {
            let path = compression == .automaticJPEG
                ? "/\(prefix)ACSImageDict /QFactor"
                : "/\(prefix)ImageDict /QFactor"
            changes.append(JoboptionsChange(path, decimal(qFactor)))
        }
        return JoboptionsChangeSet(changes)
    }

    static func imageCompression(
        in document: LosslessJoboptionsDocument,
        kind: ImageKind
    ) -> ImageCompressionConfiguration {
        let prefix = kind.rawValue
        let encode = document.value(forKey: "Encode\(prefix)Images")
        let automatic = document.value(forKey: "AutoFilter\(prefix)Images")
        let filter = document.value(forKey: "\(prefix)ImageFilter")
        let compression: ImageCompression
        if encode?.boolValue == false {
            compression = .off
        } else {
            switch filter?.textualValue {
            case "DCTEncode" where automatic?.boolValue == true: compression = .automaticJPEG
            case "DCTEncode": compression = .jpeg
            case "FlateEncode": compression = .flate
            case "JPXEncode": compression = .jpeg2000
            case "CCITTFaxEncode": compression = .ccittGroup4
            case "RunLengthEncode": compression = .runLength
            default: compression = .custom(encode: encode, automatic: automatic, filter: filter)
            }
        }
        let qFactor: Double?
        switch compression {
        case .automaticJPEG:
            qFactor = document.value(forPath: "/\(prefix)ACSImageDict /QFactor")?.numberValue
        case .jpeg:
            qFactor = document.value(forPath: "/\(prefix)ImageDict /QFactor")?.numberValue
        case .jpeg2000:
            qFactor = document.value(forPath: "/JPEG2000\(prefix)ImageDict /Quality")?.numberValue
        default:
            qFactor = nil
        }
        return ImageCompressionConfiguration(
            compression: compression,
            quality: imageQuality(qFactor)
        )
    }

    static func imagePolicy(
        in document: LosslessJoboptionsDocument,
        kind: ImageKind
    ) -> ImagePolicyConfiguration {
        let prefix = kind.rawValue
        let rawMinimum = document.value(forKey: "\(prefix)ImageMinResolution")?.numberValue
        let minimum = rawMinimum.flatMap { value in
            value.rounded() == value ? Int(value) : nil
        }
        let rawPolicy = document.value(forKey: "\(prefix)ImageMinResolutionPolicy")?.textualValue
        return ImagePolicyConfiguration(
            minimumResolution: minimum,
            policy: rawPolicy.flatMap(ImagePolicy.init(rawValue:))
        )
    }

    static func changeImagePolicy(
        kind: ImageKind,
        minimumResolution: Int,
        policy: ImagePolicy
    ) -> JoboptionsChangeSet {
        let prefix = kind.rawValue
        return JoboptionsChangeSet([
            integerChange("/\(prefix)ImageMinResolution", max(1, minimumResolution)),
            JoboptionsChange("/\(prefix)ImageMinResolutionPolicy", .name(policy.rawValue))
        ])
    }

    static func monoSmoothing(in document: LosslessJoboptionsDocument) -> MonoSmoothingConfiguration {
        let enabled = document.value(forKey: "AntiAliasMonoImages")?.boolValue
        if enabled == false { return .off }
        guard enabled == true,
              let value = document.value(forKey: "MonoImageDepth")?.numberValue,
              value.rounded() == value,
              [2, 4, 8].contains(Int(value))
        else { return .custom }
        return .depth(Int(value))
    }

    static func changeMonoSmoothing(_ value: MonoSmoothingConfiguration) -> JoboptionsChangeSet {
        switch value {
        case .off:
            JoboptionsChangeSet([JoboptionsChange("/AntiAliasMonoImages", .boolean(false))])
        case let .depth(depth) where [2, 4, 8].contains(depth):
            JoboptionsChangeSet([
                JoboptionsChange("/AntiAliasMonoImages", .boolean(true)),
                integerChange("/MonoImageDepth", depth)
            ])
        case .depth, .custom:
            JoboptionsChangeSet([])
        }
    }

    static func allowsDistillerOverrides(in document: LosslessJoboptionsDocument) -> Bool {
        document.value(forKey: "LockDistillerParams")?.boolValue != true
    }

    static func changeAllowsDistillerOverrides(_ allowsOverrides: Bool) -> JoboptionsChangeSet {
        JoboptionsChangeSet([
            JoboptionsChange("/LockDistillerParams", .boolean(!allowsOverrides))
        ])
    }

    static func changeStandard(_ standard: PDFStandard) -> JoboptionsChangeSet {
        JoboptionsChangeSet([
            JoboptionsChange("/iPS2PDFStandard", .name(standard.rawValue))
        ])
    }

    static func changeStandard(
        _ standard: PDFStandard,
        in document: LosslessJoboptionsDocument
    ) -> JoboptionsChangeSet {
        var changes = [JoboptionsChange("/iPS2PDFStandard", .name(standard.rawValue))]
        if standard.isPDFX, needsDefaultPDFXOutputIntentProfile(in: document) {
            changes.append(JoboptionsChange(
                "/PDFXOutputIntentProfile",
                .string(defaultPDFXOutputIntentProfile)
            ))
        }
        return JoboptionsChangeSet(changes)
    }

    static func embedsOutputIntentProfile(in document: LosslessJoboptionsDocument) -> Bool {
        document.value(forKey: embedOutputIntentProfileKey)?.boolValue == true
    }

    static func changeEmbedsOutputIntentProfile(_ embeds: Bool) -> JoboptionsChangeSet {
        JoboptionsChangeSet([
            JoboptionsChange("/\(embedOutputIntentProfileKey)", .boolean(embeds))
        ])
    }

    static func needsDefaultPDFXOutputIntentProfile(
        in document: LosslessJoboptionsDocument
    ) -> Bool {
        guard let value = document.value(forKey: "PDFXOutputIntentProfile")?.textualValue else {
            return true
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.caseInsensitiveCompare("None") == .orderedSame
    }

    static func changePDFXBoxRules(
        trim: PDFXBoxRule,
        bleed: PDFXBoxRule
    ) -> JoboptionsChangeSet {
        var changes: [JoboptionsChange] = []
        switch trim {
        case .error:
            changes.append(JoboptionsChange("/PDFXNoTrimBoxError", .boolean(true)))
        case let .mediaBox(offsets):
            changes.append(JoboptionsChange("/PDFXNoTrimBoxError", .boolean(false)))
            changes.append(JoboptionsChange("/PDFXTrimBoxToMediaBoxOffset", offsetArray(offsets)))
        case .trimBox, .custom:
            break
        }
        switch bleed {
        case .error:
            break
        case .mediaBox:
            changes.append(JoboptionsChange("/PDFXSetBleedBoxToMediaBox", .boolean(true)))
        case let .trimBox(offsets):
            changes.append(JoboptionsChange("/PDFXSetBleedBoxToMediaBox", .boolean(false)))
            changes.append(JoboptionsChange("/PDFXBleedBoxToTrimBoxOffset", offsetArray(offsets)))
        case .custom:
            break
        }
        return JoboptionsChangeSet(changes)
    }

    static func pdfXBoxRules(in document: LosslessJoboptionsDocument) -> PDFXBoxRules {
        let trim: PDFXBoxRule
        if document.value(forKey: "PDFXNoTrimBoxError")?.boolValue == true {
            trim = .error
        } else if let offsets = numericArray(document.value(forKey: "PDFXTrimBoxToMediaBoxOffset")),
                  offsets.count == 4 {
            trim = .mediaBox(offsets: offsets)
        } else {
            trim = .custom
        }

        let bleed: PDFXBoxRule
        if document.value(forKey: "PDFXSetBleedBoxToMediaBox")?.boolValue == true {
            bleed = .mediaBox(offsets: [0, 0, 0, 0])
        } else if let offsets = numericArray(document.value(forKey: "PDFXBleedBoxToTrimBoxOffset")),
                  offsets.count == 4 {
            bleed = .trimBox(offsets: offsets)
        } else {
            bleed = .custom
        }
        return PDFXBoxRules(trim: trim, bleed: bleed)
    }

    private static func descriptionPath(languageCode: String) -> String {
        languageCode.lowercased().hasPrefix("de") ? "/Description /DEU" : "/Description /ENU"
    }

    private static func number(_ value: Int) -> JoboptionsValue {
        .number(Double(value), original: String(value))
    }

    private static func decimal(_ value: Double) -> JoboptionsValue {
        .number(value, original: String(format: "%.5g", value))
    }

    private static func integerChange(_ path: String, _ value: Int) -> JoboptionsChange {
        JoboptionsChange(path, number(value))
    }

    private static func offsetArray(_ values: [Double]) -> JoboptionsValue {
        let padded = Array((values + [0, 0, 0, 0]).prefix(4))
        return .array(padded.map(decimal))
    }

    private static func numericArray(_ value: JoboptionsValue?) -> [Double]? {
        guard case let .array(values) = value else { return nil }
        let numbers = values.compactMap(\.numberValue)
        return numbers.count == values.count ? numbers : nil
    }

    private static func imageQuality(_ value: Double?) -> ImageQuality? {
        guard let value else { return nil }
        return switch value {
        case 0.15: .maximum
        case 0.40: .high
        case 0.76: .medium
        case 1.30: .low
        case 2.00: .minimum
        default: .custom(value)
        }
    }
}
