import Combine
import CoreText
import PDFKit
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
struct PDFSignatureCanvas: View {
    @ObservedObject var session: PDFSignatureEditingSession

    var body: some View {
        PDFSignatureRepresentable(session: session)
    }
}

@MainActor
private final class PDFSignatureCanvasCoordinator: NSObject {
    private struct Drag {
        let id: UUID
        let pageIndex: Int
        let startPoint: CGPoint
        let startBaseline: CGPoint
    }

    let session: PDFSignatureEditingSession
    weak var view: SignaturePDFView?
    private weak var overlay: SignatureOverlayView?
    private var drag: Drag?
    private var resizeStart: Double?
    private var displayedPlacements: [PDFSignaturePlacement]
    private var displayedSelectedID: UUID?
    private var subscriptions: Set<AnyCancellable> = []
    private var notifications: [NSObjectProtocol] = []
    #if os(iOS)
    private var scrollObservation: NSKeyValueObservation?
    #endif

    init(session: PDFSignatureEditingSession) {
        self.session = session
        displayedPlacements = session.placements
        displayedSelectedID = session.selectedID
    }

    func configure(_ view: SignaturePDFView) {
        self.view = view
        view.interaction = self
        view.autoScales = true
        view.minScaleFactor = 0.1
        view.maxScaleFactor = 12
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        loadDocumentIfNeeded()
        installOverlay(on: view)
        observeViewport(of: view)
        observeSession()
        refresh()
        #if os(macOS)
        view.scheduleInitialPageFit()
        #endif
    }

    func teardown() {
        notifications.forEach(NotificationCenter.default.removeObserver)
        notifications.removeAll()
        #if os(iOS)
        scrollObservation = nil
        #endif
        subscriptions.removeAll()
        overlay?.removeFromSuperview()
        overlay = nil
        view?.interaction = nil
        view = nil
    }

    func loadDocumentIfNeeded() {
        guard let view, view.document?.documentURL != session.input.input.url else { return }
        let document = PDFDocument(url: session.input.input.url)
        if let password = session.editing.passwordForProcessing, document?.isLocked == true {
            document?.unlock(withPassword: password)
        }
        view.document = document
        view.autoScales = true
    }

    func refresh() {
        overlay?.invalidate()
    }

    func tap(at viewPoint: CGPoint) {
        guard let view, let page = view.page(for: viewPoint, nearest: false),
              let document = view.document else { return }
        let pagePoint = view.convert(viewPoint, to: page)
        if let id = hit(page: page, point: pagePoint) {
            session.select(id)
        } else {
            let pageIndex = document.index(for: page)
            guard pageIndex != NSNotFound else { return }
            _ = session.add(pageIndex: pageIndex, centeredAt: pagePoint)
        }
        refresh()
    }

    func canBeginMove(at viewPoint: CGPoint) -> Bool {
        guard let view, let page = view.page(for: viewPoint, nearest: false) else { return false }
        return hit(page: page, point: view.convert(viewPoint, to: page)) != nil
    }

    @discardableResult
    func beginMove(at viewPoint: CGPoint) -> Bool {
        guard let view, let document = view.document,
              let page = view.page(for: viewPoint, nearest: false) else { return false }
        let pagePoint = view.convert(viewPoint, to: page)
        guard let id = hit(page: page, point: pagePoint), let placement = session.placement(id: id) else { return false }
        let pageIndex = document.index(for: page)
        guard pageIndex != NSNotFound else { return false }
        session.select(id)
        drag = Drag(id: id, pageIndex: pageIndex, startPoint: pagePoint,
                    startBaseline: CGPoint(x: placement.x, y: placement.y))
        refresh()
        return true
    }

    func continueMove(at viewPoint: CGPoint) {
        guard let drag, let view, let page = view.document?.page(at: drag.pageIndex) else { return }
        let point = view.convert(viewPoint, to: page)
        session.move(drag.id, baseline: CGPoint(x: drag.startBaseline.x + point.x - drag.startPoint.x,
                                                y: drag.startBaseline.y + point.y - drag.startPoint.y))
        refresh()
    }

    func endMove() { drag = nil }

    func canBeginResize(at viewPoint: CGPoint) -> Bool {
        guard let selected = session.selectedID, let view,
              let page = view.page(for: viewPoint, nearest: false) else { return false }
        return hit(page: page, point: view.convert(viewPoint, to: page)) == selected
    }

    func beginResize() { resizeStart = session.selectedFontSize }

    func continueResize(scale: CGFloat) {
        guard let resizeStart else { return }
        session.resizeSelected(to: resizeStart * max(0.05, scale))
        refresh()
    }

    func resizeIncrementally(by scale: CGFloat) {
        session.resizeSelected(to: session.selectedFontSize * max(0.05, scale))
        refresh()
    }

    func endResize() { resizeStart = nil }

    func removeSelected() { session.removeSelected(); refresh() }

