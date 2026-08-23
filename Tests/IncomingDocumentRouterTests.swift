import Foundation
import XCTest
@testable import iPS2PDF

final class IncomingDocumentRouterTests: XCTestCase {
    func testArbitraryReadableFileIsAConversionInput() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("unknown")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data([0, 1, 2, 3]).write(to: url)

        guard case .conversionInput(let routedURL) = try IncomingDocumentRouter().classify(url)
        else {
            return XCTFail("Expected a general conversion input")
        }
        XCTAssertEqual(routedURL, url)
    }

    func testJoboptionsRemainSpecial() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("joboptions")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("<< /CompatibilityLevel 1.7 >> setdistillerparams\n".utf8).write(to: url)

        guard case .joboptions(let routedURL, _) = try IncomingDocumentRouter().classify(url)
        else {
            return XCTFail("Expected Joboptions")
        }
        XCTAssertEqual(routedURL, url)
    }
}
