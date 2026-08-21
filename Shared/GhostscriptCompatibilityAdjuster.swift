import Foundation

enum GhostscriptCompatibilityAdjuster {
    static func issues(in document: LosslessJoboptionsDocument) -> [GhostscriptCompatibilityIssue] {
        guard let compatibilityLevel = compatibilityLevel(in: document) else { return [] }
        var issues: [GhostscriptCompatibilityIssue] = []

        if compatibilityLevel < 1.4,
           document.value(forKey: "AllowTransparency")?.boolValue == true {
            issues.append(
                GhostscriptCompatibilityIssue(
                    key: "AllowTransparency",
                    currentValue: "true",
                    adjustedValue: "false",
                    reason: "Transparency requires PDF 1.4 or newer."
                )
            )
        }

        if compatibilityLevel < 1.2 {
            for key in ["ColorImageFilter", "GrayImageFilter"] {
                guard document.value(forKey: key)?.textualValue == "FlateEncode" else { continue }
                issues.append(
                    GhostscriptCompatibilityIssue(
                        key: key,
                        currentValue: "FlateEncode",
                        adjustedValue: "DCTEncode",
                        reason: "Flate image compression is not accepted by Ghostscript for PDF 1.1."
                    )
                )
            }
        }

        return issues
    }

    static func adjustedDocument(from document: LosslessJoboptionsDocument) throws -> LosslessJoboptionsDocument {
        var adjusted = document
        for issue in issues(in: document) {
            switch issue.key {
            case "AllowTransparency":
                adjusted = try adjusted.replacingValue(forKey: issue.key, with: .boolean(false))
            case "ColorImageFilter", "GrayImageFilter":
                adjusted = try adjusted.replacingValue(forKey: issue.key, with: .name("DCTEncode"))
            default:
                break
            }
        }
        return adjusted
    }

    static func adjustedData(from data: Data) throws -> Data {
        let document = try LosslessJoboptionsDocument(data: data)
        return try adjustedDocument(from: document).data
    }

    private static func compatibilityLevel(in document: LosslessJoboptionsDocument) -> Double? {
        guard let text = document.value(forKey: "CompatibilityLevel")?.textualValue,
              let value = Double(text)
        else { return nil }
        return value
    }
}
