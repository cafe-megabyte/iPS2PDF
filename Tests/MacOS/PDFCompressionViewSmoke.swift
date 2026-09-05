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
        let preview = try PDFEditingRevision(input: PDFInspectionInput(sourceURL: folder.appendingPathComponent("Compression-Shared-Preview.pdf")))
        let model = try PDFCompressionSession(editing: editing) { _, _, _, page in page == nil ? full : preview }
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
        print("PASS Mac compression view: page 1 initially fitted; actual original/result PDFs, side-by-side layout, synchronized page/zoom/scroll and usable compact viewports")
    }
}
