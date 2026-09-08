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
