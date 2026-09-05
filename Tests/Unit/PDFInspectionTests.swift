import Foundation
import XCTest

final class PDFInspectionTests: XCTestCase {
    private func fixture(_ name: String) throws -> URL {
        let bundle = Bundle(for: Self.self)
        return try XCTUnwrap(bundle.url(forResource: name, withExtension: "pdf") ?? bundle.url(forResource: name, withExtension: "pdf", subdirectory: "Fixtures"))
    }
    private func inspect(_ name: String, password: String? = nil) throws -> PDFInspectionReport {
        try PDFInspectionService.inspect(url: fixture(name), fileName: name + ".pdf", password: password)
    }
    func testUsedMissingFontIsProminentButUnusedResourceIsNotAProblem() throws {
        let report = try inspect("InfoPlain")
        XCTAssertTrue(report.isComplete)
        XCTAssertEqual(report.fontWarnings.map(\.title), ["Helvetica"])
        XCTAssertEqual(report.sections(in: .fonts).first?.title, "Helvetica")
        XCTAssertTrue(report.sections(in: .fonts).contains { $0.title == "Courier" && $0.warning == nil })
        XCTAssertTrue(report.plainText.contains("PDF Information Test"))
        XCTAssertTrue(report.plainText.contains("ÄÖÜ €"))
        XCTAssertFalse(PDFInspectionFormat.size(12_345_678).contains("12345678"))
    }
    func testNestedXObjectFontIsFound() throws {
        let report = try inspect("InfoNestedFont")
        XCTAssertTrue(report.isComplete)
        XCTAssertEqual(report.fontWarnings.map(\.title), ["Helvetica"])
    }
    func testType3IsEmbeddedAndDoesNotCreateAnEmptyProblemOverview() throws {
        let report = try inspect("InfoType3")
        XCTAssertTrue(report.isComplete)
        XCTAssertTrue(report.fontWarnings.isEmpty)
        XCTAssertNil(report.warningSummary)
        XCTAssertFalse(report.paragraphs.contains { $0.text == String(localized: "Problems") })
        XCTAssertTrue(report.sections(in: .fonts).first?.fields.contains { $0.value == String(localized: "Embedded (Type 3 glyph descriptions)") } == true)
    }
    func testStandardsAreClaimsAndRawXMPComesLast() throws {
        let report = try inspect("InfoClaimedPDFA")
        XCTAssertTrue(report.hasConformityDeclaration)
        XCTAssertEqual(report.declaredStandards, ["PDF/A-2b (XMP)"])
        XCTAssertEqual(report.fontWarnings.count, 1)
        let declared = report.sections.first?.fields.first { $0.label == String(localized: "Standard according to metadata") }
        XCTAssertEqual(declared?.value, "PDF/A-2b (XMP)")
        XCTAssertEqual(declared?.emphasis, .standardDeclaration)
        XCTAssertEqual(report.paragraphs.last?.style, .metadata)
        XCTAssertFalse(report.plainText.contains("compatible"))
    }
    func testOrdinaryPDFHasNoConformityDeclaration() throws {
        let report = try inspect("InfoPlain")
        XCTAssertFalse(report.hasConformityDeclaration)
        XCTAssertTrue(report.declaredStandards.isEmpty)
        let declared = report.sections.first?.fields.first { $0.label == String(localized: "Standard according to metadata") }
        XCTAssertNil(declared?.emphasis)
    }
    func testICCProfileIsDeduplicatedAndOutputIntentIsPresent() throws {
        let report = try inspect("InfoICC")
        let profiles = report.sections.filter { $0.id.hasPrefix("icc-") }
        XCTAssertEqual(profiles.count, 1)
        XCTAssertTrue(profiles[0].fields.contains { $0.value.contains("OutputIntents") && $0.value.contains("ColorSpace") })
        XCTAssertTrue(report.sections(in: .colors).contains { $0.title == String(localized: "Output intent") })
        for section in report.sections { XCTAssertEqual(Set(section.fields.map(\.id)).count, section.fields.count, section.id) }
    }
    func testEncryptedPDFsRequireCorrectPasswordAndShowOriginalPermissions() throws {
        for algorithm in ["RC4-40", "RC4-128", "AES-128", "AES-256"] {
            let name = "InfoEncrypted-" + algorithm
            XCTAssertTrue(try inspect(name).isLocked, algorithm)
            XCTAssertTrue(try inspect(name, password: "wrong").isLocked, algorithm)
            for password in ["user-test", "owner-test"] {
                let report = try inspect(name, password: password)
                XCTAssertFalse(report.isLocked, algorithm)
                XCTAssertTrue(report.isComplete, algorithm)
                XCTAssertEqual(report.pageCount, 1)
                let encryption = try XCTUnwrap(report.sections.first { $0.id == "encryption" })
                XCTAssertTrue(encryption.fields.contains { $0.value == "Standard" }, algorithm)
                XCTAssertTrue(encryption.fields.contains { $0.label.contains(String(localized: "Content copying")) && $0.value == PDFInspectionFormat.yesNo(false) }, algorithm)
                XCTAssertFalse(report.plainText.contains(password))
                XCTAssertFalse(encryption.fields.contains { ["O", "U", "OE", "UE", "Perms"].contains($0.label) })
            }
        }
    }
    func testEmptyAndUnicodePasswords() throws {
        XCTAssertFalse(try inspect("InfoEmptyPassword").isLocked)
        XCTAssertTrue(try inspect("InfoUnicodePassword", password: "wrong").isLocked)
        XCTAssertFalse(try inspect("InfoUnicodePassword", password: "Päss (\\) € 🔒").isLocked)
        XCTAssertFalse(try inspect("InfoUnicodePassword", password: "Öwner 🔑").isLocked)
    }
    func testEncryptedXRefStreamsAndIncrementalTrailersPreserveDeclaredPermissions() throws {
        for name in ["InfoEncryptedXRefStream", "InfoEncryptedIncremental"] {
            let url = try fixture(name)
            let original = try Data(contentsOf: url)
            for password in ["user-test", "owner-test"] {
                let report = try inspect(name, password: password)
                XCTAssertFalse(report.isLocked, name)
                XCTAssertTrue(report.isComplete, name + ": " + report.notices.joined(separator: "\n"))
                let encryption = try XCTUnwrap(report.sections.first { $0.id == "encryption" })
                XCTAssertTrue(encryption.fields.contains { $0.label.contains(String(localized: "Content copying")) && $0.value == PDFInspectionFormat.yesNo(false) }, name)
            }
            XCTAssertEqual(try Data(contentsOf: url), original, "Inspection must never rewrite its input")
        }
    }
    func testPageFormatsAndOriginalFileDatesAreReported() throws {
        let created = Date(timeIntervalSince1970: 1_000_000)
        let modified = Date(timeIntervalSince1970: 2_000_000)
        let report = try PDFInspectionService.inspect(url: fixture("InfoPlain"), fileName: "Original.pdf", password: nil, fileDates: (created, modified))
        XCTAssertEqual(report.sections(in: .pages).first?.id, "page-formats")
        XCTAssertEqual(report.sections(in: .pages).first?.fields.first?.value, "1")
        XCTAssertEqual(report.sections.first { $0.id == "filesystem" }?.fields.map(\.value), [PDFInspectionFormat.date(created), PDFInspectionFormat.date(modified)])
    }
    func testSnapshotSurvivesOriginalDeletionAndRemovesItsOwnFile() throws {
        let original = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        try FileManager.default.copyItem(at: fixture("InfoPlain"), to: original)
        var input: PDFInspectionInput? = try PDFInspectionInput(sourceURL: original)
        let snapshot = try XCTUnwrap(input?.url)
        try FileManager.default.removeItem(at: original)
        XCTAssertTrue(try PDFInspectionService.inspect(url: snapshot, fileName: "Snapshot.pdf", password: nil).isComplete)
        input = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshot.path))
    }
    func testEmbeddedSubsetAndFullFontAreDistinguishedWithoutWarnings() throws {
        for (fixture, status) in [("InfoEmbeddedSubset", "Embedded subset"), ("InfoEmbeddedFull", "Fully embedded (PDF declaration)")] {
            let report = try inspect(fixture)
            XCTAssertTrue(report.isComplete, report.notices.joined(separator: "\n"))
            XCTAssertNil(report.warningSummary)
            XCTAssertTrue(report.sections(in: .fonts).contains { $0.fields.contains { $0.value == String(localized: String.LocalizationValue(status)) } })
        }
    }
    func testType0ResolvesDescendantFontEmbedding() throws {
        let report = try inspect("InfoType0")
        XCTAssertEqual(report.fontWarnings.count, 1)
        XCTAssertEqual(report.fontWarnings.first?.title, "UnicodeFont")
    }
    func testInlineImagePropertiesSurviveTheScannerCallback() throws {
        let report = try inspect("InfoInlineImage")
        XCTAssertTrue(report.isComplete, report.notices.joined(separator: "\n"))
        let image = try XCTUnwrap(report.sections.first { $0.id.contains("inline-") })
        XCTAssertTrue(image.fields.contains { $0.value.contains("ppi") })
        XCTAssertNil(report.warningSummary)
    }
    func testMultipleStandardDeclarationsAreKeptSeparate() {
        let data = Data("""
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns:a="http://www.aiim.org/pdfa/ns/id/">
          <rdf:Description a:part="1" a:conformance="B"/>
          <rdf:Description a:part="2" a:conformance="U"/>
        </rdf:RDF>
        """.utf8)
        let claims = PDFXMPReader(data: data).declarations
        XCTAssertEqual(Array(claims.prefix(2)), ["PDF/A-1b", "PDF/A-2u"])
        XCTAssertTrue(claims.last?.contains(String(localized: "Conflicting standard metadata")) == true)
    }
    func testXMPOnlyTitleAppearsInOverview() throws {
        let report = try inspect("InfoXMPTitle")
        XCTAssertTrue(report.sections.first { $0.id == "document" }!.fields.contains { $0.label == String(localized: "Title") && $0.value == "XMP-only title (XMP)" })
    }

    func testBrokenPDFReturnsAnError() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("%PDF-1.7\nnot a document".utf8).write(to: url)
        XCTAssertThrowsError(try PDFInspectionService.inspect(url: url, fileName: "broken.pdf", password: nil))
    }
    func testExternalPDFsRouteToInformationAndExplicitConversionStillWorks() throws {
        let router = IncomingDocumentRouter()
        let url = try fixture("InfoPlain")
        guard case .pdfInformation = try router.classify(url) else { return XCTFail("External PDF must open information") }
        guard case .conversionInput = try router.classify(url, purpose: .conversion) else { return XCTFail("Explicit conversion must remain available") }
        let renamed = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".dat")
        defer { try? FileManager.default.removeItem(at: renamed) }
        try FileManager.default.copyItem(at: url, to: renamed)
        guard case .pdfInformation = try router.classify(renamed) else { return XCTFail("PDF header must win over extension") }
    }
    @MainActor func testPasswordRetryAndCancellation() async throws {
        let controller = PDFPasswordController()
        let url = try fixture("InfoEncrypted-AES-128")
        let prompt = expectation(description: "Password prompt")
        var observed = false
        let observation = controller.$request.sink { request in if request != nil, !observed { observed = true; prompt.fulfill() } }
        let task = Task { try await controller.password(for: url) }
        await fulfillment(of: [prompt], timeout: 5)
        let retry = expectation(description: "Wrong password stays retryable")
        let retryObservation = controller.$request.sink { request in if request?.wasIncorrect == true { retry.fulfill() } }
        controller.submit("wrong")
        await fulfillment(of: [retry], timeout: 5)
        retryObservation.cancel()
        controller.submit("user-test")
        let result = try await task.value
        XCTAssertEqual(result, "user-test")
        XCTAssertNil(controller.request)
        observation.cancel()
        let cancelled = Task { try await controller.password(for: url) }
        let next = expectation(description: "Next prompt")
        let nextObservation = controller.$request.sink { if $0 != nil { next.fulfill() } }
        await fulfillment(of: [next], timeout: 5)
        controller.cancel()
        do { _ = try await cancelled.value; XCTFail("Expected cancellation") } catch is CancellationError { }
        nextObservation.cancel()
        XCTAssertNil(controller.request)
    }
}
