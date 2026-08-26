import SwiftUI

struct ProcessingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
            ProgressView()
                .controlSize(.large)
                .padding(28)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "processing"))
    }
}
