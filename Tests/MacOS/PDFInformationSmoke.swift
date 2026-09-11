import AppKit
import Foundation
import GhostscriptRuntime

@main
struct PDFInformationSmoke {
    @MainActor static func main() throws {
        guard CommandLine.arguments.count == 2 else { fatalError("Expected fixture directory") }
        let fixtures = URL(fileURLWithPath: CommandLine.arguments[1])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PDFSmoke-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let joboptions = directory.appendingPathComponent("Test.joboptions")
        try Data("<< /CompatibilityLevel 1.7 /NeverEmbed [] /EmbedAllFonts true >> setdistillerparams\n".utf8).write(to: joboptions)
        let resources = GhostscriptRuntimeResources.ghostscriptDirectoryURL!
        let profiles = GhostscriptRuntimeResources.profilesDirectoryURL!
        let cases: [(String, String?, Bool)] = [
            ("InfoEncrypted-RC4-40", "user-test", true),
            ("InfoEncrypted-RC4-128", "owner-test", true),
            ("InfoEncrypted-AES-128", "user-test", true),
            ("InfoEncrypted-AES-256", "owner-test", true),
            ("InfoUnicodePassword", "Päss (\\) € 🔒", true),
            ("InfoUnicodePassword", "Öwner 🔑", true),
            ("InfoEmptyPassword", nil, true),
            ("InfoEncrypted-AES-128", "wrong", false),
            ("InfoEncrypted-AES-128", nil, false)
        ]
        for (index, entry) in cases.enumerated() {
            let (name, password, expected) = entry
            let input = try FileHandle(forReadingFrom: fixtures.appendingPathComponent(name + ".pdf"))
            let outputURL = directory.appendingPathComponent("\(index).pdf")
            let journalURL = directory.appendingPathComponent("\(index).log")
            FileManager.default.createFile(atPath: outputURL.path, contents: nil)
            FileManager.default.createFile(atPath: journalURL.path, contents: nil)
            let output = try FileHandle(forUpdating: outputURL)
            let journal = try FileHandle(forUpdating: journalURL)
            let options = try FileHandle(forReadingFrom: joboptions)
            defer { try? input.close(); try? output.close(); try? journal.close(); try? options.close() }
            var code: Int32 = 0, stage: Int32 = 0
            gs_bridge_reset_cancellation()
            let run: (UnsafePointer<CChar>?) -> Int32 = { passwordPointer in
                resources.path.withCString { resourcePointer in
                    profiles.path.withCString { profilePointer in
                        gs_run_conversion_with_fds(input.fileDescriptor, output.fileDescriptor, options.fileDescriptor, journal.fileDescriptor,
                            0, Int32(GS_BRIDGE_OUTPUT_PDF.rawValue), 1, 0, 1, 0, 0, "1.7", "none", nil, resourcePointer, profilePointer, nil, nil, nil, passwordPointer,
                            1, 1, Int64(Date().addingTimeInterval(60).timeIntervalSince1970), 100_000_000, &code, &stage)
                    }
                }
            }
            let status = password.map { $0.withCString(run) } ?? run(nil)
            let log = try String(contentsOf: journalURL, encoding: .utf8)
            let rejected = ["requires a password for access", "password did not work", "incorrect password", "invalid password"].contains { log.lowercased().contains($0) }
            precondition(expected == (status == 0 && !rejected), "Unexpected password outcome for \(name), code \(code), stage \(stage)")
            if let password { precondition(!log.contains(password), "Password appeared in diagnostics") }
            if expected {
                if let password {
                    let outputData = try Data(contentsOf: outputURL)
                    precondition(outputData.range(of: Data(password.utf8)) == nil, "Password appeared in generated PDF")
                }
                let report = try PDFInspectionService.inspect(url: outputURL, fileName: "Output.pdf", password: nil)
                precondition(report.pageCount == 1 && report.isComplete, "Generated PDF could not be fully inspected")
            }
        }
        let report = try PDFInspectionService.inspect(url: fixtures.appendingPathComponent("InfoPlain.pdf"), fileName: "Ä Report.pdf", password: nil)
        let rtf = try MacOSPDFReportSharing.rtf(report)
        let rich = try NSAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        precondition(rich.string == report.plainText, "RTF/plain text mismatch")
        var hasHighlight = false
        rich.enumerateAttribute(.backgroundColor, in: NSRange(location: 0, length: rich.length)) { value, _, _ in hasHighlight = hasHighlight || value != nil }
        precondition(hasHighlight, "RTF warning is not highlighted")
        let redacted = try PDFInspectionService.inspect(url: fixtures.appendingPathComponent("Review/cryptfilter-recipient.pdf"), fileName: "Recipients.pdf", password: "user-test")
        let redactedRTF = try MacOSPDFReportSharing.rtf(redacted)
        let redactedText = try NSAttributedString(data: redactedRTF, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil).string
        precondition(redactedText == redacted.plainText)
        precondition(!redactedText.contains("REVIEW-RECIPIENT-DATA") && !redactedText.contains("/Recipients"), "Crypt filter recipients appeared in exported report")
        let pasteboard = NSPasteboard.general
        let saved = (pasteboard.pasteboardItems ?? []).map { original in
            let copy = NSPasteboardItem()
            for type in original.types { if let data = original.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        }
        defer { pasteboard.clearContents(); if !saved.isEmpty { pasteboard.writeObjects(saved) } }
        try MacOSPDFReportSharing.copy(report)
        precondition(pasteboard.pasteboardItems?.count == 1)
        precondition(pasteboard.string(forType: .string) == report.plainText)
        precondition(pasteboard.data(forType: .rtf) != nil)

        let postScriptDestination = directory.appendingPathComponent("Desktop-style-output.ps")
        let partialDestination = postScriptDestination.appendingPathExtension("partial")
        let firstPostScript = Data("%!PS-Adobe-3.0\n% first\n".utf8)
        let firstSource = directory.appendingPathComponent("first-source.ps")
        try firstPostScript.write(to: firstSource)
        try MacOSPostScriptDestinationWriter.publish(sourceURL: firstSource, destinationURL: postScriptDestination)
        let writtenPostScript = try Data(contentsOf: postScriptDestination)
        precondition(writtenPostScript == firstPostScript, "New PostScript destination was not written")
        precondition(!FileManager.default.fileExists(atPath: partialDestination.path), "PostScript export created an unauthorized sibling file")

        let replacementPostScript = Data("%!PS-Adobe-3.0\n% replacement\n".utf8)
        let replacementSource = directory.appendingPathComponent("replacement-source.ps")
        try replacementPostScript.write(to: replacementSource)
        try MacOSPostScriptDestinationWriter.publish(sourceURL: replacementSource, destinationURL: postScriptDestination)
        let replacedPostScript = try Data(contentsOf: postScriptDestination)
        precondition(replacedPostScript == replacementPostScript, "Existing PostScript destination was not replaced")
        precondition(!FileManager.default.fileExists(atPath: partialDestination.path), "PostScript replacement created an unauthorized sibling file")

        print("PASS: 9 macOS Ghostscript password cases; inspection of converted PDFs; RTF round trip including recipient redaction, warning color and one-item clipboard; exact-destination PostScript save.")
    }
}
