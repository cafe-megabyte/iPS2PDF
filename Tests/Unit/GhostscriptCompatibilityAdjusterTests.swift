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

    func testStandardRulesAreProposedWithoutChangingTheStoredDocument() throws {
        let document = try LosslessJoboptionsDocument(data: Data("""
        <<
          /iPS2PDFStandard /pdfa1b
          /CompatibilityLevel 1.1
          /EmbedAllFonts false
          /CannotEmbedFontPolicy /Warning
          /Encrypt true
          /EncryptionR 4
          /OwnerPassword (owner)
          /UserPassword (user)
          /Permissions -44
          /PDFX1aCheck true
          /PDFX3Check true
          /ColorConversionStrategy /CMYK
          /OutputICCProfile (Missing)
          /AllowTransparency true
        >> setdistillerparams
        """.utf8))
        let original = document.data
        let context = JoboptionsConsistencyContext(
            availableProfiles: [.init(name: "sRGB Profile", colorSpace: "RGB")]
        )

        let issues = JoboptionsConsistencyEngine.issues(in: document, context: context)

        XCTAssertEqual(document.data, original)
        XCTAssertEqual(issues.first?.path.description, "/CompatibilityLevel")
        XCTAssertTrue(issues.allSatisfy(\.isAutomaticallyRepairable))
        XCTAssertFalse(issues.contains { $0.path.description == "/AllowTransparency" })

        let effective = try JoboptionsConsistencyEngine.effectiveDocument(from: document, context: context)
        XCTAssertEqual(effective.value(forKey: "CompatibilityLevel")?.textualValue, "1.4")
        XCTAssertEqual(effective.value(forKey: "EmbedAllFonts")?.boolValue, true)
        XCTAssertEqual(effective.value(forKey: "Encrypt")?.boolValue, false)
        XCTAssertEqual(effective.value(forKey: "OutputICCProfile")?.textualValue, "sRGB Profile")
        XCTAssertEqual(effective.value(forKey: "AllowTransparency")?.boolValue, true)
        XCTAssertEqual(document.data, original)
    }

    func testPDFXWithoutSelectedCMYKProfileUsesDefaultGenericCMYKProfile() throws {
        let document = try LosslessJoboptionsDocument(data: Data("""
        << /iPS2PDFStandard /pdfx1 /CompatibilityLevel 1.4 /PDFXOutputIntentProfile () >> setdistillerparams
        """.utf8))
        let context = JoboptionsConsistencyContext(
            availableProfiles: [
                .init(name: "Profile A", colorSpace: "CMYK"),
                .init(name: "Generic CMYK Profile", fileStem: "Generic CMYK Profile", colorSpace: "CMYK")
            ]
        )

        let issues = JoboptionsConsistencyEngine.issues(in: document, context: context)
        let profileIssue = try XCTUnwrap(
            issues.first { $0.path.description == "/PDFXOutputIntentProfile" }
        )
        XCTAssertTrue(profileIssue.isAutomaticallyRepairable)
        XCTAssertEqual(profileIssue.proposedValue?.textualValue, "Generic CMYK Profile")

        let effective = try JoboptionsConsistencyEngine.effectiveDocument(from: document, context: context)
        XCTAssertEqual(effective.value(forKey: "PDFXOutputIntentProfile")?.textualValue, "Generic CMYK Profile")
    }

    func testPDFXWithoutGenericCMYKProfileRemainsUnresolved() throws {
        let document = try LosslessJoboptionsDocument(data: Data("""
        << /iPS2PDFStandard /pdfx1 /CompatibilityLevel 1.4 /PDFXOutputIntentProfile () >> setdistillerparams
        """.utf8))
        let context = JoboptionsConsistencyContext(
            availableProfiles: [.init(name: "Profile A", colorSpace: "CMYK")]
        )

        let issues = JoboptionsConsistencyEngine.issues(in: document, context: context)
        let profileIssue = try XCTUnwrap(
            issues.first { $0.path.description == "/PDFXOutputIntentProfile" }
        )
        XCTAssertFalse(profileIssue.isAutomaticallyRepairable)
        XCTAssertNil(profileIssue.proposedValue)
    }

    func testPDFX1DisablesTransparencyWhenProfileIsSelected() throws {
        let document = try LosslessJoboptionsDocument(data: Data("""
        <<
          /iPS2PDFStandard /pdfx1
          /CompatibilityLevel 1.7
          /AllowTransparency true
          /ColorConversionStrategy /LeaveColorUnchanged
          /PDFXOutputIntentProfile (Coated FOGRA27)
        >> setdistillerparams
        """.utf8))
        let context = JoboptionsConsistencyContext(
            availableProfiles: [
                .init(name: "Coated FOGRA27", fileStem: "CoatedFOGRA27", colorSpace: "CMYK")
            ]
        )

        let effective = try JoboptionsConsistencyEngine.effectiveDocument(from: document, context: context)

        XCTAssertEqual(effective.value(forKey: "CompatibilityLevel")?.textualValue, "1.4")
        XCTAssertEqual(effective.value(forKey: "AllowTransparency")?.boolValue, false)
        XCTAssertEqual(effective.value(forKey: "ColorConversionStrategy")?.textualValue, "CMYK")
        XCTAssertEqual(effective.value(forKey: "PDFXOutputIntentProfile")?.textualValue, "Coated FOGRA27")
    }

    func testPDFA1DisablesTransparencyFromNormalProfile() throws {
        let document = try LosslessJoboptionsDocument(data: Data("""
        <<
          /iPS2PDFStandard /pdfa1b
          /CompatibilityLevel 1.7
          /AllowTransparency true
          /OutputICCProfile (Missing)
        >> setdistillerparams
        """.utf8))
        let context = JoboptionsConsistencyContext(
            availableProfiles: [.init(name: "sRGB Profile", colorSpace: "RGB")]
        )

        let effective = try JoboptionsConsistencyEngine.effectiveDocument(from: document, context: context)

        XCTAssertEqual(effective.value(forKey: "CompatibilityLevel")?.textualValue, "1.4")
        XCTAssertEqual(effective.value(forKey: "AllowTransparency")?.boolValue, false)
        XCTAssertEqual(effective.value(forKey: "OutputICCProfile")?.textualValue, "sRGB Profile")
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
