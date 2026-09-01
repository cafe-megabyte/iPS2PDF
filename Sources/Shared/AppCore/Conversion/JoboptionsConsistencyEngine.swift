import Foundation

enum JoboptionsConsistencyEngine {
    static func issues(
        in document: LosslessJoboptionsDocument,
        context: JoboptionsConsistencyContext = .empty
    ) -> [JoboptionsConsistencyIssue] {
        var evaluator = Evaluator(document: document, context: context)
        evaluator.evaluateStandardRules()
        evaluator.evaluateOutputIntentEmbeddingRules()
        evaluator.evaluateCompatibilityRules()
        evaluator.evaluateCompoundSettingRules()
        return evaluator.issues
    }

    static func effectiveDocument(
        from document: LosslessJoboptionsDocument,
        context: JoboptionsConsistencyContext = .empty
    ) throws -> LosslessJoboptionsDocument {
        try repair(document, applying: issues(in: document, context: context))
    }

    static func repair(
        _ document: LosslessJoboptionsDocument,
        applying issues: [JoboptionsConsistencyIssue]
    ) throws -> LosslessJoboptionsDocument {
        let changes = issues.map { issue in
            JoboptionsChange(issue.path.description, issue.proposedValue)
        }
        return try JoboptionsChangeSet(changes).applying(to: document)
    }

    static func adjustedDocument(from document: LosslessJoboptionsDocument) throws -> LosslessJoboptionsDocument {
        try effectiveDocument(from: document)
    }

    static func adjustedData(from data: Data) throws -> Data {
        try effectiveDocument(from: LosslessJoboptionsDocument(data: data)).data
    }

    private struct Evaluator {
        let context: JoboptionsConsistencyContext
        let original: LosslessJoboptionsDocument
        var working: LosslessJoboptionsDocument
        var issues: [JoboptionsConsistencyIssue] = []
        var proposalsByPath: [JoboptionsKeyPath: JoboptionsValue] = [:]

        init(document: LosslessJoboptionsDocument, context: JoboptionsConsistencyContext) {
            original = document
            working = document
            self.context = context
        }

        mutating func evaluateStandardRules() {
            guard let raw = working.value(forKey: "iPS2PDFStandard")?.textualValue,
                  let standard = PDFStandard(rawValue: raw),
                  standard != .none
            else { return }

            if let compatibility = standard.requiredCompatibilityLevel {
                propose(
                    path: "/CompatibilityLevel",
                    value: .number(Double(compatibility) ?? 1.7, original: compatibility),
                    reason: .standardPDFVersion,
                    rule: "standard.compatibility"
                )
            }
            propose(
                path: "/EmbedAllFonts",
                value: .boolean(true),
                reason: .standardFontEmbedding,
                rule: "standard.fonts.embed-all"
            )
            propose(
                path: "/CannotEmbedFontPolicy",
                value: .name("Error"),
                reason: .standardFontFailure,
                rule: "standard.fonts.failure"
            )
            propose(
                path: "/Encrypt",
                value: .boolean(false),
                reason: .standardEncryption,
                rule: "standard.encryption.enabled"
            )
            propose(
                path: "/EncryptionR",
                value: .number(0, original: "0"),
                reason: .standardEncryption,
                rule: "standard.encryption.revision"
            )
            propose(
                path: "/OwnerPassword",
                value: .string(""),
                reason: .standardEncryption,
                rule: "standard.encryption.owner-password"
            )
            propose(
                path: "/UserPassword",
                value: .string(""),
                reason: .standardEncryption,
                rule: "standard.encryption.user-password"
            )
            propose(
                path: "/Permissions",
                value: .number(-4, original: "-4"),
                reason: .standardPermissions,
                rule: "standard.permissions"
            )
            propose(
                path: "/PDFX1aCheck",
                value: .boolean(standard == .pdfx1),
                reason: .standardPDFXChecks,
                rule: "standard.pdfx1-check"
            )
            propose(
                path: "/PDFX3Check",
                value: .boolean(standard == .pdfx3),
                reason: .standardPDFXChecks,
                rule: "standard.pdfx3-check"
            )

            if standard.ghostscriptPDFAValue != nil {
                propose(
                    path: "/ColorConversionStrategy",
                    value: .name("RGB"),
                    reason: .standardColorConversion,
                    rule: "standard.pdfa.color"
                )
                if standard == .pdfa1b {
                    propose(
                        path: "/AllowTransparency",
                        value: .boolean(false),
                        reason: .standardTransparency,
                        rule: "standard.pdfa1.transparency"
                    )
                }
                evaluatePDFAProfile()
            } else if standard.ghostscriptPDFXValue != nil {
                let strategy = standard == .pdfx1 ? "CMYK" : "UseDeviceIndependentColor"
                propose(
                    path: "/ColorConversionStrategy",
                    value: .name(strategy),
                    reason: .standardColorConversion,
                    rule: "standard.pdfx.color"
                )
                if standard == .pdfx1 || standard == .pdfx3 {
                    propose(
                        path: "/AllowTransparency",
                        value: .boolean(false),
                        reason: .standardTransparency,
                        rule: "standard.pdfx.transparency"
                    )
                }
                evaluatePDFXProfile()
                evaluatePDFXOutputIntentMetadata()
            }
        }

