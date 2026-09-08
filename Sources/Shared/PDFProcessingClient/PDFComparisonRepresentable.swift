import SwiftUI
@preconcurrency import PDFKit

@MainActor
struct PDFComparisonRepresentable {
    let revision: PDFEditingRevision
    let password: String?
    let pageOffset: Int?
    let synchronization: PDFComparisonSynchronization
    let pageChanged: (Int) -> Void
    final class Coordinator {
        var revisionID: UUID?
        var pageOffset: Int?
        let synchronization: PDFComparisonSynchronization
        init(_ synchronization: PDFComparisonSynchronization) { self.synchronization = synchronization }
    }
    func makeCoordinator() -> Coordinator { Coordinator(synchronization) }
    func makeView() -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        return view
    }
    func update(_ view: PDFView, coordinator: Coordinator) {
        let replacesDocument = coordinator.revisionID != revision.id
        guard replacesDocument || coordinator.pageOffset != pageOffset else { return }
        synchronization.unregister(view)
        if replacesDocument {
            let document = PDFDocument(url: revision.input.url)
            if let password, document?.isLocked == true { document?.unlock(withPassword: password) }
            view.document = document
            view.autoScales = true
            #if os(macOS)
            view.layoutSubtreeIfNeeded()
            #else
            view.layoutIfNeeded()
            #endif
        }
        coordinator.revisionID = revision.id
        coordinator.pageOffset = pageOffset
        synchronization.register(view, pageOffset: pageOffset, pageChanged: pageChanged)
    }
}

#if os(macOS)
extension PDFComparisonRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> PDFView { makeView() }
    func updateNSView(_ view: PDFView, context: Context) { update(view, coordinator: context.coordinator) }
    static func dismantleNSView(_ view: PDFView, coordinator: Coordinator) { coordinator.synchronization.unregister(view) }
}
#else
extension PDFComparisonRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> PDFView { makeView() }
    func updateUIView(_ view: PDFView, context: Context) { update(view, coordinator: context.coordinator) }
    static func dismantleUIView(_ view: PDFView, coordinator: Coordinator) { coordinator.synchronization.unregister(view) }
}
#endif
