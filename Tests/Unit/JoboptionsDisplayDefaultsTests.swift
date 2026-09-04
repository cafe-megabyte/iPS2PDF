import Foundation
import XCTest

final class JoboptionsDisplayDefaultsTests: XCTestCase {
    private func document(_ entries: String = "") throws -> LosslessJoboptionsDocument {
        try LosslessJoboptionsDocument(data: Data("% preserved\n<< \(entries) >> setdistillerparams\n".utf8))
    }

    func testMissingSelectionsAndNumbersHaveConcreteDefaultsWithoutWriting() throws {
        let source = try document()
        let original = source.data
        let expected = [
            "iPS2PDFStandard": "none", "CannotEmbedFontPolicy": "Warning",
            "BlendConversionStrategy": "Simple", "ProcessColorModel": "DeviceRGB",
            "EncryptionR": "0", "Permissions": "-4", "PDFACompatibilityPolicy": "0",
            "PDFXTrapped": "False"
        ]
        for (key, value) in expected {
            XCTAssertEqual(JoboptionsConsistencyEngine.displayValue(forKey: key, in: source)?.textualValue, value, key)
        }
        for key in JoboptionsRuntimeDefaults.profileKeys {
            XCTAssertEqual(JoboptionsConsistencyEngine.displayValue(forKey: key, in: source), .string(""), key)
        }
        XCTAssertEqual(source.data, original)
        XCTAssertTrue(source.keys.isEmpty)
        XCTAssertTrue(JoboptionsConsistencyEngine.issues(in: source).isEmpty)
    }

    func testFreeTextRemainsEmptyEvenWhenAStandardProposesMetadata() throws {
        let source = try document("/iPS2PDFStandard /pdfx4")
        for key in ["OwnerPassword", "UserPassword", "PDFXOutputCondition", "PDFXOutputConditionIdentifier", "PDFXRegistryName"] {
            XCTAssertNil(JoboptionsConsistencyEngine.displayValue(forKey: key, in: source), key)
            XCTAssertNil(source.value(forKey: key), key)
        }
        XCTAssertNil(JoboptionsConsistencyEngine.displayValue(forKey: "DSCReportingLevel", in: source))
        XCTAssertTrue(JoboptionsConsistencyEngine.issues(in: source).contains {
            $0.key == "PDFXOutputConditionIdentifier"
        })
    }

    func testMissingStandardDependentSelectionsComeFromTheEngine() throws {
        let pdfa = try document("/iPS2PDFStandard /pdfa2b")
        XCTAssertEqual(JoboptionsConsistencyEngine.displayValue(forKey: "PDFACompatibilityPolicy", in: pdfa)?.numberValue, 1)
        XCTAssertEqual(JoboptionsConsistencyEngine.displayValue(forKey: "OutputICCProfile", in: pdfa)?.textualValue, "sRGB Profile")
        XCTAssertEqual(JoboptionsConsistencyEngine.displayValue(forKey: "ProcessColorModel", in: pdfa)?.textualValue, "DeviceRGB")
        let pdfx = try document("/iPS2PDFStandard /pdfx4")
        XCTAssertEqual(JoboptionsConsistencyEngine.displayValue(forKey: "PDFXOutputIntentProfile", in: pdfx)?.textualValue, "Generic CMYK Profile")
        XCTAssertEqual(JoboptionsConsistencyEngine.displayValue(forKey: "ProcessColorModel", in: pdfx)?.textualValue, "DeviceCMYK")
        XCTAssertNil(pdfa.value(forKey: "OutputICCProfile"))
        XCTAssertNil(pdfx.value(forKey: "PDFXOutputIntentProfile"))
    }

    func testStoredSelectionsAreNotMaskedByRepairs() throws {
        let source = try document("/iPS2PDFStandard /pdfa2b /PDFACompatibilityPolicy 0 /OutputICCProfile () /BlendConversionStrategy /ImportedValue")
        XCTAssertEqual(JoboptionsConsistencyEngine.displayValue(forKey: "PDFACompatibilityPolicy", in: source)?.numberValue, 0)
        XCTAssertEqual(JoboptionsConsistencyEngine.displayValue(forKey: "OutputICCProfile", in: source), .string(""))
        XCTAssertEqual(JoboptionsConsistencyEngine.displayValue(forKey: "BlendConversionStrategy", in: source), .name("ImportedValue"))
        let effective = try JoboptionsConsistencyEngine.effectiveDocument(from: source)
        XCTAssertEqual(effective.value(forKey: "PDFACompatibilityPolicy")?.numberValue, 1)
        XCTAssertEqual(effective.value(forKey: "BlendConversionStrategy"), .name("Simple"))
        XCTAssertTrue(JoboptionsConsistencyEngine.issues(in: effective).isEmpty)
    }

    func testExplicitPDFAPoliciesRemainSelectable() throws {
        for policy in [1, 2] {
            let source = try document("/iPS2PDFStandard /pdfa2b /PDFACompatibilityPolicy \(policy)")
            let effective = try JoboptionsConsistencyEngine.effectiveDocument(from: source)
            XCTAssertEqual(effective.value(forKey: "PDFACompatibilityPolicy")?.numberValue, Double(policy))
        }
    }

    func testProfileNoneSpellingsAreReadWithoutRewriting() throws {
        for spelling in ["()", "(None)", "/None", "( none )"] {
            let source = try document("/OutputICCProfile \(spelling)")
            let original = source.data
            XCTAssertEqual(JoboptionsRuntimeDefaults.profileSelection(source.value(forKey: "OutputICCProfile")), "")
            XCTAssertEqual(source.data, original)
        }
    }

