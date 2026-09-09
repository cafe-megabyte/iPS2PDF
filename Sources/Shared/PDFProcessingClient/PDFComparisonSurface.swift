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
    let paperSample: PDFPaperSample?
    let isChoosingPaperArea: Bool
    let paperSampled: (PDFPaperSample) -> Void
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
                pane(original, title: String(localized: "Original"), pageOffset: nil,
                     allowsPaperSelection: true)
                pane(result, title: String(localized: "Result"), pageOffset: previewPage,
                     allowsPaperSelection: false)
            }
        } else {
            VStack(spacing: 8) {
                Picker("Comparison", selection: $showsResult) {
                    Text("Original").tag(false)
                    Text("Result").tag(true)
                }.pickerStyle(.segmented).padding(.horizontal)
                pane(showsResult ? result : original,
                     title: showsResult ? String(localized: "Result") : String(localized: "Original"),
                     pageOffset: showsResult ? previewPage : nil,
                     allowsPaperSelection: !showsResult)
            }
            .onChange(of: isChoosingPaperArea) { _, choosing in
                if choosing { showsResult = false }
            }
        }
    }
    private func pane(_ revision: PDFEditingRevision?, title: String, pageOffset: Int?,
                      allowsPaperSelection: Bool) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            if let revision, pageOffset == nil || pageOffset == currentPage {
                ZStack(alignment: .top) {
                    PDFComparisonRepresentable(
                        revision: revision, password: password, pageOffset: pageOffset,
                        synchronization: synchronization,
                        paperSample: allowsPaperSelection ? paperSample : nil,
                        isChoosingPaperArea: allowsPaperSelection && isChoosingPaperArea,
                        pageChanged: { currentPage = $0 }, paperSampled: paperSampled
                    )
                    .accessibilityLabel(title)
                    if allowsPaperSelection && isChoosingPaperArea {
                        Label("Tap an unprinted paper area", systemImage: "scope")
                            .font(.callout.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(.regularMaterial, in: Capsule())
                            .padding(8)
                            .allowsHitTesting(false)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Preparing preview…").font(.callout).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
