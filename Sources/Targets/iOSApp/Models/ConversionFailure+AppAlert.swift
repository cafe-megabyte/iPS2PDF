import Foundation

extension ConversionFailure {
    var appAlert: AppAlert {
        var messageParts = [localizedMessage]
        var detailsParts: [String] = []
        if let diagnostics {
            let format = String(localized: "error_diagnostics_format")
            messageParts.append(String(format: format, String(diagnostics.suffix(8_000))))
            detailsParts.append(diagnostics)
        }
        if let returnCode {
            let format = String(localized: "error_return_code_format")
            let text = String(format: format, returnCode)
            messageParts.append(text)
            detailsParts.insert(text, at: 0)
        }
        return AppAlert(
            kind: .error,
            title: String(localized: "conversion_failed"),
            message: messageParts.joined(separator: "\n\n"),
            details: detailsParts.isEmpty ? nil : detailsParts.joined(separator: "\n\n")
        )
    }
}
