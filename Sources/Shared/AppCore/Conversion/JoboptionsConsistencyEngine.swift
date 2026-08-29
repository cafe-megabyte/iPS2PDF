import Foundation

enum JoboptionsConsistencyEngine {
    static func issues(
        in document: LosslessJoboptionsDocument,
        context: JoboptionsConsistencyContext = .empty
    ) -> [JoboptionsConsistencyIssue] {
        var evaluator = Evaluator(document: document, context: context)
        evaluator.evaluateStandardRules()
        evaluator.evaluateCompatibilityRules()
        return evaluator.issues
    }

    static func effectiveDocument(
        from document: LosslessJoboptionsDocument,
        context: JoboptionsConsistencyContext = .empty
    ) throws -> LosslessJoboptionsDocument {
        let analysis = issues(in: document, context: context)
        if let unresolved = analysis.first(where: { !$0.isAutomaticallyRepairable }) {
            throw JoboptionsError.unresolvedConsistency(
                "\(unresolved.path.description): \(unresolved.reason)"
            )
        }
        return try repair(document, applying: analysis)
    }

    static func repair(
        _ document: LosslessJoboptionsDocument,
        applying issues: [JoboptionsConsistencyIssue]
    ) throws -> LosslessJoboptionsDocument {
        let changes = issues.compactMap { issue -> JoboptionsChange? in
            guard issue.isAutomaticallyRepairable, let value = issue.proposedValue else { return nil }
            return JoboptionsChange(issue.path.description, value)
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
        var working: LosslessJoboptionsDocument
        var issues: [JoboptionsConsistencyIssue] = []
        var proposalsByPath: [JoboptionsKeyPath: JoboptionsValue] = [:]

        init(document: LosslessJoboptionsDocument, context: JoboptionsConsistencyContext) {
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
                evaluatePDFXProfile()
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

        private mutating func evaluatePDFAProfile() {
            let path = JoboptionsKeyPath("/OutputICCProfile")
            let current = working.value(forPath: path)?.textualValue
            if let current,
               context.availableProfiles.contains(where: {
                   $0.colorSpace == "RGB" && $0.matches(current)
               }) {
                return
            }
            if let profile = context.availableProfiles.first(where: {
                $0.colorSpace == "RGB" && $0.name.localizedCaseInsensitiveContains("sRGB")
            }) {
                propose(
                    path: path.description,
                    value: .string(profile.name),
                    reason: .standardOutputProfile,
                    rule: "standard.pdfa.output-profile"
                )
            } else {
                reportUnresolved(
                    path: path,
                    reason: .missingOutputProfile,
                    rule: "standard.pdfa.output-profile.missing"
                )
            }
        }

        private mutating func evaluatePDFXProfile() {
            let path = JoboptionsKeyPath("/PDFXOutputIntentProfile")
            let current = working.value(forPath: path)?.textualValue
            if let current,
               context.availableProfiles.contains(where: {
                   $0.colorSpace == "CMYK" && $0.matches(current)
               }) {
                return
            }
            reportUnresolved(
                path: path,
                reason: .missingOutputProfile,
                rule: "standard.pdfx.output-profile.missing"
            )
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
                reportUnresolved(
                    path: path,
                    reason: reason,
                    rule: "conflict.\(rule)"
                )
                return
            }
            proposalsByPath[path] = value
            issues.append(
                JoboptionsConsistencyIssue(
                    path: path,
                    currentValue: current,
                    proposedValue: value,
                    reasonCode: reason,
                    ruleIdentifier: rule,
                    isAutomaticallyRepairable: true
                )
            )
            if let adjusted = try? working.replacingValue(forPath: path, with: value) {
                working = adjusted
            }
        }

        private mutating func reportUnresolved(
            path: JoboptionsKeyPath,
            reason: JoboptionsConsistencyIssue.Reason,
            rule: String
        ) {
            issues.append(
                JoboptionsConsistencyIssue(
                    path: path,
                    currentValue: working.value(forPath: path),
                    proposedValue: nil,
                    reasonCode: reason,
                    ruleIdentifier: rule,
                    isAutomaticallyRepairable: false
                )
            )
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
    }
}

typealias GhostscriptCompatibilityAdjuster = JoboptionsConsistencyEngine
