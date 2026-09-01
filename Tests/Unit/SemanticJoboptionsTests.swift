import Foundation
import XCTest

final class SemanticJoboptionsTests: XCTestCase {
    func testLocalizedDescriptionChangesOnlyTheRequestedLanguage() throws {
        let original = Data("<< /Description << /ENU <FEFF0045006E0067006C006900730068> /DEU <FEFF0044006500750074007300630068> /JPN <FEFF65E5672C> >> >> setdistillerparams\n".utf8)
        let document = try LosslessJoboptionsDocument(data: original)

        XCTAssertEqual(SemanticJoboptions.description(in: document, languageCode: "de"), "Deutsch")
        let changes = SemanticJoboptions.changeDescription(
            to: "Neu",
            in: document,
            languageCode: "de"
        )
        XCTAssertEqual(changes.paths.map(\.description), ["/Description /DEU"])

        let edited = try changes.applying(to: document)
        XCTAssertEqual(edited.value(forPath: "/Description /DEU")?.textualValue, "Neu")
        XCTAssertEqual(edited.value(forPath: "/Description /ENU")?.textualValue, "English")
        XCTAssertTrue(edited.sourceText.contains("/JPN <FEFF65E5672C>"))
    }

    func testMissingDescriptionIsCreatedAsNeutralLiteralString() throws {
        let document = try makeDocument("/Flag true")
        let changes = SemanticJoboptions.changeDescription(
            to: "Neutral",
            in: document,
            languageCode: "de"
        )

        XCTAssertEqual(changes.paths.map(\.description), ["/Description"])
        let edited = try changes.applying(to: document)
        XCTAssertEqual(edited.value(forKey: "Description")?.textualValue, "Neutral")
        XCTAssertTrue(edited.sourceText.contains("/Description (Neutral)"))
    }

    func testPageRangeActionHasOnlyTwoIntentionalChanges() throws {
        let changes = SemanticJoboptions.changePageSelection(.range(start: 3, end: 8))
        XCTAssertEqual(changes.paths.map(\.description), ["/StartPage", "/EndPage"])

        let edited = try changes.applying(to: makeDocument("/StartPage 1 /EndPage -1 /Keep true"))
        XCTAssertEqual(edited.value(forKey: "StartPage")?.numberValue, 3)
        XCTAssertEqual(edited.value(forKey: "EndPage")?.numberValue, 8)
        XCTAssertEqual(edited.value(forKey: "Keep")?.boolValue, true)
    }

    func testResolutionAndPageSizeRoundTripArrays() throws {
        let document = try makeDocument("/HWResolution [300 600] /PageSize [612 792]")
        XCTAssertEqual(
            SemanticJoboptions.deviceResolution(in: document),
            .init(x: 300, y: 600)
        )
        XCTAssertEqual(
            SemanticJoboptions.pageSize(in: document),
            .init(widthInPoints: 612, heightInPoints: 792)
        )

        let resolution = SemanticJoboptions.changeDeviceResolution(x: 1_200, y: 600)
        XCTAssertEqual(resolution.paths.map(\.description), ["/HWResolution"])
        let resized = try resolution.applying(to: document)
        XCTAssertEqual(
            SemanticJoboptions.deviceResolution(in: resized),
            .init(x: 1_200, y: 600)
        )

        let pageSize = SemanticJoboptions.changePageSize(width: 210, height: 297, unit: .millimeters)
        XCTAssertEqual(pageSize.paths.map(\.description), ["/PageSize"])
        let page = try pageSize.applying(to: resized)
        let size = try XCTUnwrap(SemanticJoboptions.pageSize(in: page))
        XCTAssertEqual(size.widthInPoints, 595.276, accuracy: 0.01)
        XCTAssertEqual(size.heightInPoints, 841.89, accuracy: 0.001)
    }

    func testDownsamplingReaderAndChangesPreserveCustomValuesUntilApply() throws {
        let custom = try makeDocument("""
        /DownsampleGrayImages true
        /GrayImageDownsampleType /VendorMode
        /GrayImageResolution 444
        /GrayImageDownsampleThreshold 1.7
        """)
        let original = custom.data
        XCTAssertEqual(SemanticJoboptions.downsampling(in: custom, kind: .grayscale), .custom)
        XCTAssertEqual(custom.data, original)

        let disabled = SemanticJoboptions.changeDownsampling(
            kind: .grayscale,
            enabled: false,
            mode: .bicubic,
            resolution: 300,
            threshold: 1.5
        )
        XCTAssertEqual(disabled.paths.map(\.description), ["/DownsampleGrayImages"])

        let configured = SemanticJoboptions.changeDownsampling(
            kind: .grayscale,
            enabled: true,
            mode: .average,
            resolution: 200,
            threshold: 1.5
        )
        XCTAssertEqual(
            configured.paths.map(\.description),
            [
                "/DownsampleGrayImages", "/GrayImageDownsampleType",
                "/GrayImageResolution", "/GrayImageDownsampleThreshold"
            ]
        )
        let edited = try configured.applying(to: custom)
        XCTAssertEqual(
            SemanticJoboptions.downsampling(in: edited, kind: .grayscale),
            .configured(mode: .average, resolution: 200, threshold: 1.5)
        )
    }