        mutating func evaluateOutputIntentEmbeddingRules() {
            let rawStandard = working.value(forKey: "iPS2PDFStandard")?.textualValue
            let standard = rawStandard.flatMap(PDFStandard.init(rawValue:)) ?? .none
            let profile = working.value(forKey: "PDFXOutputIntentProfile")?.textualValue?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let hasProfile = profile.map {
                !$0.isEmpty && $0.caseInsensitiveCompare("None") != .orderedSame
            } ?? false

            if !hasProfile {
                if SemanticJoboptions.embedsOutputIntentProfile(in: working) {
                    propose(
                        path: "/\(SemanticJoboptions.embedOutputIntentProfileKey)",
                        value: .boolean(false),
                        reason: .missingOutputProfileDisablesEmbedding,
                        rule: "output-intent.missing-profile"
                    )
                }
                return
            }

            if standard.isPDFX {
                propose(
                    path: "/\(SemanticJoboptions.embedOutputIntentProfileKey)",
                    value: .boolean(true),
                    reason: .standardOutputProfileEmbedding,
                    rule: "standard.pdfx.embed-output-profile"
                )
            }
        }

        mutating func evaluateCompatibilityRules() {
            guard let compatibilityText = working.value(forKey: "CompatibilityLevel")?.textualValue,
                  let compatibility = Double(compatibilityText)
            else { return }

            if compatibility < 1.4,
               working.value(forKey: "AllowTransparency")?.boolValue == true {
                propose(
                    path: "/AllowTransparency",
                    value: .boolean(false),
                    reason: .transparency,
                    rule: "ghostscript.transparency"
                )
            }

            if compatibility < 1.2 {
                for key in ["ColorImageFilter", "GrayImageFilter"]
                where working.value(forKey: key)?.textualValue == "FlateEncode" {
                    propose(
                        path: "/\(key)",
                        value: .name("DCTEncode"),
                        reason: .flatePDF11,
                        rule: "ghostscript.pdf11.\(key)"
                    )
                }
            }
        }

        mutating func evaluateCompoundSettingRules() {
            evaluatePageRange()
            evaluateDeviceResolution()
            evaluatePageSize()
            for kind in SemanticJoboptions.ImageKind.allCases {
                evaluateDownsampling(kind: kind)
                evaluateCompression(kind: kind)
                evaluateImagePolicy(kind: kind)
            }
            evaluateMonoSmoothing()
            evaluatePDFXBoxes()
        }

        private mutating func evaluatePDFAProfile() {
            let path = JoboptionsKeyPath("/OutputICCProfile")
            let current = working.value(forPath: path)?.textualValue
            if let current,
               context.availableProfiles.contains(where: {
                   $0.colorSpace == "RGB" && $0.matches(current)
               }) {
                return
            }
            let replacement = context.availableProfiles.first(where: {
                $0.colorSpace == "RGB" && $0.name.localizedCaseInsensitiveContains("sRGB")
            })?.name ?? "sRGB Profile"
            propose(
                path: path.description,
                value: .string(replacement),
                reason: .standardOutputProfile,
                rule: "standard.pdfa.output-profile"
            )
        }

