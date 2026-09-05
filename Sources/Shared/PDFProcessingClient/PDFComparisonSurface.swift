import SwiftUI
@preconcurrency import PDFKit
import Combine

@MainActor
struct PDFComparisonSurface: View {
    let original: PDFEditingRevision
    let result: PDFEditingRevision?
    let previewPage: Int?
    let password: String?
    @Binding var currentPage: Int
    @State private var showsResult = true
    @StateObject private var synchronization = PDFComparisonSynchronization()

    var body: some View {
        GeometryReader { geometry in
            #if os(macOS)
            comparison(wide: true)
            #else
            comparison(wide: geometry.size.width >= 700)
            #endif
        }
    }
    @ViewBuilder private func comparison(wide: Bool) -> some View {
        if wide {
            HStack(spacing: 1) {
                pane(original, title: String(localized: "Original"), pageOffset: nil)
                pane(result, title: String(localized: "Result"), pageOffset: previewPage)
            }
        } else {
            VStack(spacing: 8) {
                Picker("Comparison", selection: $showsResult) {
                    Text("Original").tag(false)
                    Text("Result").tag(true)
                }.pickerStyle(.segmented).padding(.horizontal)
                pane(showsResult ? result : original,
                     title: showsResult ? String(localized: "Result") : String(localized: "Original"),
                     pageOffset: showsResult ? previewPage : nil)
            }
        }
    }
    private func pane(_ revision: PDFEditingRevision?, title: String, pageOffset: Int?) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            if let revision, pageOffset == nil || pageOffset == currentPage {
                PDFComparisonRepresentable(revision: revision, password: password, pageOffset: pageOffset,
                    synchronization: synchronization, pageChanged: { currentPage = $0 })
                    .accessibilityLabel(title)
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Preparing preview…").font(.callout).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
private final class PDFComparisonSynchronization: ObservableObject {
    private final class Entry {
        weak var view: PDFView?
        let pageOffset: Int?
        var notifications: [NSObjectProtocol] = []
        #if os(iOS)
        var scrollObservation: NSKeyValueObservation?
        #endif
        init(view: PDFView, pageOffset: Int?) { self.view = view; self.pageOffset = pageOffset }
        deinit { notifications.forEach(NotificationCenter.default.removeObserver) }
    }
    private var entries: [ObjectIdentifier: Entry] = [:]
    private var isSynchronizing = false
    private var pageIndex = 0
    private var point: CGPoint?
    private var relativeScale: CGFloat = 1
    private var pageChanged: ((Int) -> Void)?

    func register(_ view: PDFView, pageOffset: Int?, pageChanged: @escaping (Int) -> Void) {
        unregister(view)
        self.pageChanged = pageChanged
        let entry = Entry(view: view, pageOffset: pageOffset)
        entries[ObjectIdentifier(view)] = entry
        for name in [Notification.Name.PDFViewPageChanged, .PDFViewScaleChanged, .PDFViewVisiblePagesChanged] {
            entry.notifications.append(NotificationCenter.default.addObserver(forName: name, object: view, queue: .main) {
                [weak self, weak view] _ in
                MainActor.assumeIsolated { if let view { self?.changed(view) } }
            })
        }
        #if os(macOS)
        if let scroll = descendant(NSScrollView.self, of: view) {
            scroll.contentView.postsBoundsChangedNotifications = true
            entry.notifications.append(NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
                object: scroll.contentView, queue: .main) { [weak self, weak view] _ in
                    MainActor.assumeIsolated { if let view { self?.changed(view) } }
                })
        }
        #else
        if let scroll = descendant(UIScrollView.self, of: view) {
            entry.scrollObservation = scroll.observe(\.contentOffset, options: [.new]) { [weak self, weak view] _, _ in
                MainActor.assumeIsolated { if let view { self?.changed(view) } }
            }
        }
        #endif
        isSynchronizing = true
        restore(entry)
        isSynchronizing = false
    }
    func unregister(_ view: PDFView) { entries.removeValue(forKey: ObjectIdentifier(view)) }
    private func changed(_ source: PDFView) {
        guard !isSynchronizing, let entry = entries[ObjectIdentifier(source)],
              let document = source.document, let destination = source.currentDestination,
              let page = destination.page else { return }
        let index = document.index(for: page)
        guard index != NSNotFound else { return }
        pageIndex = entry.pageOffset ?? index
        point = destination.point
        let fit = source.scaleFactorForSizeToFit
        if fit > 0 { relativeScale = source.scaleFactor / fit }
        isSynchronizing = true
        for other in entries.values where other.view !== source { restore(other) }
        isSynchronizing = false
        let current = pageIndex
        // PDFKit may notify while SwiftUI is installing a new document.
        Task { @MainActor [weak self] in self?.pageChanged?(current) }
    }
    private func restore(_ entry: Entry) {
        guard let view = entry.view, let document = view.document,
              entry.pageOffset == nil || entry.pageOffset == pageIndex,
              let page = document.page(at: entry.pageOffset == nil ? min(pageIndex, max(0, document.pageCount - 1)) : 0) else { return }
        let fit = view.scaleFactorForSizeToFit
        if fit > 0 { view.scaleFactor = fit * relativeScale }
        if let point { view.go(to: PDFDestination(page: page, at: point)) }
        else { view.go(to: page) }
    }
    #if os(macOS)
    private func descendant<T: NSView>(_ type: T.Type, of view: NSView) -> T? {
        for child in view.subviews { if let value = child as? T { return value }; if let value = descendant(type, of: child) { return value } }
        return nil
    }
    #else
    private func descendant<T: UIView>(_ type: T.Type, of view: UIView) -> T? {
        for child in view.subviews { if let value = child as? T { return value }; if let value = descendant(type, of: child) { return value } }
        return nil
    }
    #endif
}

@MainActor
private struct PDFComparisonRepresentable {
    let revision: PDFEditingRevision
    let password: String?
    let pageOffset: Int?
    let synchronization: PDFComparisonSynchronization
    let pageChanged: (Int) -> Void
    final class Coordinator {
        var revisionID: UUID?
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
        guard coordinator.revisionID != revision.id else { return }
        synchronization.unregister(view)
        let document = PDFDocument(url: revision.input.url)
        if let password, document?.isLocked == true { document?.unlock(withPassword: password) }
        coordinator.revisionID = revision.id
        view.document = document
        view.autoScales = true
        #if os(macOS)
        view.layoutSubtreeIfNeeded()
        #else
        view.layoutIfNeeded()
        #endif
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
