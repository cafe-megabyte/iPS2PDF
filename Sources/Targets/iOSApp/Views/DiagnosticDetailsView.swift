import SwiftUI
import UIKit

struct DiagnosticDetailsView: View {
    let presentation: DiagnosticPresentation
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                Text(presentation.text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(copied ? "Copied" : "Copy") {
                        UIPasteboard.general.string = presentation.text
                        copied = true
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
