import Combine
import PDFKit
import SwiftUI
import UIKit
import XCTest
@testable import iPS2PDF

final class PDFRoutingIntegrationTests: XCTestCase {
    private actor RoutingConverter: FileConverting {
        private(set) var calls = 0
        func validateJoboptions(at joboptionsURL: URL) async throws { }
        func convert(sourceURL: URL, outputURL: URL, joboptionsURL: URL, standard: PDFStandard, securityLimitsEnabled: Bool, postScriptRandomSeed: Int, inputPassword: String?) async throws {
            calls += 1
            try FileManager.default.copyItem(at: sourceURL, to: outputURL)
        }
        func convertToPostScript(sourceURL: URL, outputURL: URL, securityLimitsEnabled: Bool, postScriptRandomSeed: Int, inputPassword: String?) async throws {
            calls += 1
            try FileManager.default.copyItem(at: sourceURL, to: outputURL)
        }
    }

    private final class RoutingFileManager: FileManager, @unchecked Sendable {
        private let root = FileManager.default.temporaryDirectory.appendingPathComponent("RoutingWorkspace-\(UUID().uuidString)")
        override var temporaryDirectory: URL { root }
        deinit { try? FileManager.default.removeItem(at: root) }
    }

    private actor EncryptedExportConverter: FileConverting {
        private(set) var postScriptConversions = 0

        func validateJoboptions(at joboptionsURL: URL) async throws {}

        func convert(
            sourceURL: URL,
            outputURL: URL,
            joboptionsURL: URL,
            standard: PDFStandard,
            securityLimitsEnabled: Bool,
            postScriptRandomSeed: Int,
            inputPassword: String?
        ) async throws {}

        func convertToPostScript(
            sourceURL: URL,
            outputURL: URL,
            securityLimitsEnabled: Bool,
            postScriptRandomSeed: Int,
            inputPassword: String?
        ) async throws {
            postScriptConversions += 1
            try Data(
                "%!PS-Adobe-3.0\n72 720 moveto (Converted PDF payload 9817) show\nshowpage\n".utf8
            ).write(to: outputURL)
        }
    }

