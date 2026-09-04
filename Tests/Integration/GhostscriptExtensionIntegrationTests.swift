import PDFKit
import XCTest
@testable import iPS2PDF

/// Verifies conversion behavior across the app-to-extension boundary.
final class GhostscriptExtensionIntegrationTests: XCTestCase {
    func testAdditionalDeviceParametersReachGhostscript() async throws {
        let output = try await convert(
            joboptions: """
            << /PDFACompatibilityPolicy 2 /BlendConversionStrategy /Managed
               /ProcessColorModel /DeviceGray /EncryptionR 3 /Permissions -44 /LockDistillerParams true
            >> setdistillerparams
            """,
            standard: .none,
            postScript: """
            %!PS-Adobe-3.0
            currentpagedevice /PDFACompatibilityPolicy get 2 ne { 1 0 div pop } if
            currentpagedevice /BlendConversionStrategy get /Managed ne { 1 0 div pop } if
            currentpagedevice /ProcessColorModel get /DeviceGray ne { 1 0 div pop } if
            currentpagedevice /Permissions get -44 ne { 1 0 div pop } if
            << /CompressPages false >> setdistillerparams
            currentdistillerparams /CompressPages get not { 1 0 div pop } if
            showpage
            """
        )
        XCTAssertEqual(try XCTUnwrap(PDFDocument(data: output)).pageCount, 1)
    }

    func testPDFAPolicyIsNotHardcodedByBridge() async throws {
        let output = try await convert(
            joboptions: "<< /PDFACompatibilityPolicy 2 /ColorConversionStrategy /RGB >> setdistillerparams",
            standard: .pdfa2b,
            postScript: """
            %!PS-Adobe-3.0
            currentpagedevice /PDFACompatibilityPolicy get 2 ne { 1 0 div pop } if
            showpage
            """
        )
        XCTAssertEqual(try XCTUnwrap(PDFDocument(data: output)).pageCount, 1)
    }

    func testDeviceICCProfilesReachGhostscript() async throws {
        let output = try await convert(
            joboptions: """
            << /OutputICCProfile (sRGB Profile) /GraphicICCProfile (sRGB Profile)
               /ImageICCProfile (sRGB Profile) /TextICCProfile (sRGB Profile) /LockDistillerParams true
            >> setdistillerparams
            """,
            standard: .none,
            postScript: """
            %!PS-Adobe-3.0
            currentpagedevice /OutputICCProfile get (default_rgb.icc) eq { 1 0 div pop } if
            [/VectorICCProfile /ImageICCProfile /TextICCProfile] {
              currentpagedevice exch get length 0 eq { 1 0 div pop } if
            } forall
            << /CompressPages false >> setdistillerparams
            currentdistillerparams /CompressPages get not { 1 0 div pop } if
            showpage
            """
        )
        XCTAssertEqual(try XCTUnwrap(PDFDocument(data: output)).pageCount, 1)
    }

    func testPasswordSettingsProduceAnEncryptedPDF() async throws {
        let output = try await convert(
            joboptions: "<< /Encrypt true /EncryptionR 3 /CompatibilityLevel 1.4 /OwnerPassword (test-owner) /UserPassword (test-user) /Permissions -4 >> setdistillerparams",
            standard: .none
        )
        let pdf = try XCTUnwrap(PDFDocument(data: output))
        XCTAssertTrue(pdf.isEncrypted)
        XCTAssertTrue(pdf.unlock(withPassword: "test-user"))
        XCTAssertEqual(pdf.pageCount, 1)
    }

    func testPreservedUnknownTrappedStateDoesNotBreakNormalPDF() async throws {
        let output = try await convert(joboptions: "<< /PDFXTrapped /Unknown >> setdistillerparams", standard: .none)
        XCTAssertEqual(try XCTUnwrap(PDFDocument(data: output)).pageCount, 1)
    }

    func testSetTransparencyPdfmarkConvertsWhenAllowedByJoboptions() async throws {
        let output = try await convert(allowTransparency: true)
        let document = try XCTUnwrap(PDFDocument(data: output))
        XCTAssertEqual(document.pageCount, 1)
    }

    func testSetTransparencyPdfmarkIsNotMappedWhenDisabledByJoboptions() async throws {
        let enabled = try centerPixel(in: await convert(allowTransparency: true))
        let disabled = try centerPixel(in: await convert(allowTransparency: false))

        XCTAssertGreaterThan(enabled.blue, disabled.blue + 50)
        XCTAssertLessThan(enabled.red, disabled.red - 50)
    }

    func testPDFInputIsRewrittenAsPDF() async throws {
        let firstPDF = try await convert(allowTransparency: true)
        let rewrittenPDF = try await convert(
            input: firstPDF,
            inputFileName: "Already.pdf",
            allowTransparency: true
        )

        let document = try XCTUnwrap(PDFDocument(data: rewrittenPDF))
        XCTAssertEqual(document.pageCount, 1)
    }

