import Foundation
import XCTest
@testable import iPS2PDF

final class ResourceAndCatalogTests: XCTestCase {
    func testBundledResourcesArePresentAndInspectable() throws {
        let joboptionsDirectory = try XCTUnwrap(Bundle.main.url(forResource: "Joboptions", withExtension: nil))
        let profileDirectory = try XCTUnwrap(Bundle.main.url(forResource: "Profiles", withExtension: nil))
        let joboptions = try regularFiles(in: joboptionsDirectory).filter { $0.pathExtension == "joboptions" }
        let profiles = try regularFiles(in: profileDirectory).filter {
            ["icc", "icm"].contains($0.pathExtension.lowercased())
        }

        XCTAssertTrue(joboptions.contains { $0.deletingPathExtension().lastPathComponent == "Normal" })

        for url in profiles {
            XCTAssertNoThrow(try ICCProfileRecord.inspect(url: url, origin: .bundled), url.lastPathComponent)
        }
    }

    func testCatalogueIsVersionedAndHasUniqueKeys() {
        XCTAssertEqual(DistillerOptionCatalog.ghostscriptVersion, "10.07.1")
        XCTAssertGreaterThan(DistillerOptionCatalog.options.count, 50)
        XCTAssertEqual(
            Set(DistillerOptionCatalog.options.map(\.key)).count,
            DistillerOptionCatalog.options.count
        )
        for category in DistillerCategory.allCases where category != .additional {
            XCTAssertFalse(DistillerOptionCatalog.options(in: category).isEmpty, category.rawValue)
        }
    }

    func testStandardCompatibilityLocksAreDefined() {
        XCTAssertNil(PDFStandard.none.requiredCompatibilityLevel)
        XCTAssertEqual(PDFStandard.pdfa1b.requiredCompatibilityLevel, "1.4")
        XCTAssertEqual(PDFStandard.pdfa2b.requiredCompatibilityLevel, "1.7")
        XCTAssertEqual(PDFStandard.pdfa3b.requiredCompatibilityLevel, "1.7")
        XCTAssertEqual(PDFStandard.pdfx1.requiredCompatibilityLevel, "1.4")
        XCTAssertEqual(PDFStandard.pdfx3.requiredCompatibilityLevel, "1.4")
        XCTAssertEqual(PDFStandard.pdfx4.requiredCompatibilityLevel, "1.7")
    }

    private func regularFiles(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).filter { try $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true }
    }
}