        private mutating func evaluatePDFXProfile() {
            let path = JoboptionsKeyPath("/PDFXOutputIntentProfile")
            let current = working.value(forPath: path)?.textualValue
            if let current,
               context.availableProfiles.contains(where: {
                   $0.colorSpace == "CMYK"
                       && ($0.profileClass.isEmpty || $0.profileClass == "prtr")
                       && $0.matches(current)
               }) {
                return
            }
            let replacement = context.availableProfiles.first(where: {
                   $0.colorSpace == "CMYK"
                       && ($0.profileClass.isEmpty || $0.profileClass == "prtr")
                       && (
                           $0.name == SemanticJoboptions.defaultPDFXOutputIntentProfile
                           || $0.fileStem == SemanticJoboptions.defaultPDFXOutputIntentProfile
                       )
               })?.name ?? SemanticJoboptions.defaultPDFXOutputIntentProfile
            propose(
                path: path.description,
                value: .string(replacement),
                reason: .standardOutputProfile,
                rule: "standard.pdfx.output-profile"
            )
        }

        private mutating func evaluatePageRange() {
            guard working.value(forKey: "StartPage") != nil
                    || working.value(forKey: "EndPage") != nil
            else { return }
            let start = working.value(forKey: "StartPage")?.numberValue
            let end = working.value(forKey: "EndPage")?.numberValue
            let isValid = start.map(Self.isIntegerAtLeastOne) == true
                && (end == -1 || (end.map(Self.isIntegerAtLeastOne) == true && end! >= start!))
            guard !isValid else { return }
            propose(
                path: "/StartPage",
                value: Self.integer(1),
                reason: .invalidPageRange,
                rule: "group.page-range.start"
            )
            propose(
                path: "/EndPage",
                value: Self.integer(-1),
                reason: .invalidPageRange,
                rule: "group.page-range.end"
            )
        }

        private mutating func evaluateDeviceResolution() {
            guard working.value(forKey: "HWResolution") != nil else { return }
            guard !Self.isPositiveArray(working.value(forKey: "HWResolution"), count: 2) else { return }
            propose(
                path: "/HWResolution",
                value: .array([Self.integer(2_400), Self.integer(2_400)]),
                reason: .invalidDeviceResolution,
                rule: "group.device-resolution"
            )
        }

        private mutating func evaluatePageSize() {
            guard working.value(forKey: "PageSize") != nil else { return }
            guard !Self.isPositiveArray(working.value(forKey: "PageSize"), count: 2) else { return }
            propose(
                path: "/PageSize",
                value: .array([Self.decimal(595.276), Self.decimal(841.89)]),
                reason: .invalidPageSize,
                rule: "group.page-size"
            )
        }

        private mutating func evaluateDownsampling(kind: SemanticJoboptions.ImageKind) {
            let prefix = kind.rawValue
            guard working.value(forKey: "Downsample\(prefix)Images")?.boolValue == true else { return }
            let mode = working.value(forKey: "\(prefix)ImageDownsampleType")?.textualValue
            let resolution = working.value(forKey: "\(prefix)ImageResolution")?.numberValue
            let threshold = working.value(forKey: "\(prefix)ImageDownsampleThreshold")?.numberValue
            let isValid = ["Average", "Bicubic", "Subsample"].contains(mode ?? "")
                && resolution.map { Self.isInteger($0, in: 1...9_600) } == true
                && threshold.map { $0.isFinite && (1...10).contains($0) } == true
            guard !isValid else { return }
            propose(
                path: "/Downsample\(prefix)Images",
                value: .boolean(false),
                reason: .invalidDownsampling,
                rule: "group.downsampling.\(prefix.lowercased())"
            )
        }

