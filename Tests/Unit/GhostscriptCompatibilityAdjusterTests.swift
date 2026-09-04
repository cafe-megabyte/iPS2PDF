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

    func testIgnoredEmbedOpenTypeValueSurvivesConsistencyProcessing() throws {
        let document = try LosslessJoboptionsDocument(data: Data("""
        <<
          /iPS2PDFStandard /pdfa1b
          /CompatibilityLevel 1.1
          /EmbedOpenType false
        >> setdistillerparams
        """.utf8))

        let effective = try JoboptionsConsistencyEngine.effectiveDocument(from: document)

        XCTAssertEqual(effective.value(forKey: "EmbedOpenType")?.boolValue, false)
        XCTAssertTrue(effective.sourceText.contains("/EmbedOpenType false"))
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
        XCTAssertTrue(issues.contains { $0.path.description == "/AllowTransparency" })

        let effective = try JoboptionsConsistencyEngine.effectiveDocument(from: document, context: context)
        XCTAssertEqual(effective.value(forKey: "CompatibilityLevel")?.textualValue, "1.4")
        XCTAssertEqual(effective.value(forKey: "EmbedAllFonts")?.boolValue, true)
        XCTAssertEqual(effective.value(forKey: "Encrypt")?.boolValue, false)
        XCTAssertEqual(effective.value(forKey: "OutputICCProfile")?.textualValue, "sRGB Profile")
        XCTAssertEqual(effective.value(forKey: "AllowTransparency")?.boolValue, false)
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
        XCTAssertEqual(profileIssue.proposedValue.textualValue, "Generic CMYK Profile")

        let effective = try JoboptionsConsistencyEngine.effectiveDocument(from: document, context: context)
        XCTAssertEqual(effective.value(forKey: "PDFXOutputIntentProfile")?.textualValue, "Generic CMYK Profile")
    }

    func testPDFXWithoutDiscoverableGenericCMYKProfileStillUsesBundledDefault() throws {
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
        XCTAssertEqual(
            profileIssue.proposedValue.textualValue,
            SemanticJoboptions.defaultPDFXOutputIntentProfile
        )
        XCTAssertNoThrow(
            try JoboptionsConsistencyEngine.effectiveDocument(from: document, context: context)
        )
    }

    func testIncompleteCompoundSettingsReceiveDeterministicRepairs() throws {
        let document = try LosslessJoboptionsDocument(data: Data("""
        <<
          /iPS2PDFStandard /pdfx4
          /CompatibilityLevel 1.7
          /PDFXOutputIntentProfile (Generic CMYK Profile)
          /StartPage 9
          /EndPage 3
          /HWResolution [2400]
          /PageSize [0 842]
          /DownsampleColorImages true
          /ColorImageDownsampleType /VendorMode
          /ColorImageResolution 300
          /ColorImageDownsampleThreshold 1.5
          /EncodeGrayImages true
          /AutoFilterGrayImages false
          /GrayImageFilter /DCTEncode
          /GrayImageDict << >>
          /MonoImageMinResolution /Invalid
          /MonoImageMinResolutionPolicy /VendorPolicy
          /AntiAliasMonoImages true
          /MonoImageDepth 3
          /PDFXNoTrimBoxError false
          /PDFXTrimBoxToMediaBoxOffset [0 0]
          /PDFXSetBleedBoxToMediaBox false
          /PDFXBleedBoxToTrimBoxOffset [0 0]
          /VendorSetting (preserved)
        >> setdistillerparams
        """.utf8))

        let issues = JoboptionsConsistencyEngine.issues(in: document)
        let effective = try JoboptionsConsistencyEngine.effectiveDocument(from: document)

        XCTAssertFalse(issues.isEmpty)
        XCTAssertEqual(effective.value(forKey: "StartPage")?.numberValue, 1)
        XCTAssertEqual(effective.value(forKey: "EndPage")?.numberValue, -1)
        XCTAssertEqual(effective.value(forKey: "HWResolution")?.postScript, "[2400 2400]")
        XCTAssertEqual(effective.value(forKey: "PageSize")?.postScript, "[595.276 841.89]")
        XCTAssertEqual(effective.value(forKey: "DownsampleColorImages")?.boolValue, false)
        XCTAssertEqual(effective.value(forPath: "/GrayImageDict /QFactor")?.numberValue, 0.76)
        XCTAssertEqual(effective.value(forKey: "MonoImageMinResolution")?.numberValue, 1_200)
        XCTAssertEqual(effective.value(forKey: "MonoImageMinResolutionPolicy")?.textualValue, "OK")
        XCTAssertEqual(effective.value(forKey: "AntiAliasMonoImages")?.boolValue, false)
        XCTAssertEqual(effective.value(forKey: "PDFXNoTrimBoxError")?.boolValue, false)
        XCTAssertEqual(effective.value(forKey: "PDFXTrimBoxToMediaBoxOffset")?.postScript, "[0 0 0 0]")
        XCTAssertEqual(effective.value(forKey: "PDFXSetBleedBoxToMediaBox")?.boolValue, true)
        XCTAssertEqual(effective.value(forKey: "VendorSetting")?.textualValue, "preserved")
    }

    func testInactiveCompanionValuesArePreserved() throws {
        let document = try LosslessJoboptionsDocument(data: Data("""
        <<
          /DownsampleColorImages false
          /ColorImageDownsampleType /VendorMode
          /ColorImageResolution /Invalid
          /ColorImageDownsampleThreshold /Invalid
          /EncodeColorImages false
          /ColorImageFilter /VendorFilter
          /ColorACSImageDict << /QFactor /Invalid >>
          /ColorImageDict << /QFactor /Invalid >>
          /AntiAliasMonoImages false
          /MonoImageDepth 3
        >> setdistillerparams
        """.utf8))

        let effective = try JoboptionsConsistencyEngine.effectiveDocument(from: document)

        XCTAssertEqual(effective.data, document.data)
    }

    func testAutomaticRepairCreatesMissingActiveQualityDictionary() throws {
        let document = try LosslessJoboptionsDocument(data: Data("""
        <<
          /EncodeColorImages true
          /AutoFilterColorImages true
          /ColorImageFilter /DCTEncode
        >> setdistillerparams
        """.utf8))

        let effective = try JoboptionsConsistencyEngine.effectiveDocument(from: document)

        XCTAssertEqual(effective.value(forPath: "/ColorACSImageDict /QFactor")?.numberValue, 0.40)
    }

    func testIssueIndexTracksAffectedPaths() throws {
        let document = try LosslessJoboptionsDocument(data: Data("""
        << /StartPage 5 /EndPage 2 >> setdistillerparams
        """.utf8))
        let index = JoboptionsConsistencyIssueIndex(
            JoboptionsConsistencyEngine.issues(in: document)
        )

        XCTAssertTrue(index.affects(JoboptionsKeyPath("/StartPage")))
        XCTAssertTrue(index.affects(any: [JoboptionsKeyPath("/Unrelated"), JoboptionsKeyPath("/EndPage")]))
        XCTAssertFalse(index.affects(JoboptionsKeyPath("/Unrelated")))
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

    func testPDFXForcesEmbeddingMappedIdentifierAndValidTrappedState() throws {
        let document = try LosslessJoboptionsDocument(data: Data("""
        <<
          /iPS2PDFStandard /pdfx4
          /CompatibilityLevel 1.6
          /PDFXOutputIntentProfile (PSO Coated v3)
          /PDFXOutputConditionIdentifier (Wrong)
          /PDFXTrapped /Unknown
          /iPS2PDFEmbedOutputIntentProfile false
        >> setdistillerparams
        """.utf8))
        let original = document.data
        let context = JoboptionsConsistencyContext(
            availableProfiles: [
                .init(
                    name: "PSO Coated v3",
                    fileStem: "PSOcoated_v3",
                    colorSpace: "CMYK",
                    profileClass: "prtr",
                    outputConditionIdentifier: "FOGRA51"
                )
            ]
        )

        let issues = JoboptionsConsistencyEngine.issues(in: document, context: context)
        let effective = try JoboptionsConsistencyEngine.effectiveDocument(
            from: document,
            context: context
        )

        XCTAssertTrue(issues.contains {
            $0.path.description == "/iPS2PDFEmbedOutputIntentProfile"
                && $0.proposedValue.boolValue == true
        })
        XCTAssertTrue(issues.contains {
            $0.path.description == "/PDFXOutputConditionIdentifier"
                && $0.proposedValue.textualValue == "FOGRA51"
        })
        XCTAssertTrue(issues.contains {
            $0.path.description == "/PDFXTrapped"
                && $0.proposedValue.textualValue == "False"
        })
        XCTAssertEqual(
            effective.value(forKey: "iPS2PDFEmbedOutputIntentProfile")?.boolValue,
            true
        )
        XCTAssertEqual(
            effective.value(forKey: "PDFXOutputConditionIdentifier")?.textualValue,
            "FOGRA51"
        )
        XCTAssertEqual(effective.value(forKey: "PDFXTrapped")?.textualValue, "False")
        XCTAssertEqual(document.data, original)
    }

    func testPDFXPreservesManualIdentifierForUnmappedProfile() throws {
        let document = try LosslessJoboptionsDocument(data: Data("""
        <<
          /iPS2PDFStandard /pdfx4
          /CompatibilityLevel 1.6
          /PDFXOutputIntentProfile (My Press Profile)
          /PDFXOutputConditionIdentifier (My registered condition)
          /PDFXTrapped /True
          /iPS2PDFEmbedOutputIntentProfile false
        >> setdistillerparams
        """.utf8))
        let context = JoboptionsConsistencyContext(
            availableProfiles: [
                .init(
                    name: "My Press Profile",
                    colorSpace: "CMYK",
                    profileClass: "prtr"
                )
            ]
        )

        let effective = try JoboptionsConsistencyEngine.effectiveDocument(
            from: document,
            context: context
        )

        XCTAssertEqual(
            effective.value(forKey: "PDFXOutputConditionIdentifier")?.textualValue,
            "My registered condition"
        )
        XCTAssertEqual(effective.value(forKey: "PDFXTrapped")?.textualValue, "True")
        XCTAssertEqual(
            effective.value(forKey: "iPS2PDFEmbedOutputIntentProfile")?.boolValue,
            true
        )
    }

    func testPDFXUsesCustomForUnmappedProfileWithoutManualIdentifier() throws {
        let document = try LosslessJoboptionsDocument(data: Data("""
        <<
          /iPS2PDFStandard /pdfx4
          /CompatibilityLevel 1.6
          /PDFXOutputIntentProfile (Generic CMYK Profile)
          /PDFXOutputConditionIdentifier ()
          /PDFXTrapped /False
        >> setdistillerparams
        """.utf8))
        let context = JoboptionsConsistencyContext(
            availableProfiles: [
                .init(
                    name: "Generic CMYK Profile",
                    colorSpace: "CMYK",
                    profileClass: "prtr"
                )
            ]
        )

        let effective = try JoboptionsConsistencyEngine.effectiveDocument(
            from: document,
            context: context
        )

        XCTAssertEqual(
            effective.value(forKey: "PDFXOutputConditionIdentifier")?.textualValue,
            "Custom"
        )
    }

    func testMissingOutputIntentProfileMakesEmbeddingEffectivelyOff() throws {
        let document = try LosslessJoboptionsDocument(data: Data("""
        <<
          /iPS2PDFStandard /none
          /PDFXOutputIntentProfile /None
          /iPS2PDFEmbedOutputIntentProfile true
        >> setdistillerparams
        """.utf8))

        let effective = try JoboptionsConsistencyEngine.effectiveDocument(from: document)

        XCTAssertEqual(
            effective.value(forKey: "iPS2PDFEmbedOutputIntentProfile")?.boolValue,
            false
        )
        XCTAssertEqual(
            document.value(forKey: "iPS2PDFEmbedOutputIntentProfile")?.boolValue,
            true
        )
    }

    func testNormalPDFRecognizesSelectedOutputIntentProfile() throws {
        let document = try LosslessJoboptionsDocument(data: Data("""
        <<
          /iPS2PDFStandard /none
          /PDFXOutputIntentProfile (PSOcoated_v3)
          /iPS2PDFEmbedOutputIntentProfile true
        >> setdistillerparams
        """.utf8))

        let issues = JoboptionsConsistencyEngine.issues(in: document)
        let effective = try JoboptionsConsistencyEngine.effectiveDocument(from: document)

        XCTAssertFalse(issues.contains {
            $0.path.description == "/iPS2PDFEmbedOutputIntentProfile"
        })
        XCTAssertEqual(
            effective.value(forKey: "iPS2PDFEmbedOutputIntentProfile")?.boolValue,
            true
        )
    }

    func testPDFAMayFreelyEmbedOrNotEmbedSelectedOutputProfile() throws {
        let context = JoboptionsConsistencyContext(
            availableProfiles: [.init(name: "sRGB Profile", colorSpace: "RGB")]
        )
        for expected in [false, true] {
            let document = try LosslessJoboptionsDocument(data: Data("""
            <<
              /iPS2PDFStandard /pdfa2b
              /CompatibilityLevel 1.7
              /OutputICCProfile (sRGB Profile)
              /PDFXOutputIntentProfile (sRGB Profile)
              /iPS2PDFEmbedOutputIntentProfile \(expected)
            >> setdistillerparams
            """.utf8))

            let effective = try JoboptionsConsistencyEngine.effectiveDocument(
                from: document,
                context: context
            )

            XCTAssertEqual(
                effective.value(forKey: "iPS2PDFEmbedOutputIntentProfile")?.boolValue,
                expected
            )
        }
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