    func testFirstEditAndClearKeepExplicitKeys() throws {
        let source = try document()
        let selected = try source.replacingValue(forKey: "OutputICCProfile", with: .string("sRGB Profile"))
        let cleared = try selected.replacingValue(forKey: "OutputICCProfile", with: .string(""))
            .replacingValue(forKey: "PDFXRegistryName", with: .string(""))
            .replacingValue(forKey: "iPS2PDFStandard", with: .name("none"))
        let reopened = try LosslessJoboptionsDocument(data: cleared.data)
        XCTAssertEqual(reopened.value(forKey: "OutputICCProfile"), .string(""))
        XCTAssertEqual(reopened.value(forKey: "PDFXRegistryName"), .string(""))
        XCTAssertEqual(reopened.value(forKey: "iPS2PDFStandard"), .name("none"))
    }

    func testDeviceParametersUseTheirOwnOperatorWithoutChangingSource() throws {
        let source = try document("/PDFACompatibilityPolicy 2 /BlendConversionStrategy /Managed /ProcessColorModel /DeviceCMYK /DSCReportingLevel 2 /EmbedOpenType true")
        let original = source.data
        let program = JoboptionsDeviceParameters.program(in: source)
        XCTAssertTrue(program.contains("/PDFACompatibilityPolicy 2"))
        XCTAssertTrue(program.contains("/BlendConversionStrategy /Managed"))
        XCTAssertTrue(program.contains("/ProcessColorModel /DeviceCMYK"))
        XCTAssertTrue(program.contains(">> setpagedevice"))
        XCTAssertFalse(program.contains("DSCReportingLevel"))
        XCTAssertFalse(program.contains("EmbedOpenType"))
        let runtime = try JoboptionsDeviceParameters.runtimeData(in: source)
        XCTAssertTrue(runtime.starts(with: original))
        XCTAssertEqual(source.data, original)
    }

    func testEncryptionConsistencyIsHandledWithoutAnEditor() throws {
        let disabled = try document("/Encrypt false /OwnerPassword (owner) /UserPassword (user)")
        let effective = try JoboptionsConsistencyEngine.effectiveDocument(from: disabled)
        XCTAssertEqual(effective.value(forKey: "OwnerPassword"), .string(""))
        XCTAssertEqual(effective.value(forKey: "UserPassword"), .string(""))
        XCTAssertEqual(disabled.value(forKey: "UserPassword"), .string("user"))
        let missingPassword = try document("/Encrypt true")
        XCTAssertEqual(try JoboptionsConsistencyEngine.effectiveDocument(from: missingPassword).value(forKey: "Encrypt"), .boolean(false))
    }

    func testIncompatibleDeviceProfilesAreRepairedByEngineOnly() throws {
        let source = try document("/ColorConversionStrategy /CMYK /TextICCProfile (RGB Profile)")
        let context = JoboptionsConsistencyContext(availableProfiles: [
            .init(name: "RGB Profile", colorSpace: "RGB", profileClass: "mntr")
        ])
        let effective = try JoboptionsConsistencyEngine.effectiveDocument(from: source, context: context)
        XCTAssertEqual(effective.value(forKey: "TextICCProfile"), .string(""))
        XCTAssertEqual(JoboptionsConsistencyEngine.displayValue(forKey: "TextICCProfile", in: source, context: context), .string("RGB Profile"))
    }

    func testInvalidImportedEncryptionParametersAreRepairedIdempotently() throws {
        for permissions in ["0", "1e99", "-1e99"] {
            let source = try document("/Encrypt true /UserPassword (test) /EncryptionR 3 /CompatibilityLevel 1.3 /Permissions \(permissions)")
            let effective = try JoboptionsConsistencyEngine.effectiveDocument(from: source)
            XCTAssertEqual(effective.value(forKey: "EncryptionR")?.numberValue, 0)
            XCTAssertTrue(JoboptionsConsistencyEngine.issues(in: effective).isEmpty)
        }
    }

    func testMissingPDFXOffsetsUseZeroWithoutCreatingKeys() throws {
        let source = try document("/PDFXNoTrimBoxError false /PDFXSetBleedBoxToMediaBox false")
        let rules = SemanticJoboptions.pdfXBoxRules(in: source)
        XCTAssertEqual(rules.trim, .mediaBox(offsets: [0, 0, 0, 0]))
        XCTAssertEqual(rules.bleed, .trimBox(offsets: [0, 0, 0, 0]))
        XCTAssertNil(source.value(forKey: "PDFXTrimBoxToMediaBoxOffset"))
        XCTAssertNil(source.value(forKey: "PDFXBleedBoxToTrimBoxOffset"))
        let pdfx = try document("/iPS2PDFStandard /pdfx4")
        XCTAssertEqual(JoboptionsConsistencyEngine.pdfXBoxRulesForDisplay(in: pdfx).trim, .mediaBox(offsets: [0, 0, 0, 0]))
        XCTAssertNil(pdfx.value(forKey: "PDFXNoTrimBoxError"))
    }

    func testResolvableProfileAliasesAreNotRepairedAway() throws {
        let source = try document("/OutputICCProfile (sRGB IEC61966-2.1) /TextICCProfile ( srgb profile )")
        let context = JoboptionsConsistencyContext(availableProfiles: [
            .init(name: "sRGB Profile", colorSpace: "RGB", profileClass: "mntr")
        ])
        XCTAssertTrue(JoboptionsConsistencyEngine.issues(in: source, context: context).isEmpty)
        XCTAssertEqual(try JoboptionsConsistencyEngine.effectiveDocument(from: source, context: context).data, source.data)
    }
}
