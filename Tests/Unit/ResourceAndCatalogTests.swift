import Foundation
import XCTest

final class ResourceAndCatalogTests: XCTestCase {
    func testBundledResourcesArePresentAndInspectable() throws {
        let bundle = Bundle(for: Self.self)
        let joboptionsDirectory = try XCTUnwrap(bundle.url(forResource: "Joboptions", withExtension: nil))
        let profileDirectory = try XCTUnwrap(bundle.url(forResource: "Profiles", withExtension: nil))
        let joboptions = try regularFiles(in: joboptionsDirectory).filter { $0.pathExtension == "joboptions" }
        let profiles = try regularFiles(in: profileDirectory).filter {
            ["icc", "icm"].contains($0.pathExtension.lowercased())
        }

        XCTAssertTrue(joboptions.contains { $0.deletingPathExtension().lastPathComponent == "Normal" })

        for url in profiles {
            XCTAssertNoThrow(try ICCProfileRecord.inspect(url: url, origin: .bundled), url.lastPathComponent)
        }

        let metadata = try Dictionary(uniqueKeysWithValues: profiles.map { url in
            let profile = try ICCProfileRecord.inspect(url: url, origin: .bundled)
            return (profile.fileStem, profile)
        })
        XCTAssertEqual(metadata["PSOcoated_v3"]?.outputConditionIdentifier, "FOGRA51")
        XCTAssertEqual(metadata["ISOcoated_v2_eci"]?.outputConditionIdentifier, "FOGRA39")
        XCTAssertEqual(metadata["CoatedGRACoL2006"]?.outputConditionIdentifier, "CGATS TR 006")
        XCTAssertEqual(metadata["CoatedFOGRA27"]?.outputConditionIdentifier, "FOGRA27")
        XCTAssertNil(metadata["Generic CMYK Profile"]?.outputConditionIdentifier)
        XCTAssertEqual(metadata["ISOcoated_v2_to_PSOcoated_v3_DeviceLink"]?.profileClass, "link")
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
        for option in DistillerOptionCatalog.options {
            XCTAssertFalse(option.keyPaths.isEmpty, option.key)
            XCTAssertFalse(option.localizedHelp.hasSuffix("."), option.key)
            XCTAssertFalse(option.localizedCompatibilityNote?.hasSuffix(".") == true, option.key)
        }
        XCTAssertTrue(DistillerOptionCatalog.options.contains {
            $0.classification == .knownAdditional
        })
        XCTAssertEqual(
            DistillerOptionCatalog.byKey["ColorSettingsFile"]?.classification,
            .preserved
        )
    }

    func testCompositeTooltipPathsMatchTheirSemanticChangeSets() {
        let compression = DistillerOptionCatalog.byKey["ColorImageFilter"]
        let compressionChanges = SemanticJoboptions.changeCompression(
            kind: .color,
            compression: .automaticJPEG,
            quality: .medium
        )
        XCTAssertEqual(compression?.keyPaths, compressionChanges.paths)

        let policy = DistillerOptionCatalog.byKey["MonoImageMinResolution"]
        let policyChanges = SemanticJoboptions.changeImagePolicy(
            kind: .monochrome,
            minimumResolution: 600,
            policy: .warn
        )
        XCTAssertEqual(policy?.keyPaths, policyChanges.paths)

        let override = DistillerOptionCatalog.byKey["LockDistillerParams"]
        XCTAssertEqual(
            override?.keyPaths,
            SemanticJoboptions.changeAllowsDistillerOverrides(true).paths
        )
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