    func drawOverlay(in context: CGContext, overlay: SignatureOverlayView) {
        guard let view, let document = view.document else { return }
        for placement in displayedPlacements where (0..<document.pageCount).contains(placement.pageIndex) {
            guard let page = document.page(at: placement.pageIndex) else { continue }
            func convert(_ point: CGPoint) -> CGPoint {
                overlay.convert(view.convert(point, from: page), from: view)
            }
            let origin = convert(.zero)
            let unitX = convert(CGPoint(x: 1, y: 0))
            let unitY = convert(CGPoint(x: 0, y: 1))
            let transform = CGAffineTransform(
                a: unitX.x - origin.x, b: unitX.y - origin.y,
                c: unitY.x - origin.x, d: unitY.y - origin.y,
                tx: origin.x, ty: origin.y
            )
            let determinant = transform.a * transform.d - transform.b * transform.c
            guard abs(determinant) > 0.000_001 else { continue }
            context.saveGState()
            context.concatenate(transform)
            var glyph = session.font.glyph
            var position = CGPoint(x: placement.x, y: placement.y)
            #if os(macOS)
            context.setFillColor(NSColor.black.cgColor)
            #else
            context.setFillColor(UIColor.black.cgColor)
            #endif
            CTFontDrawGlyphs(session.font.coreTextFont(size: placement.fontSize), &glyph, &position, 1, context)
            if displayedSelectedID == placement.id {
                #if os(macOS)
                context.setStrokeColor(NSColor.controlAccentColor.cgColor)
                context.setFillColor(NSColor.controlAccentColor.cgColor)
                #else
                context.setStrokeColor(UIColor.systemBlue.cgColor)
                context.setFillColor(UIColor.systemBlue.cgColor)
                #endif
                let line = max(1 / max(view.scaleFactor, 0.1), placement.fontSize / 75)
                let bounds = session.glyphBounds(for: placement)
                context.setLineWidth(line)
                context.setLineDash(phase: 0, lengths: [4 * line, 3 * line])
                context.stroke(bounds.insetBy(dx: -2 * line, dy: -2 * line))
                context.setLineDash(phase: 0, lengths: [])
                let radius = max(2.5 / max(view.scaleFactor, 0.1), placement.fontSize / 30)
                for point in [
                    CGPoint(x: bounds.minX, y: bounds.minY), CGPoint(x: bounds.maxX, y: bounds.minY),
                    CGPoint(x: bounds.minX, y: bounds.maxY), CGPoint(x: bounds.maxX, y: bounds.maxY),
                ] {
                    context.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius,
                                                   width: radius * 2, height: radius * 2))
                }
            }
            context.restoreGState()
        }
    }

    private func hit(page: PDFPage, point: CGPoint) -> UUID? {
        guard let document = view?.document else { return nil }
        let pageIndex = document.index(for: page)
        guard pageIndex != NSNotFound else { return nil }
        let padding = 8 / max(view?.scaleFactor ?? 1, 0.1)
        return session.placements.reversed().first {
            $0.pageIndex == pageIndex &&
                session.glyphBounds(for: $0).insetBy(dx: -padding, dy: -padding).contains(point)
        }?.id
    }

    private func installOverlay(on view: SignaturePDFView) {
        let overlay = SignatureOverlayView()
        overlay.coordinator = self
        overlay.frame = view.bounds
        #if os(macOS)
        overlay.autoresizingMask = [.width, .height]
        overlay.wantsLayer = true
        view.addSubview(overlay, positioned: .above, relativeTo: nil)
        #else
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.backgroundColor = .clear
        overlay.isUserInteractionEnabled = false
        view.addSubview(overlay)
        #endif
        self.overlay = overlay
    }

    private func observeViewport(of view: SignaturePDFView) {
        for name in [Notification.Name.PDFViewPageChanged, .PDFViewScaleChanged, .PDFViewVisiblePagesChanged] {
            notifications.append(NotificationCenter.default.addObserver(forName: name, object: view, queue: .main) {
                [weak self] _ in MainActor.assumeIsolated { self?.refresh() }
            })
        }
        #if os(macOS)
        if let scroll = descendant(NSScrollView.self, of: view) {
            scroll.contentView.postsBoundsChangedNotifications = true
            notifications.append(NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } })
        }
        #else
        if let scroll = descendant(UIScrollView.self, of: view) {
            scrollObservation = scroll.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        #endif
    }

    private func observeSession() {
        session.$placements.sink { [weak self] placements in
            MainActor.assumeIsolated {
                self?.displayedPlacements = placements
                self?.overlay?.invalidate()
            }
        }.store(in: &subscriptions)
        session.$selectedID.sink { [weak self] selectedID in
            MainActor.assumeIsolated {
                self?.displayedSelectedID = selectedID
                self?.overlay?.invalidate()
            }
        }.store(in: &subscriptions)
    }

    #if os(macOS)
    private func descendant<T: NSView>(_ type: T.Type, of view: NSView) -> T? {
        for child in view.subviews {
            if let value = child as? T { return value }
            if let value = descendant(type, of: child) { return value }
        }
        return nil
    }
    #else
    private func descendant<T: UIView>(_ type: T.Type, of view: UIView) -> T? {
        for child in view.subviews {
            if let value = child as? T { return value }
            if let value = descendant(type, of: child) { return value }
        }
        return nil
    }
    #endif
}

