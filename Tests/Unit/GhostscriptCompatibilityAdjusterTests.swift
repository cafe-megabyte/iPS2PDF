import Foundation
import XCTest

final class GhostscriptCompatibilityAdjusterTests: XCTestCase {
    func testTransparencyIsDisabledBelowPDF14() throws {
        let document = try document(
            compatibilityLevel: "1.3",
            entries: "/AllowTransparency true"
        )

        let issues = GhostscriptCompatibilityAdjuster.issues(in: document)
        let adjusted = try GhostscriptCompatibilityAdjuster.adjustedDocument(from: document)

        XCTAssertEqual(issues.map(\.key), ["AllowTransparency"])
        XCTAssertEqual(adjusted.value(forKey: "AllowTransparency")?.boolValue, false)
    }

    func testTransparencyIsKeptForPDF14() throws {
        let document = try document(
            compatibilityLevel: "1.4",
            entries: "/AllowTransparency true"
        )

        XCTAssertTrue(GhostscriptCompatibilityAdjuster.issues(in: document).isEmpty)
        XCTAssertEqual(try GhostscriptCompatibilityAdjuster.adjustedDocument(from: document).data, document.data)
    }

    func testFlateImageFiltersAreChangedForPDF11() throws {
        let document = try document(
            compatibilityLevel: "1.1",
            entries: """
            /ColorImageFilter /FlateEncode
              /GrayImageFilter /FlateEncode
            """
        )

        let issues = GhostscriptCompatibilityAdjuster.issues(in: document)
        let adjusted = try GhostscriptCompatibilityAdjuster.adjustedDocument(from: document)

        XCTAssertEqual(issues.map(\.key), ["ColorImageFilter", "GrayImageFilter"])
        XCTAssertEqual(adjusted.value(forKey: "ColorImageFilter")?.textualValue, "DCTEncode")
        XCTAssertEqual(adjusted.value(forKey: "GrayImageFilter")?.textualValue, "DCTEncode")
    }

    func testFlateImageFiltersAreKeptForPDF12() throws {
        let document = try document(
            compatibilityLevel: "1.2",
            entries: """
            /ColorImageFilter /FlateEncode
              /GrayImageFilter /FlateEncode
            """
        )

        XCTAssertTrue(GhostscriptCompatibilityAdjuster.issues(in: document).isEmpty)
        XCTAssertEqual(try GhostscriptCompatibilityAdjuster.adjustedDocument(from: document).data, document.data)
    }

    func testUnrelatedSettingsArePreserved() throws {
        let document = try document(
            compatibilityLevel: "1.1",
            entries: """
            /Title (Keep me)
              /ColorImageFilter /FlateEncode
              /Untouched [1 true /Name]
            """
        )

        let adjusted = try GhostscriptCompatibilityAdjuster.adjustedDocument(from: document)
        let text = try XCTUnwrap(String(data: adjusted.data, encoding: .utf8))

        XCTAssertTrue(text.contains("/Title (Keep me)"))
        XCTAssertTrue(text.contains("/Untouched [1 true /Name]"))
        XCTAssertEqual(adjusted.value(forKey: "ColorImageFilter")?.textualValue, "DCTEncode")
    }

    private func document(
        compatibilityLevel: String,
        entries: String
    ) throws -> LosslessJoboptionsDocument {
        try LosslessJoboptionsDocument(data: Data("""
        <<
          /CompatibilityLevel \(compatibilityLevel)
          \(entries)
        >> setdistillerparams
        """.utf8))
    }
}