    func testCompressionQualityChangesOnlyDocumentedNestedPaths() throws {
        let document = try makeDocument("""
        /EncodeColorImages false
        /AutoFilterColorImages false
        /ColorImageFilter /FlateEncode
        /ColorACSImageDict << /QFactor 0.15 /Keep 1 >>
        /ColorImageDict << /QFactor 0.15 /Keep 2 >>
        """)
        let changes = SemanticJoboptions.changeCompression(
            kind: .color,
            compression: .automaticJPEG,
            quality: .medium
        )

        XCTAssertEqual(
            changes.paths.map(\.description),
            [
                "/EncodeColorImages", "/AutoFilterColorImages", "/ColorImageFilter",
                "/ColorACSImageDict /QFactor"
            ]
        )
        let edited = try changes.applying(to: document)
        XCTAssertEqual(edited.value(forPath: "/ColorACSImageDict /QFactor")?.numberValue, 0.76)
        XCTAssertEqual(edited.value(forPath: "/ColorImageDict /QFactor")?.numberValue, 0.15)
        XCTAssertEqual(edited.value(forPath: "/ColorACSImageDict /Keep")?.numberValue, 1)
        XCTAssertEqual(edited.value(forPath: "/ColorImageDict /Keep")?.numberValue, 2)
        XCTAssertEqual(
            SemanticJoboptions.imageCompression(in: edited, kind: .color),
            .init(compression: .automaticJPEG, quality: .medium)
        )
    }

    func testCompressionReadsAndWritesOnlyTheActiveQualityDictionary() throws {
        let document = try makeDocument("""
        /EncodeColorImages true
        /AutoFilterColorImages false
        /ColorImageFilter /DCTEncode
        /ColorACSImageDict << /QFactor 0.40 >>
        /ColorImageDict << /QFactor 0.76 >>
        /JPEG2000ColorImageDict << /Quality 15 >>
        """)

        XCTAssertEqual(
            SemanticJoboptions.imageCompression(in: document, kind: .color),
            .init(compression: .jpeg, quality: .medium)
        )
        let automatic = try SemanticJoboptions.changeCompression(
            kind: .color,
            compression: .automaticJPEG,
            quality: .high
        ).applying(to: document)
        XCTAssertEqual(automatic.value(forPath: "/ColorACSImageDict /QFactor")?.numberValue, 0.40)
        XCTAssertEqual(automatic.value(forPath: "/ColorImageDict /QFactor")?.numberValue, 0.76)
        XCTAssertEqual(
            SemanticJoboptions.imageCompression(in: automatic, kind: .color),
            .init(compression: .automaticJPEG, quality: .high)
        )

        let jpeg2000 = try SemanticJoboptions.changeCompression(
            kind: .color,
            compression: .jpeg2000
        ).applying(to: document)
        XCTAssertEqual(
            SemanticJoboptions.imageCompression(in: jpeg2000, kind: .color),
            .init(compression: .jpeg2000, quality: .custom(15))
        )
    }

    func testImagePolicyMonoSmoothingAndOverrideMappings() throws {
        let document = try makeDocument("""
        /MonoImageMinResolution 600
        /MonoImageMinResolutionPolicy /Warning
        /AntiAliasMonoImages true
        /MonoImageDepth 4
        /LockDistillerParams true
        """)
        XCTAssertEqual(
            SemanticJoboptions.imagePolicy(in: document, kind: .monochrome),
            .init(minimumResolution: 600, policy: .warn)
        )
        XCTAssertEqual(SemanticJoboptions.monoSmoothing(in: document), .depth(4))
        XCTAssertFalse(SemanticJoboptions.allowsDistillerOverrides(in: document))

        let policy = SemanticJoboptions.changeImagePolicy(
            kind: .monochrome,
            minimumResolution: 900,
            policy: .error
        )
        XCTAssertEqual(
            policy.paths.map(\.description),
            ["/MonoImageMinResolution", "/MonoImageMinResolutionPolicy"]
        )
        let smoothing = SemanticJoboptions.changeMonoSmoothing(.off)
        XCTAssertEqual(smoothing.paths.map(\.description), ["/AntiAliasMonoImages"])
        let overrides = SemanticJoboptions.changeAllowsDistillerOverrides(true)
        XCTAssertEqual(overrides.paths.map(\.description), ["/LockDistillerParams"])
        let edited = try overrides.applying(to: document)
        XCTAssertTrue(SemanticJoboptions.allowsDistillerOverrides(in: edited))
    }

