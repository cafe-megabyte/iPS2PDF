import PDFKit
import XCTest
@testable import iPS2PDF

final class EnhancedSecurityIntegrationTests: XCTestCase {
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

    private func convert(allowTransparency: Bool) async throws -> Data {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("iPS2PDF-Transparency-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }

        let joboptionsURL = directory.appendingPathComponent("Transparency.joboptions")
        let inputURL = directory.appendingPathComponent("Transparency.ps")
        let outputURL = directory.appendingPathComponent("Transparency.pdf")
        let allowValue = allowTransparency ? "true" : "false"
        try Data("<< /AllowTransparency \(allowValue) >> setdistillerparams\n".utf8)
            .write(to: joboptionsURL)
        try Data(Self.transparencyPostScript.utf8).write(to: inputURL)

        try await EnhancedSecurityClient().convert(
            inputURL: inputURL,
            outputURL: outputURL,
            joboptionsURL: joboptionsURL,
            standard: .none,
            limitsEnabled: true,
            postScriptRandomSeed: PostScriptRandomSeedSettings.defaultManualSeed
        )

        return try Data(contentsOf: outputURL)
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
}