    func testAutoPositionEPSFilesAppliesTheEPSBoundingBox() async throws {
        let cropped = try await convert(
            input: Data(Self.boundedEPS.utf8),
            inputFileName: "Bounded.eps",
            allowTransparency: false,
            autoPositionEPSFiles: true
        )
        let uncropped = try await convert(
            input: Data(Self.boundedEPS.utf8),
            inputFileName: "Bounded.eps",
            allowTransparency: false,
            autoPositionEPSFiles: false
        )

        let croppedBox = try mediaBox(in: cropped)
        let uncroppedBox = try mediaBox(in: uncropped)
        XCTAssertEqual(croppedBox.width, 100, accuracy: 0.1)
        XCTAssertEqual(croppedBox.height, 200, accuracy: 0.1)
        XCTAssertGreaterThan(uncroppedBox.width, croppedBox.width)
        XCTAssertGreaterThan(uncroppedBox.height, croppedBox.height)
    }

    func testEmbedSubstituteFontsIsPassedFromJoboptionsToGhostscript() async throws {
        for expected in [false, true] {
            let probe = """
            %!PS-Adobe-3.0
            /EmbedSubstituteFonts /GetDeviceParam .special_op
            { exch pop \(expected) ne { 1 0 div pop } if }
            { 1 0 div pop } ifelse
            showpage
            """
            let output = try await convert(
                input: Data(probe.utf8),
                inputFileName: "EmbedSubstituteFonts.ps",
                allowTransparency: false,
                embedSubstituteFonts: expected
            )

            XCTAssertEqual(try XCTUnwrap(PDFDocument(data: output)).pageCount, 1)
        }
    }

    func testOutputIntentEmbeddingToggleControlsNormalPDF() async throws {
        let disabled = try await convert(
            joboptions: """
            <<
              /PDFXOutputIntentProfile (PSOcoated_v3)
              /iPS2PDFEmbedOutputIntentProfile false
            >> setdistillerparams
            """,
            standard: .none
        )
        let enabled = try await convert(
            joboptions: """
            <<
              /PDFXOutputIntentProfile (PSOcoated_v3)
              /iPS2PDFEmbedOutputIntentProfile true
            >> setdistillerparams
            """,
            standard: .none
        )

        XCTAssertNil(try outputIntent(in: disabled))
        let intent = try XCTUnwrap(outputIntent(in: enabled))
        XCTAssertEqual(intent.identifier, "FOGRA51")
        XCTAssertEqual(intent.info, "PSOcoated_v3")
        XCTAssertTrue(intent.hasEmbeddedProfile)
    }

    func testPDFAMayEmbedOrOmitItsSelectedOutputProfile() async throws {
        for embeds in [false, true] {
            let output = try await convert(
                joboptions: """
                <<
                  /OutputICCProfile (sRGB Profile)
                  /PDFXOutputIntentProfile (sRGB Profile)
                  /iPS2PDFEmbedOutputIntentProfile \(embeds)
                >> setdistillerparams
                """,
                standard: .pdfa2b
            )

            XCTAssertEqual(try outputIntent(in: output) != nil, embeds)
        }
    }

    func testPDFXAlwaysEmbedsProfileAndUsesEffectiveMetadata() async throws {
        let output = try await convert(
            joboptions: """
            <<
              /PDFXOutputIntentProfile (PSOcoated_v3)
              /PDFXOutputCondition (Offset printing on premium coated paper)
              /PDFXOutputConditionIdentifier (FOGRA51)
              /PDFXRegistryName (https://registry.color.org)
              /PDFXTrapped /True
              /iPS2PDFEmbedOutputIntentProfile false
            >> setdistillerparams
            """,
            standard: .pdfx4
        )

        let intent = try XCTUnwrap(outputIntent(in: output))
        XCTAssertEqual(intent.identifier, "FOGRA51")
        XCTAssertEqual(intent.outputCondition, "Offset printing on premium coated paper")
        XCTAssertEqual(intent.registryName, "https://registry.color.org")
        XCTAssertEqual(intent.info, "PSOcoated_v3")
        XCTAssertTrue(intent.hasEmbeddedProfile)
        XCTAssertEqual(try documentInfoName("Trapped", in: output), "True")
    }

    private func convert(allowTransparency: Bool) async throws -> Data {
        try await convert(
            input: Data(Self.transparencyPostScript.utf8),
            inputFileName: "Transparency.ps",
            allowTransparency: allowTransparency
        )
    }

