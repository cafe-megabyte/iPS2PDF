import Foundation
import XCTest
@testable import iPS2PDF

final class PendingShareDocumentTests: XCTestCase {
    func testOnlyTheHandoffURLMatches() {
        XCTAssertTrue(PendingShareDocument.isTriggerURL(PendingShareDocument.triggerURL))
        XCTAssertFalse(PendingShareDocument.isTriggerURL(URL(string: "ips2pdf://something-else")!))
        XCTAssertFalse(PendingShareDocument.isTriggerURL(URL(string: "https://share-pending")!))
    }

    func testPendingDocumentIsClaimedExactlyOnce() throws {
        let fileManager = FileManager.default
        let testRootURL = fileManager.temporaryDirectory
            .appendingPathComponent("PendingShareDocumentTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let containerURL = testRootURL.appendingPathComponent("App Group", isDirectory: true)
        let stagingRootURL = testRootURL.appendingPathComponent("Incoming shares", isDirectory: true)
        defer { try? fileManager.removeItem(at: testRootURL) }

        let postScript = "%!PS\n(share handoff) =\n"
        let pendingURL = try PendingShareDocument.writePostScript(
            postScript,
            fileManager: fileManager,
            containerURL: containerURL
        )
        XCTAssertTrue(fileManager.fileExists(atPath: pendingURL.path))

        let claimedURL = try XCTUnwrap(PendingShareDocument.claimPendingSourceURL(
            fileManager: fileManager,
            containerURL: containerURL,
            stagingRootURL: stagingRootURL
        ))
        XCTAssertEqual(try String(contentsOf: claimedURL, encoding: .utf8), postScript)
        XCTAssertFalse(fileManager.fileExists(atPath: pendingURL.path))
        XCTAssertNil(try PendingShareDocument.pendingSourceURL(
            fileManager: fileManager,
            containerURL: containerURL
        ))
        XCTAssertNil(try PendingShareDocument.claimPendingSourceURL(
            fileManager: fileManager,
            containerURL: containerURL,
            stagingRootURL: stagingRootURL
        ))
    }

    func testStartupCleanupPreservesOnlyShareInbox() throws {
        let fileManager = FileManager.default
        let containerURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: containerURL) }

        _ = try PendingShareDocument.writePostScript(
            "%!PS\n",
            fileManager: fileManager,
            containerURL: containerURL
        )
        for name in ["Joboptions", "Profiles", "ConversionInput", "ConversionOutput"] {
            try fileManager.createDirectory(
                at: containerURL.appendingPathComponent(name, isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        try AppGroupWorkspace.clearStaleDataPreservingShareInbox(
            fileManager: fileManager,
            containerURL: containerURL
        )

        XCTAssertNotNil(try PendingShareDocument.pendingSourceURL(
            fileManager: fileManager,
            containerURL: containerURL
        ))
        XCTAssertEqual(
            try fileManager.contentsOfDirectory(atPath: containerURL.path),
            [AppGroupWorkspace.shareDirectoryName]
        )
    }

    func testConversionCleanupDoesNotRemoveShareInbox() throws {
        let fileManager = FileManager.default
        let containerURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: containerURL) }

        _ = try PendingShareDocument.writePostScript(
            "%!PS\n",
            fileManager: fileManager,
            containerURL: containerURL
        )
        try AppGroupWorkspace.prepareConversionDirectories(
            fileManager: fileManager,
            containerURL: containerURL
        )
        try AppGroupWorkspace.clearConversionDirectories(
            fileManager: fileManager,
            containerURL: containerURL
        )

        XCTAssertNotNil(try PendingShareDocument.pendingSourceURL(
            fileManager: fileManager,
            containerURL: containerURL
        ))
    }

    func testFullCleanupPreservesSystemManagedContainerEntries() throws {
        let fileManager = FileManager.default
        let containerURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: containerURL) }

        try fileManager.createDirectory(at: containerURL, withIntermediateDirectories: true)
        let metadataURL = containerURL
            .appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
        let libraryURL = containerURL.appendingPathComponent("Library", isDirectory: true)
        try Data().write(to: metadataURL)
        try fileManager.createDirectory(at: libraryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: containerURL.appendingPathComponent("HistoricalData", isDirectory: true),
            withIntermediateDirectories: true
        )

        try AppGroupWorkspace.clearAll(fileManager: fileManager, containerURL: containerURL)

        XCTAssertTrue(fileManager.fileExists(atPath: metadataURL.path))
        XCTAssertTrue(fileManager.fileExists(atPath: libraryURL.path))
        XCTAssertFalse(fileManager.fileExists(
            atPath: containerURL.appendingPathComponent("HistoricalData").path
        ))
    }
}