        private mutating func evaluateCompression(kind: SemanticJoboptions.ImageKind) {
            let prefix = kind.rawValue
            guard working.value(forKey: "Encode\(prefix)Images")?.boolValue == true else { return }
            let filter = working.value(forKey: "\(prefix)ImageFilter")?.textualValue
            let allowed = kind == .monochrome
                ? ["CCITTFaxEncode", "FlateEncode", "RunLengthEncode"]
                : ["DCTEncode", "FlateEncode", "JPXEncode"]
            guard allowed.contains(filter ?? "") else {
                propose(
                    path: "/\(prefix)ImageFilter",
                    value: .name(kind == .monochrome ? "CCITTFaxEncode" : "FlateEncode"),
                    reason: .invalidCompression,
                    rule: "group.compression.\(prefix.lowercased()).filter"
                )
                return
            }
            guard kind != .monochrome else { return }

            let qualityPath: String?
            let fallback: Double
            if filter == "DCTEncode" {
                if working.value(forKey: "AutoFilter\(prefix)Images")?.boolValue == true {
                    qualityPath = "/\(prefix)ACSImageDict /QFactor"
                    fallback = 0.40
                } else {
                    qualityPath = "/\(prefix)ImageDict /QFactor"
                    fallback = 0.76
                }
            } else if filter == "JPXEncode" {
                qualityPath = "/JPEG2000\(prefix)ImageDict /Quality"
                fallback = 15
            } else {
                qualityPath = nil
                fallback = 0
            }
            guard let qualityPath else { return }
            let quality = working.value(forPath: qualityPath)?.numberValue
            let isValid = if filter == "JPXEncode" {
                quality.map { $0.isFinite && (0...100).contains($0) } == true
            } else {
                quality.map { $0.isFinite && $0 > 0 } == true
            }
            guard !isValid else { return }
            propose(
                path: qualityPath,
                value: Self.decimal(fallback),
                reason: .invalidImageQuality,
                rule: "group.compression.\(prefix.lowercased()).quality"
            )
        }

        private mutating func evaluateImagePolicy(kind: SemanticJoboptions.ImageKind) {
            let prefix = kind.rawValue
            let resolutionPath = "/\(prefix)ImageMinResolution"
            let policyPath = "/\(prefix)ImageMinResolutionPolicy"
            guard working.value(forPath: resolutionPath) != nil
                    || working.value(forPath: policyPath) != nil
            else { return }
            let resolution = working.value(forPath: resolutionPath)?.numberValue
            if resolution.map({ Self.isInteger($0, in: 1...9_600) }) != true {
                propose(
                    path: resolutionPath,
                    value: Self.integer(kind == .monochrome ? 1_200 : 150),
                    reason: .invalidImagePolicy,
                    rule: "group.image-policy.\(prefix.lowercased()).resolution"
                )
            }
            let policy = working.value(forPath: policyPath)?.textualValue
            if !["OK", "Warning", "Error"].contains(policy ?? "") {
                propose(
                    path: policyPath,
                    value: .name("OK"),
                    reason: .invalidImagePolicy,
                    rule: "group.image-policy.\(prefix.lowercased()).policy"
                )
            }
        }

        private mutating func evaluateMonoSmoothing() {
            guard working.value(forKey: "AntiAliasMonoImages")?.boolValue == true else { return }
            let depth = working.value(forKey: "MonoImageDepth")?.numberValue
            guard depth.map({ $0.rounded() == $0 && [2, 4, 8].contains(Int($0)) }) != true else { return }
            propose(
                path: "/AntiAliasMonoImages",
                value: .boolean(false),
                reason: .invalidMonoSmoothing,
                rule: "group.mono-smoothing"
            )
        }

        private mutating func evaluatePDFXBoxes() {
            guard let raw = working.value(forKey: "iPS2PDFStandard")?.textualValue,
                  PDFStandard(rawValue: raw)?.isPDFX == true
            else { return }

            let trimUsesError = working.value(forKey: "PDFXNoTrimBoxError")?.boolValue
            let trimIsValid = trimUsesError == true
                || (trimUsesError == false && Self.isFiniteArray(
                    working.value(forKey: "PDFXTrimBoxToMediaBoxOffset"), count: 4
                ))
            if !trimIsValid {
                propose(
                    path: "/PDFXNoTrimBoxError",
                    value: .boolean(false),
                    reason: .invalidPDFXBoxes,
                    rule: "group.pdfx-boxes.trim-policy"
                )
                propose(
                    path: "/PDFXTrimBoxToMediaBoxOffset",
                    value: .array(Array(repeating: Self.integer(0), count: 4)),
                    reason: .invalidPDFXBoxes,
                    rule: "group.pdfx-boxes.trim-offsets"
                )
            }

            let bleedUsesMedia = working.value(forKey: "PDFXSetBleedBoxToMediaBox")?.boolValue
            let bleedIsValid = bleedUsesMedia == true
                || (bleedUsesMedia == false && Self.isFiniteArray(
                    working.value(forKey: "PDFXBleedBoxToTrimBoxOffset"), count: 4
                ))
            if !bleedIsValid {
                propose(
                    path: "/PDFXSetBleedBoxToMediaBox",
                    value: .boolean(true),
                    reason: .invalidPDFXBoxes,
                    rule: "group.pdfx-boxes.bleed-policy"
                )
            }
        }