    @MainActor private func model(converter: RoutingConverter = RoutingConverter()) -> ConversionViewModel {
        ConversionViewModel(workingDirectoryService: WorkingDirectoryService(fileManager: RoutingFileManager()), converter: converter)
    }
    @MainActor private func fixture(extension suffix: String, missingFont: Bool = false) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PDFRouting-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("Routing." + suffix)
        if missingFont {
            let content = "BT /F1 14 Tf 20 100 Td (Missing font) Tj ET"
            let objects = ["<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Count 1 /Kids [3 0 R] >>", "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>", "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>", "<< /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream"]
            var data = Data("%PDF-1.4\n".utf8), offsets = [0]
            for (index, object) in objects.enumerated() { offsets.append(data.count); data.append(Data("\(index + 1) 0 obj\n\(object)\nendobj\n".utf8)) }
            let xref = data.count
            let entries = offsets.dropFirst().map { String(format: "%010d 00000 n \n", $0) }.joined()
            data.append(Data("xref\n0 6\n0000000000 65535 f \n\(entries)trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n".utf8))
            try data.write(to: url)
        } else {
            let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 200, height: 200))
            try renderer.pdfData { context in context.beginPage(); ("PDF routing" as NSString).draw(at: CGPoint(x: 20, y: 20), withAttributes: [.font: UIFont.systemFont(ofSize: 14)]) }.write(to: url)
        }
        return url
    }
    @MainActor private func finish(_ model: ConversionViewModel, action: () -> Void) async {
        let done = expectation(description: "Routing finished")
        let observation = model.$isProcessing.dropFirst().filter { !$0 }.prefix(1).sink { _ in done.fulfill() }
        action()
        await fulfillment(of: [done], timeout: 15)
        observation.cancel()
    }
    @MainActor func testExternalPDFHeaderOpensInformationWithoutCallingConverter() async throws {
        let converter = RoutingConverter()
        let model = model(converter: converter)
        let url = try fixture(extension: "dat")
        defer { model.presentedPDFInfo?.cancel(); try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        await finish(model) { model.handleOpenURL(url) }
        XCTAssertNotNil(model.presentedPDFInfo)
        XCTAssertNil(model.presentedPDF)
        let calls = await converter.calls
        XCTAssertEqual(calls, 0)
        XCTAssertNil(model.alert)
    }
    @MainActor func testExplicitPDFSelectionStillCallsConverter() async throws {
        let converter = RoutingConverter()
        let model = model(converter: converter)
        let url = try fixture(extension: "pdf")
        defer { model.closePDFViewer(); model.pdfViewerDidDismiss(); try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        await finish(model) { model.handleSelectedFile(url) }
        XCTAssertNotNil(model.presentedPDF)
        XCTAssertNil(model.presentedPDFInfo)
        let calls = await converter.calls
        XCTAssertEqual(calls, 1)
    }
    @MainActor func testDroppedPDFOpensInformation() async throws {
        let converter = RoutingConverter()
        let model = model(converter: converter)
        let url = try fixture(extension: "pdf")
        defer { model.presentedPDFInfo?.cancel(); try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        await finish(model) { model.handleDroppedFile(url) }
        XCTAssertNotNil(model.presentedPDFInfo)
        let calls = await converter.calls
        XCTAssertEqual(calls, 0)
    }
    @MainActor func testInformationPresentationAndLayout() async throws {
        try await checkInformationLayout(missingFont: false)
    }
    @MainActor func testClosingViewerThenImmediatelyOpeningInformationKeepsTheNewFile() async throws {
        let model = model()
        let url = try fixture(extension: "pdf")
        defer { model.presentedPDFInfo?.cancel(); try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        await finish(model) { model.handleSelectedFile(url) }
        XCTAssertNotNil(model.presentedPDF)
        model.closePDFViewer()
        model.pdfViewerDidDismiss()
        await finish(model) { model.handleOpenURL(url) }
        XCTAssertNil(model.alert)
        XCTAssertNotNil(model.presentedPDFInfo)
    }

    @MainActor func testCompletedPostScriptConversionPresentsFileExporter() async throws {
        let model = model()
        let url = try fixture(extension: "pdf")
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try XCTUnwrap(scene.windows.first { $0.isKeyWindow })
        let previous = window.rootViewController
        let host = UIHostingController(rootView: ContentView(viewModel: model))
        window.rootViewController = host
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        defer {
            model.postScriptFileExporterDidFinish(.failure(CocoaError(.userCancelled)))
            host.dismiss(animated: false)
            window.rootViewController = previous
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }

        try await Task.sleep(for: .milliseconds(100))
        await finish(model) { model.handleSelectedPostScriptFile(url) }
        try await Task.sleep(for: .milliseconds(500))

        XCTAssertTrue(model.isPostScriptFileExporterPresented)
        XCTAssertNotNil(host.presentedViewController, "The completed PostScript conversion must present its save dialog")
    }

    @MainActor func testPrimaryFileImporterStillPresentsWhenEncryptionFlowIsInstalled() async throws {
        let model = model()
        model.presentFileImporter(for: .pdfInformation)
        XCTAssertTrue(model.isFileImporterPresented)
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let window = try XCTUnwrap(scene.windows.first { $0.isKeyWindow })
        let previous = window.rootViewController
        let host = UIHostingController(rootView: ContentView(viewModel: model))
        window.rootViewController = host
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        defer {
            host.dismiss(animated: false)
            window.rootViewController = previous
        }

        try await Task.sleep(for: .milliseconds(500))

        let presentedViewControllers = scene.windows.flatMap {
            presentedViewControllerHierarchy(from: $0.rootViewController)
        }
        XCTAssertTrue(
            presentedViewControllers.contains { $0 is UIDocumentPickerViewController },
            "Installing the PostScript encryption flow must not disable the existing file importer. isPresented=\(model.isFileImporterPresented), purpose=\(String(describing: model.fileImportPurpose)), controlsDisabled=\(model.controlsAreDisabled), presented=\(presentedViewControllers.map { String(describing: type(of: $0)) })"
        )
    }

    @MainActor func testEncryptedPDFExportConvertsBeforeEncrypting() async throws {
        let converter = EncryptedExportConverter()
        let runtimeSettings = GhostscriptRuntimeSettings()
        let session = PostScriptEncryptionSession(
            runtimeSettings: runtimeSettings,
            converter: converter
        )
        let sourceURL = try fixture(extension: "pdf")
        defer {
            session.cancel()
            try? FileManager.default.removeItem(at: sourceURL.deletingLastPathComponent())
        }

        session.preparePDFExport(
            sourceURL: sourceURL,
            sourceName: "Current.pdf",
            inputPassword: nil
        )
        XCTAssertTrue(session.isPasswordPromptPresented)

        let ready = expectation(description: "Encrypted PostScript is ready to save")
        let observation = session.$artifact.compactMap { $0 }.prefix(1).sink { _ in
            ready.fulfill()
        }
        session.encrypt(password: "Export password 42!")
        await fulfillment(of: [ready], timeout: 10)
        observation.cancel()

        let artifact = try XCTUnwrap(session.artifact)
        let encrypted = try String(contentsOf: artifact.url, encoding: .utf8)
        let conversionCount = await converter.postScriptConversions
        XCTAssertEqual(conversionCount, 1)
        XCTAssertEqual(artifact.url.lastPathComponent, "Current.encrypted.ps")
        XCTAssertFalse(encrypted.contains("Converted PDF payload 9817"))
        XCTAssertTrue(
            encrypted.contains(
                "/wrongPasswordMessage <57726f6e672050617373776f7264> def"
            )
        )
    }

    @MainActor func testMissingFontInformationPresentationAndLayout() async throws {
        try await checkInformationLayout(missingFont: true)
    }

    func testWorkingDirectoryCleanupRemovesAbandonedPostScriptExports() async throws {
        let service = WorkingDirectoryService(fileManager: RoutingFileManager())
        try await service.clearWorkingDirectory()
        let outputURL = try await service.postScriptOutputURL(sourceName: "Abandoned.pdf")
        try Data("%!PS-Adobe-3.0\n".utf8).write(to: outputURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))

        try await service.clearWorkingDirectory()
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
    }

    @MainActor func testGlobalGhostscriptSettingsPreserveExistingDefaults() throws {
        let suiteName = "GhostscriptRuntimeSettingsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "initializedSecurityLimits")
        defaults.set(false, forKey: "securityLimitsEnabled")
        defaults.set(false, forKey: "automaticRandomSeed")
        defaults.set(42, forKey: "manualRandomSeed")

        let settings = GhostscriptRuntimeSettings(defaults: defaults)
        XCTAssertFalse(settings.securityLimitsEnabled)
        XCTAssertFalse(settings.automaticRandomSeed)
        XCTAssertEqual(settings.manualRandomSeed, 42)
        XCTAssertEqual(settings.snapshot().postScriptRandomSeed, 42)

        settings.securityLimitsEnabled = true
        settings.setAutomaticRandomSeed(true)
        XCTAssertTrue(defaults.bool(forKey: "securityLimitsEnabled"))
        XCTAssertTrue(defaults.bool(forKey: "automaticRandomSeed"))
    }

    @MainActor private func checkInformationLayout(missingFont: Bool) async throws {
        let model = model()
        let url = try fixture(extension: "pdf", missingFont: missingFont)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try XCTUnwrap(scene.windows.first { $0.isKeyWindow })
        let previous = window.rootViewController
        let host = UIHostingController(rootView: ContentView(viewModel: model))
        window.rootViewController = host
        defer {
            host.dismiss(animated: false)
            window.rootViewController = previous
            model.presentedPDFInfo?.cancel()
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        await finish(model) { model.handleOpenURL(url) }
        let session = try XCTUnwrap(model.presentedPDFInfo)
        let read = expectation(description: "PDF properties read")
        let observation = session.$isReading.filter { !$0 }.prefix(1).sink { _ in read.fulfill() }
        await fulfillment(of: [read], timeout: 10)
        observation.cancel()
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertNotNil(host.presentedViewController, "The real ContentView must present the information sheet")
        XCTAssertTrue(session.report.isComplete, session.report.notices.joined(separator: "\n"))
        XCTAssertEqual(session.report.fontWarnings.count, missingFont ? 1 : 0)
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image)
        attachment.name = missingFont ? "PDF information — visible font warning" : "PDF information — iOS sheet"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor private func presentedViewControllerHierarchy(
        from root: UIViewController?
    ) -> [UIViewController] {
        guard let root else { return [] }
        return [root]
            + root.children.flatMap { presentedViewControllerHierarchy(from: $0) }
            + presentedViewControllerHierarchy(from: root.presentedViewController)
    }
}