#if os(macOS)
@MainActor
private final class SignatureOverlayView: NSView {
    weak var coordinator: PDFSignatureCanvasCoordinator?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func invalidate() {
        needsDisplay = true
        layer?.setNeedsDisplay()
        displayIfNeeded()
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        coordinator?.drawOverlay(in: context, overlay: self)
    }
}

@MainActor
private final class SignaturePDFView: PDFView {
    weak var interaction: PDFSignatureCanvasCoordinator?
    override var acceptsFirstResponder: Bool { true }
    private var initialPageFitTask: Task<Void, Never>?

    func scheduleInitialPageFit() {
        initialPageFitTask?.cancel()
        initialPageFitTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled, let self, let page = document?.page(at: 0) else { return }
            window?.contentView?.layoutSubtreeIfNeeded()
            layoutSubtreeIfNeeded()
            layoutDocumentView()
            let pageBounds = page.bounds(for: .cropBox)
            guard bounds.width > 40, bounds.height > 40,
                  pageBounds.width > 0, pageBounds.height > 0 else { return }
            let fitted = min((bounds.width - 40) / pageBounds.width,
                             (bounds.height - 40) / pageBounds.height)
            guard fitted.isFinite, fitted > 0 else { return }
            autoScales = false
            scaleFactor = min(max(fitted, minScaleFactor), maxScaleFactor)
            go(to: page)
            initialPageFitTask = nil
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        window?.makeFirstResponder(self)
        if interaction?.beginMove(at: point) != true { interaction?.tap(at: point) }
    }

    override func mouseDragged(with event: NSEvent) {
        interaction?.continueMove(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) { interaction?.endMove() }

    override func magnify(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if interaction?.canBeginResize(at: point) == true {
            interaction?.resizeIncrementally(by: 1 + event.magnification)
        } else {
            super.magnify(with: event)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 { interaction?.removeSelected() }
        else { super.keyDown(with: event) }
    }
}
#else
@MainActor
private final class SignatureOverlayView: UIView {
    weak var coordinator: PDFSignatureCanvasCoordinator?
    func invalidate() { setNeedsDisplay() }
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        coordinator?.drawOverlay(in: context, overlay: self)
    }
}

@MainActor
private final class SignaturePDFView: PDFView {
    weak var interaction: PDFSignatureCanvasCoordinator?
}

extension PDFSignatureCanvasCoordinator: UIGestureRecognizerDelegate {
    func installGestures(on view: SignaturePDFView) {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pan.delegate = self
        pinch.delegate = self
        tap.require(toFail: pan)
        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(pinch)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let view = gestureRecognizer.view as? SignaturePDFView else { return false }
        let point = gestureRecognizer.location(in: view)
        if gestureRecognizer is UIPanGestureRecognizer { return canBeginMove(at: point) }
        if gestureRecognizer is UIPinchGestureRecognizer { return canBeginResize(at: point) }
        return true
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended, let view = gesture.view else { return }
        tap(at: gesture.location(in: view))
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let view = gesture.view else { return }
        let point = gesture.location(in: view)
        switch gesture.state {
        case .began: _ = beginMove(at: point)
        case .changed: continueMove(at: point)
        default: endMove()
        }
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began: beginResize()
        case .changed: continueResize(scale: gesture.scale)
        default: endResize()
        }
    }
}
#endif

@MainActor
private struct PDFSignatureRepresentable {
    let session: PDFSignatureEditingSession

    func makeCoordinator() -> PDFSignatureCanvasCoordinator { PDFSignatureCanvasCoordinator(session: session) }

    func makeView(coordinator: PDFSignatureCanvasCoordinator) -> SignaturePDFView {
        let view = SignaturePDFView()
        coordinator.configure(view)
        #if os(iOS)
        coordinator.installGestures(on: view)
        #endif
        return view
    }

    func update(_ view: SignaturePDFView, coordinator: PDFSignatureCanvasCoordinator) {
        coordinator.loadDocumentIfNeeded()
        coordinator.refresh()
    }
}

#if os(macOS)
extension PDFSignatureRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> SignaturePDFView { makeView(coordinator: context.coordinator) }
    func updateNSView(_ view: SignaturePDFView, context: Context) { update(view, coordinator: context.coordinator) }
    static func dismantleNSView(_ view: SignaturePDFView, coordinator: PDFSignatureCanvasCoordinator) {
        coordinator.teardown()
    }
}
#else
extension PDFSignatureRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> SignaturePDFView { makeView(coordinator: context.coordinator) }
    func updateUIView(_ view: SignaturePDFView, context: Context) { update(view, coordinator: context.coordinator) }
    static func dismantleUIView(_ view: SignaturePDFView, coordinator: PDFSignatureCanvasCoordinator) {
        coordinator.teardown()
    }
}
#endif