        private mutating func evaluatePDFXOutputIntentMetadata() {
            guard let selected = working.value(forKey: "PDFXOutputIntentProfile")?.textualValue,
                  !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  selected.caseInsensitiveCompare("None") != .orderedSame
            else { return }

            let profile = context.availableProfiles.first {
                $0.colorSpace == "CMYK"
                    && ($0.profileClass.isEmpty || $0.profileClass == "prtr")
                    && $0.matches(selected)
            }
            let currentIdentifier = working
                .value(forKey: "PDFXOutputConditionIdentifier")?
                .textualValue?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let identifier: String
            if let known = profile?.outputConditionIdentifier, !known.isEmpty {
                identifier = known
            } else if let currentIdentifier,
                      !currentIdentifier.isEmpty,
                      currentIdentifier.caseInsensitiveCompare("None") != .orderedSame {
                identifier = currentIdentifier
            } else {
                identifier = "Custom"
            }
            propose(
                path: "/PDFXOutputConditionIdentifier",
                value: .string(identifier),
                reason: .standardOutputConditionIdentifier,
                rule: "standard.pdfx.output-condition-identifier"
            )

            let trapped = working.value(forKey: "PDFXTrapped")?.textualValue
            if trapped != "True", trapped != "False" {
                propose(
                    path: "/PDFXTrapped",
                    value: .name("False"),
                    reason: .standardTrappedState,
                    rule: "standard.pdfx.trapped"
                )
            }
        }

        private mutating func propose(
            path pathText: String,
            value: JoboptionsValue,
            reason: JoboptionsConsistencyIssue.Reason,
            rule: String
        ) {
            let path = JoboptionsKeyPath(pathText)
            let current = working.value(forPath: path)
            guard !Self.valuesAreEquivalent(current, value) else { return }

            if let existing = proposalsByPath[path], !Self.valuesAreEquivalent(existing, value) {
                return
            }
            proposalsByPath[path] = value
            issues.append(
                JoboptionsConsistencyIssue(
                    path: path,
                    currentValue: original.value(forPath: path),
                    proposedValue: value,
                    reasonCode: reason,
                    ruleIdentifier: rule
                )
            )
            if let adjusted = try? working.replacingValue(forPath: path, with: value) {
                working = adjusted
            }
        }

        private static func valuesAreEquivalent(
            _ lhs: JoboptionsValue?,
            _ rhs: JoboptionsValue
        ) -> Bool {
            guard let lhs else { return false }
            if let left = lhs.numberValue, let right = rhs.numberValue {
                return left == right
            }
            return lhs == rhs
        }

        private static func integer(_ value: Int) -> JoboptionsValue {
            .number(Double(value), original: String(value))
        }

        private static func decimal(_ value: Double) -> JoboptionsValue {
            var text = String(format: "%.6f", value)
            while text.last == "0" { text.removeLast() }
            if text.last == "." { text.removeLast() }
            return .number(value, original: text)
        }

        private static func isIntegerAtLeastOne(_ value: Double) -> Bool {
            value.isFinite && value.rounded() == value && value >= 1
        }

        private static func isInteger(_ value: Double, in range: ClosedRange<Int>) -> Bool {
            value.isFinite && value.rounded() == value && range.contains(Int(value))
        }

        private static func isPositiveArray(_ value: JoboptionsValue?, count: Int) -> Bool {
            guard case let .array(values) = value, values.count == count else { return false }
            return values.allSatisfy { ($0.numberValue ?? 0).isFinite && ($0.numberValue ?? 0) > 0 }
        }

        private static func isFiniteArray(_ value: JoboptionsValue?, count: Int) -> Bool {
            guard case let .array(values) = value, values.count == count else { return false }
            return values.allSatisfy { $0.numberValue?.isFinite == true }
        }
    }
}

typealias GhostscriptCompatibilityAdjuster = JoboptionsConsistencyEngine
