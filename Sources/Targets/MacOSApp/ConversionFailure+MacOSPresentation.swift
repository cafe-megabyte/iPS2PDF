import Foundation

extension ConversionFailure {
    var macOSPresentation: String {
        var parts = [localizedMessage]
        if let returnCode {
            parts.append(
                String.localizedStringWithFormat(
                    String(localized: "Ghostscript return code: %lld"),
                    Int64(returnCode)
                )
            )
        }
        if let diagnostics, !diagnostics.isEmpty {
            parts.append(String(diagnostics.suffix(8_000)))
        }
        return parts.joined(separator: "\n\n")
    }
}
