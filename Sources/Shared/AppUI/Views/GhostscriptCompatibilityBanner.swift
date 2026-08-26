import SwiftUI

struct GhostscriptCompatibilityBanner: View {
    @ObservedObject var repository: JoboptionsRepository

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .foregroundStyle(Color.appTint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Compatibility adjustments")
                        .font(.subheadline.weight(.semibold))
                    Text("The current PDF version requires temporary conversion adjustments. The active Joboptions remain unchanged unless you apply them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(issueSummary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("Apply") {
                    do {
                        try repository.applyGhostscriptCompatibilityAdjustments()
                    } catch {
                        repository.lastError = error.localizedDescription
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.thinMaterial)
    }

    private var issueSummary: String {
        repository.compatibilityIssues
            .map(\.summary)
            .joined(separator: "\n")
    }
}