    private func convert(
        input: Data,
        inputFileName: String,
        allowTransparency: Bool,
        autoPositionEPSFiles: Bool = false,
        embedSubstituteFonts: Bool? = nil
    ) async throws -> Data {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("iPS2PDF-Transparency-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }

        let joboptionsURL = directory.appendingPathComponent("Transparency.joboptions")
        let inputURL = directory.appendingPathComponent(inputFileName)
        let outputURL = directory.appendingPathComponent("Transparency.pdf")
        let allowValue = allowTransparency ? "true" : "false"
        let autoPositionValue = autoPositionEPSFiles ? "true" : "false"
        let embedSubstituteFontsEntry = embedSubstituteFonts.map {
            "/EmbedSubstituteFonts \($0)"
        } ?? ""
        try Data(
            "<< /AllowTransparency \(allowValue) /AutoPositionEPSFiles \(autoPositionValue) \(embedSubstituteFontsEntry) >> setdistillerparams\n".utf8
        )
            .write(to: joboptionsURL)
        try input.write(to: inputURL)

        try await GhostscriptExtensionClient().convert(
            inputURL: inputURL,
            outputURL: outputURL,
            joboptionsURL: joboptionsURL,
            standard: .none,
            limitsEnabled: true,
            postScriptRandomSeed: PostScriptRandomSeedSettings.defaultManualSeed
        )

        return try Data(contentsOf: outputURL)
    }

    private func convert(joboptions: String, standard: PDFStandard, postScript: String? = nil) async throws -> Data {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("iPS2PDF-OutputIntent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }

        let joboptionsURL = directory.appendingPathComponent("OutputIntent.joboptions")
        let inputURL = directory.appendingPathComponent("OutputIntent.ps")
        let outputURL = directory.appendingPathComponent("OutputIntent.pdf")
        try Data(joboptions.utf8).write(to: joboptionsURL)
        try Data((postScript ?? Self.simplePostScript).utf8).write(to: inputURL)

        try await GhostscriptExtensionClient().convert(
            inputURL: inputURL,
            outputURL: outputURL,
            joboptionsURL: joboptionsURL,
            standard: standard,
            limitsEnabled: true,
            postScriptRandomSeed: PostScriptRandomSeedSettings.defaultManualSeed
        )
        return try Data(contentsOf: outputURL)
    }

    private func outputIntent(in data: Data) throws -> OutputIntent? {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider),
              let catalog = document.catalog
        else { throw XCTSkip("Core Graphics could not open the generated PDF.") }

        var intents: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(catalog, "OutputIntents", &intents),
              let intents,
              CGPDFArrayGetCount(intents) > 0
        else { return nil }

        var dictionary: CGPDFDictionaryRef?
        guard CGPDFArrayGetDictionary(intents, 0, &dictionary), let dictionary else {
            XCTFail("The first output intent is not a dictionary.")
            return nil
        }
        var profile: CGPDFStreamRef?
        return OutputIntent(
            identifier: pdfString("OutputConditionIdentifier", in: dictionary),
            outputCondition: pdfString("OutputCondition", in: dictionary),
            registryName: pdfString("RegistryName", in: dictionary),
            info: pdfString("Info", in: dictionary),
            hasEmbeddedProfile: CGPDFDictionaryGetStream(
                dictionary,
                "DestOutputProfile",
                &profile
            ) && profile != nil
        )
    }

    private func pdfString(_ key: String, in dictionary: CGPDFDictionaryRef) -> String? {
        var value: CGPDFStringRef?
        guard CGPDFDictionaryGetString(dictionary, key, &value), let value else { return nil }
        return CGPDFStringCopyTextString(value) as String?
    }

    private func documentInfoName(_ key: String, in data: Data) throws -> String? {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider),
              let info = document.info
        else { throw XCTSkip("Core Graphics could not open the generated PDF info dictionary.") }
        var value: UnsafePointer<CChar>?
        guard CGPDFDictionaryGetName(info, key, &value), let value else { return nil }
        return String(cString: value)
    }

    private func mediaBox(in data: Data) throws -> CGRect {
        let document = try XCTUnwrap(PDFDocument(data: data))
        return try XCTUnwrap(document.page(at: 0)).bounds(for: .mediaBox)
    }

    private func centerPixel(in data: Data) throws -> (red: Int, green: Int, blue: Int) {
        let document = try XCTUnwrap(PDFDocument(data: data))
        let page = try XCTUnwrap(document.page(at: 0))
        let width = 200
        let height = 200
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(
                data: bytes.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            page.draw(with: .mediaBox, to: context)
        }
        let offset = ((height / 2) * width + (width / 2)) * 4
        return (Int(pixels[offset]), Int(pixels[offset + 1]), Int(pixels[offset + 2]))
    }

    private static let transparencyPostScript = """
    %!PS-Adobe-3.0
    << /PageSize [200 200] >> setpagedevice
    0 0 1 setrgbcolor
    20 20 160 160 rectfill
    [ /ca 0.5 /CA 0.5 /BM /Normal /SetTransparency pdfmark
    1 0 0 setrgbcolor
    60 60 100 100 rectfill
    showpage
    """

    private static let boundedEPS = """
    %!PS-Adobe-3.0 EPSF-3.0
    %%BoundingBox: 10 20 110 220
    %%HiResBoundingBox: 10 20 110 220
    %%Pages: 1
    0 0 1 setrgbcolor
    10 20 100 200 rectfill
    showpage
    %%EOF
    """

    private static let simplePostScript = """
    %!PS-Adobe-3.0
    << /PageSize [200 200] >> setpagedevice
    0.2 0.4 0.8 setrgbcolor
    20 20 160 160 rectfill
    showpage
    """

    private struct OutputIntent {
        let identifier: String?
        let outputCondition: String?
        let registryName: String?
        let info: String?
        let hasEmbeddedProfile: Bool
    }
}
