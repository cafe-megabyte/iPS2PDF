import AppKit
import SwiftUI
import PDFKit

@main @MainActor
struct PDFCompressionViewSmoke {
    static func require(_ value: Bool, _ message: String) throws {
        if !value { throw NSError(domain: "PDFCompressionViewSmoke", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    static func descendants<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
        view.subviews.flatMap { child in (child as? T).map { [$0] } ?? descendants(type, in: child) }
    }
    static func wait(_ predicate: @escaping () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while !predicate() {
            try require(ContinuousClock.now < deadline, "Timed out waiting for PDF comparison")
            try await Task.sleep(for: .milliseconds(30))
        }
    }
    static func main() async throws {
        let folder = URL(fileURLWithPath: CommandLine.arguments[1])
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let editing = try PDFEditingSession(input: PDFInspectionInput(sourceURL: folder.appendingPathComponent("Compression-Shared-Source.pdf")))
        let full = try PDFEditingRevision(input: PDFInspectionInput(sourceURL: folder.appendingPathComponent("Compression-Shared-Full.pdf")))
        let preview = try PDFEditingRevision(
            input: PDFInspectionInput(sourceURL: folder.appendingPathComponent("Compression-Shared-Preview.pdf")),
            sharedResourcesFromEarlierPages: 1
        )
        let model = try PDFCompressionSession(editing: editing) { _, _, _, _, page in page == nil ? full : preview }
        let host = NSHostingController(rootView: PDFCompressionView(session: model, close: {}))
        let window = NSWindow(contentViewController: host)
        window.setContentSize(NSSize(width: 1050, height: 760))
        window.makeKeyAndOrderFront(nil)
        defer { model.cancel(); window.close(); editing.cancel() }
        try await wait { model.canAccept }
        host.view.layoutSubtreeIfNeeded()
        try await wait { descendants(PDFView.self, in: host.view).filter { $0.document?.pageCount == 2 }.count == 2 }
        let views = descendants(PDFView.self, in: host.view).sorted {
            $0.convert($0.bounds, to: host.view).minX < $1.convert($1.bounds, to: host.view).minX
        }
        try require(views.count == 2, "Mac comparison is not side by side")
        try require(views.allSatisfy { $0.bounds.width > 300 && $0.bounds.height > 300 }, "PDF comparison has an unusable viewport")
        let left = views[0], right = views[1]
        try require(views.allSatisfy { view in
            view.currentPage.map { view.document?.index(for: $0) == 0 } == true
        }, "PDF comparison did not open on page 1")
        try require(views.allSatisfy { view in
            let fitted = view.scaleFactorForSizeToFit
            return fitted > 0 && abs(view.scaleFactor / fitted - 1) < 0.02
        }, "PDF comparison did not initially fit page 1")
        left.scaleFactor = left.scaleFactorForSizeToFit * 2
        if let page = left.document?.page(at: 1) { left.go(to: PDFDestination(page: page, at: CGPoint(x: 100, y: 450))) }
        try await wait { right.currentPage.map { right.document?.index(for: $0) == 1 } == true && model.currentPage == 1 }
        try await Task.sleep(for: .milliseconds(100))
        let leftScale = left.scaleFactor / left.scaleFactorForSizeToFit
        let rightScale = right.scaleFactor / right.scaleFactorForSizeToFit
        try require(abs(leftScale - rightScale) < 0.02, "Comparison zoom did not synchronize")
        guard let a = left.currentDestination?.point, let b = right.currentDestination?.point else { throw CocoaError(.fileReadUnknown) }
        try require(abs(a.x - b.x) < 2 && abs(a.y - b.y) < 2, "Comparison scroll positions diverged")
        window.setContentSize(NSSize(width: 800, height: 560))
        host.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        try require(views.allSatisfy { $0.bounds.width > 250 && $0.bounds.height > 200 }, "Compact comparison lost its usable viewports")
        let retainedScale = left.scaleFactor / left.scaleFactorForSizeToFit
        guard let retainedPoint = left.currentDestination?.point else { throw CocoaError(.fileReadUnknown) }
        model.options.contrast = 20
        try await wait { model.canAccept }
        host.view.layoutSubtreeIfNeeded()
        try await wait { descendants(PDFView.self, in: host.view).filter { $0.document?.pageCount == 2 }.count == 2 }
        // PDFKit can run another auto-scale layout after the replacement has
        // appeared. Wait long enough to catch that delayed reset.
        try await Task.sleep(for: .milliseconds(750))
        let refreshed = descendants(PDFView.self, in: host.view)
        try require(refreshed.allSatisfy { view in
            view.currentPage.map { view.document?.index(for: $0) == 1 } == true
        }, "Changing compression options reset the current page")
        let refreshedScales = refreshed.map { $0.scaleFactor / $0.scaleFactorForSizeToFit }
        try require(refreshed.allSatisfy { view in
            let fitted = view.scaleFactorForSizeToFit
            return fitted > 0 && abs(view.scaleFactor / fitted - retainedScale) < 0.02
        }, "Changing compression options reset the zoom: retained \(retainedScale), found \(refreshedScales)")
        try require(refreshed.allSatisfy { view in
            guard let point = view.currentDestination?.point else { return false }
            return abs(point.x - retainedPoint.x) < 2 && abs(point.y - retainedPoint.y) < 2
        }, "Changing compression options reset the visible area")
        model.setCurrentPageUsesIndividualSettingsFromView(true)
        try await wait { model.canAccept && model.standardComparisonBytes == full.byteCount }
        host.view.layoutSubtreeIfNeeded()
        try require(model.currentPageSizeImpact != nil && model.sharedResourcesFromEarlierPages == 1,
                    "Current-page size comparison or shared-resource state is missing")
        try await wait { editing.inspection?.report.imagePlacementAnalysisComplete == true }
        model.options.colorMode = .blackAndWhite
        try await wait { model.availableMonochromeLevels == [.strong] && model.options.level == .strong }
        host.view.layoutSubtreeIfNeeded()
        let levelPickers = descendants(NSSegmentedControl.self, in: host.view).filter { $0.segmentCount == 3 }
        try require(levelPickers.contains { !$0.isEnabled }, "Ineffective monochrome compression levels remained enabled")
        print("PASS Mac compression view: fitted synchronized comparison, retained viewport, page policy editor, exact size comparison, shared-resource note, resets and disabled ineffective S/W levels")
    }
}