    func testPDFXBoxRulesReadAndWriteExactOffsetPaths() throws {
        let document = try makeDocument("""
        /PDFXNoTrimBoxError false
        /PDFXTrimBoxToMediaBoxOffset [1 2 3 4]
        /PDFXSetBleedBoxToMediaBox false
        /PDFXBleedBoxToTrimBoxOffset [5 6 7 8]
        """)
        XCTAssertEqual(
            SemanticJoboptions.pdfXBoxRules(in: document),
            .init(
                trim: .mediaBox(offsets: [1, 2, 3, 4]),
                bleed: .trimBox(offsets: [5, 6, 7, 8])
            )
        )

        let changes = SemanticJoboptions.changePDFXBoxRules(
            trim: .error,
            bleed: .mediaBox(offsets: [0, 0, 0, 0])
        )
        XCTAssertEqual(
            changes.paths.map(\.description),
            ["/PDFXNoTrimBoxError", "/PDFXSetBleedBoxToMediaBox"]
        )
        let edited = try changes.applying(to: document)
        XCTAssertEqual(
            SemanticJoboptions.pdfXBoxRules(in: edited),
            .init(trim: .error, bleed: .mediaBox(offsets: [0, 0, 0, 0]))
        )
    }

    func testStandardActionChangesOnlyTheStandardParameter() throws {
        let document = try makeDocument("/iPS2PDFStandard /none /CompatibilityLevel 1.1 /Encrypt true")
        let changes = SemanticJoboptions.changeStandard(.pdfa1b)

        XCTAssertEqual(changes.paths.map(\.description), ["/iPS2PDFStandard"])
        let edited = try changes.applying(to: document)
        XCTAssertEqual(edited.value(forKey: "iPS2PDFStandard")?.textualValue, "pdfa1b")
        XCTAssertEqual(edited.value(forKey: "CompatibilityLevel")?.textualValue, "1.1")
        XCTAssertEqual(edited.value(forKey: "Encrypt")?.boolValue, true)
    }

    func testSelectingPDFXAddsOnlyTheMissingDefaultOutputIntent() throws {
        let missing = try makeDocument("/iPS2PDFStandard /none /PDFXOutputIntentProfile /None")
        let missingChanges = SemanticJoboptions.changeStandard(.pdfx4, in: missing)
        XCTAssertEqual(
            missingChanges.paths.map(\.description),
            ["/iPS2PDFStandard", "/PDFXOutputIntentProfile"]
        )
        let defaulted = try missingChanges.applying(to: missing)
        XCTAssertEqual(
            defaulted.value(forKey: "PDFXOutputIntentProfile")?.textualValue,
            SemanticJoboptions.defaultPDFXOutputIntentProfile
        )

        let selected = try makeDocument("/iPS2PDFStandard /none /PDFXOutputIntentProfile (My Press)")
        let selectedChanges = SemanticJoboptions.changeStandard(.pdfx4, in: selected)
        XCTAssertEqual(selectedChanges.paths.map(\.description), ["/iPS2PDFStandard"])
        let preserved = try selectedChanges.applying(to: selected)
        XCTAssertEqual(preserved.value(forKey: "PDFXOutputIntentProfile")?.textualValue, "My Press")
    }

    func testOutputIntentEmbeddingDefaultsOffAndCanBeChanged() throws {
        let document = try makeDocument("/iPS2PDFStandard /none")

        XCTAssertFalse(SemanticJoboptions.embedsOutputIntentProfile(in: document))

        let edited = try SemanticJoboptions.changeEmbedsOutputIntentProfile(true)
            .applying(to: document)
        XCTAssertTrue(SemanticJoboptions.embedsOutputIntentProfile(in: edited))
    }

    private func makeDocument(_ entries: String) throws -> LosslessJoboptionsDocument {
        try LosslessJoboptionsDocument(data: Data("<<\n  \(entries)\n>> setdistillerparams\n".utf8))
    }
}
