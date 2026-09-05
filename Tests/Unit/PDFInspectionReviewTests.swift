import Foundation
import XCTest

/// Counterexamples from the independent review of 2026-09-05. Fixtures contain
/// synthetic data only, including deliberately malformed objects and public passwords.
final class PDFInspectionReviewTests: XCTestCase {
    private func inspect(_ name: String, password: String? = nil) throws -> PDFInspectionReport {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "pdf", subdirectory: "Fixtures/Review"))
        let original = try Data(contentsOf: url)
        let report = try PDFInspectionService.inspect(url: url, fileName: name + ".pdf", password: password)
        XCTAssertEqual(try Data(contentsOf: url), original, "Inspection must preserve the original PDF")
        return report
    }
    private func standard(_ report: PDFInspectionReport) throws -> String {
        try XCTUnwrap(report.sections.first { $0.id == "file" }?.fields.first { $0.label == String(localized: "Standard according to metadata") }?.value)
    }
    func testOversizedEncryptionLengthDoesNotCrashAndIsUnknown() throws {
        let report = try inspect("oversized-encryption-length")
        XCTAssertFalse(report.isLocked)
        XCTAssertFalse(report.isComplete)
        XCTAssertTrue(report.notices.contains(String(localized: "The encryption dictionary could not be read completely.")))
        XCTAssertTrue(report.sections.first { $0.id == "encryption" }?.fields.contains { $0.label == String(localized: "Encryption algorithm / key length") && $0.value == PDFInspectionFormat.unknown } == true)
    }
    func testUnreadableXMPIsNotReportedAsAbsentOrComplete() throws {
        let report = try inspect("unreadable-xmp-stream")
        XCTAssertFalse(report.isComplete)
        XCTAssertFalse(report.notices.isEmpty)
        XCTAssertTrue(try standard(report).contains(PDFInspectionFormat.unknown))
        XCTAssertFalse(try standard(report).contains(String(localized: "No standard specified")))
        XCTAssertEqual(
            report.sections.first { $0.id == "file" }?.fields.first {
                $0.label == String(localized: "Standard according to metadata")
            }?.emphasis,
            .warning
        )
        XCTAssertEqual(report.sections.first { $0.id == "xmp" }?.isComplete, false)
    }
    func testUnreadableICCHeaderMarksReportIncomplete() throws {
        let report = try inspect("unreadable-icc-profile")
        XCTAssertFalse(report.isComplete)
        XCTAssertFalse(report.notices.isEmpty)
        XCTAssertEqual(report.sections.first { $0.id.hasPrefix("icc-") }?.isComplete, false)
    }
    func testInvalidICCTagTableAndTagRangeMarkProfileIncomplete() {
        func profile(count: UInt32, offset: UInt32, size: UInt32) -> Data {
            var data = Data(repeating: 0, count: 144)
            func uint(_ index: Int, _ value: UInt32) {
                data.replaceSubrange(index..<index + 4, with: withUnsafeBytes(of: value.bigEndian, Array.init))
            }
            uint(0, 144); data.replaceSubrange(36..<40, with: "acsp".utf8)
            uint(128, count); uint(136, offset); uint(140, size)
            return data
        }
        XCTAssertFalse(PDFICCReader.inspect(profile(count: 4097, offset: 0, size: 8), location: "test").isComplete)
        XCTAssertFalse(PDFICCReader.inspect(profile(count: 1, offset: 140, size: 32), location: "test").isComplete)
    }
    func testFormWithoutResourcesUsesCallingPageFont() throws {
        let report = try inspect("form-inherits-resources")
        XCTAssertTrue(report.isComplete, report.notices.joined(separator: "\n"))
        XCTAssertEqual(report.fontWarnings.map(\.title), ["Helvetica"])
        XCTAssertTrue(report.fontWarnings[0].fields.contains { $0.label == String(localized: "Used on pages") && $0.value == "1" })
    }
    func testUnicodePasswordPreservesBookmarksAndPageLabels() throws {
        for password in ["Päss (\\) € 🔒", "Öwner 🔑"] {
            let report = try inspect("unicode-bookmarks-labels", password: password)
            XCTAssertFalse(report.isLocked)
            XCTAssertTrue(report.isComplete, report.notices.joined(separator: "\n"))
            XCTAssertTrue(report.sections.first { $0.id == "page-1" }?.fields.contains { $0.label == String(localized: "Page label") && $0.value == "A-i" } == true)
            XCTAssertTrue(report.sections.first { $0.id == "outlines" }?.fields.contains { $0.label == "Unicode protected chapter" && $0.value == "A-i" } == true)
        }
    }
    func testDirectDeviceColorOperatorsAreReported() throws {
        let report = try inspect("direct-colors")
        XCTAssertTrue(report.isComplete)
        let spaces = report.sections(in: .colors).flatMap(\.fields).map(\.value)
        for space in ["DeviceRGB", "DeviceCMYK", "DeviceGray"] { XCTAssertTrue(spaces.contains(space), space) }
        XCTAssertNil(report.warningSummary)
    }
    func testXMPPropertiesAreMergedAcrossDescriptionsOfSameSubject() throws {
        XCTAssertEqual(try standard(inspect("xmp-split-description")), "PDF/A-2b (XMP)")
    }
    func testConflictingXMPValuesRemainVisibleWithoutInventedCombinations() throws {
        let report = try inspect("xmp-conflicting-properties")
        let declaration = try standard(report)
        XCTAssertTrue(declaration.contains(String(localized: "Conflicting standard metadata")))
        for value in ["1", "2", "B", "U"] { XCTAssertTrue(declaration.contains(value)) }
        for invented in ["PDF/A-1b", "PDF/A-1u", "PDF/A-2b", "PDF/A-2u"] { XCTAssertFalse(declaration.contains(invented)) }
        XCTAssertEqual(
            report.sections.first { $0.id == "file" }?.fields.first {
                $0.label == String(localized: "Standard according to metadata")
            }?.emphasis,
            .warning
        )
    }
    func testUnrelatedNamespaceDoesNotDeclareAStandard() throws {
        let report = try inspect("xmp-unrelated-namespace")
        XCTAssertTrue(report.isComplete)
        XCTAssertEqual(try standard(report), String(localized: "No standard specified"))
        XCTAssertFalse(report.plainText.contains("PDF/UA-9"))
    }
    func testNamespacesAreExactButTheirPrefixesAreArbitrary() {
        for (uri, key, value, claim) in [
            ("http://www.aiim.org/pdfua/ns/id/", "part", "2", "PDF/UA-2"),
            ("http://www.npes.org/pdfvt/ns/id/", "GTS_PDFVTVersion", "PDF/VT-1", "PDF/VT-1"),
            ("http://www.aiim.org/pdfe/ns/id/", "GTS_PDFEVersion", "PDF/E-1", "PDF/E-1")
        ] {
            func declarations(_ namespace: String) -> [String] {
                PDFXMPReader(data: Data("<r:RDF xmlns:r=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\"><r:Description xmlns:arbitrary=\"\(namespace)\" arbitrary:\(key)=\"\(value)\"/></r:RDF>".utf8)).declarations
            }
            XCTAssertEqual(declarations(uri), [claim])
            XCTAssertTrue(declarations("https://example.org/" + uri).isEmpty)
        }
    }
    func testSeparateRDFSubjectsAndNestedStructuresAreNotCombined() {
        let reader = PDFXMPReader(data: Data("""
        <r:RDF xmlns:r="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns:a="http://www.aiim.org/pdfa/ns/id/" xmlns:custom="urn:test:">
          <r:Description r:about="one" a:part="2"/>
          <r:Description r:about="two" a:conformance="B"/>
          <r:Description r:about="one"><custom:thing><r:Description a:part="9"/></custom:thing></r:Description>
        </r:RDF>
        """.utf8))
        XCTAssertEqual(reader.declarations, ["PDF/A-2"])
    }
    func testType3ImageResolutionIsExplicitlyUnknown() throws {
        let report = try inspect("type3-image-resolution")
        XCTAssertFalse(report.isComplete)
        XCTAssertFalse(report.plainText.contains("7.2 × 7.2 ppi"))
        XCTAssertTrue(report.sections(in: .contents).flatMap(\.fields).contains { $0.label == String(localized: "Effective resolution") && $0.value == String(localized: "Unknown — Type 3 text transformation not evaluated") })
        XCTAssertNil(report.warningSummary)
    }
    func testChildFormFieldInheritsTypeAndPreservesQualifiedNameAndValue() throws {
        let report = try inspect("inherited-field-type")
        XCTAssertTrue(report.isComplete)
        let field = try XCTUnwrap(report.sections(in: .contents).first { $0.title.contains("ParentField.ChildField") })
        XCTAssertTrue(field.fields.contains { $0.value == "Tx" })
        XCTAssertTrue(field.fields.contains { $0.value == "REVIEW-FIELD-VALUE" })
    }
    func testCryptFilterRecipientsAreExcludedFromWholeReport() throws {
        let report = try inspect("cryptfilter-recipient", password: "user-test")
        XCTAssertFalse(report.isLocked)
        XCTAssertTrue(report.isComplete)
        XCTAssertFalse(report.plainText.contains("REVIEW-RECIPIENT-DATA"))
        XCTAssertFalse(report.plainText.contains("/Recipients"))
        XCTAssertTrue(report.plainText.contains("AES-128"))
    }
    func testLowerCatalogVersionCannotLowerEffectivePDFVersion() throws {
        let report = try inspect("version-lower-override")
        let fields = try XCTUnwrap(report.sections.first { $0.id == "file" }?.fields)
        XCTAssertEqual(fields.first { $0.label == String(localized: "PDF version") }?.value, "1.7")
        XCTAssertEqual(fields.first { $0.label == String(localized: "Header version") }?.value, "1.7")
        XCTAssertEqual(fields.first { $0.label == String(localized: "Catalog version") }?.value, "1.4")
    }
    func testManyNoticesHaveOneCollapsibleSectionAndExportEachOnce() throws {
        let report = try inspect("many-incomplete-pages")
        XCTAssertEqual(report.notices.count, 35)
        let section = try XCTUnwrap(report.sections(in: .overview).first { $0.id == "analysis-notices" })
        XCTAssertFalse(section.initiallyExpanded)
        XCTAssertEqual(section.fields.map(\.value), report.notices)
        for notice in report.notices { XCTAssertEqual(report.paragraphs.filter { $0.text == notice }.count, 1) }
        XCTAssertNil(PDFInspectionReport(fileName: "empty.pdf").sections(in: .overview).first { $0.id == "analysis-notices" })
    }
}
