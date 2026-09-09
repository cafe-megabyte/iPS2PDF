import SwiftUI
import Foundation

@MainActor
struct PDFProcessingLicensesView: View {
    var closeAction: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [PDFProcessingLicenseEntry] = []
    @State private var failed = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Link("iPS2PDF source code", destination: URL(string: "https://github.com/cafe-megabyte/iPS2PDF")!)
                    Link("Hyper Compress source code", destination: URL(string: "https://github.com/alam00000/bentopdf-hyper-compress")!)
                }
                if failed { Text("The bundled license notices could not be read.").foregroundStyle(.red) }
                ForEach(entries) { entry in
                    DisclosureGroup {
                        Text(entry.text).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(entry.id)
                            if !entry.license.isEmpty { Text(entry.license).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            .navigationTitle("PDF processing licenses")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { if let closeAction { closeAction() } else { dismiss() } } } }
        }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 480)
        #endif
        .task {
            do { entries = try await Task.detached { try PDFProcessingLicenseEntry.load() }.value }
            catch { failed = true }
        }
    }
}
