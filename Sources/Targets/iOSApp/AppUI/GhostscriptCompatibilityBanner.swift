import SwiftUI

struct GhostscriptCompatibilityBanner: View {
    @ObservedObject var repository: JoboptionsRepository
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .foregroundStyle(Color.appTint)
                DisclosureGroup(isExpanded: $isExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(repository.compatibilityIssues) { issue in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(issue.summary)
                                    .font(.caption.monospaced())
                                Text(issue.reason)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                if !issue.isAutomaticallyRepairable {
                                    Label(
                                        String(localized: "Manual selection required"),
                                        systemImage: "hand.raised.fill"
                                    )
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    Text(issueCountTitle)
                        .font(.subheadline.weight(.semibold))
                }
                Spacer(minLength: 8)
                Button(String(localized: "Repair")) {
                    do {
                        try repository.applyConsistencyRepairs(repository.compatibilityIssues)
                    } catch {
                        repository.lastError = error.localizedDescription
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!repository.compatibilityIssues.contains(where: { $0.isAutomaticallyRepairable }))
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.thinMaterial)
    }

    private var issueCountTitle: String {
        String.localizedStringWithFormat(
            String(localized: "%lld inconsistent settings"),
            Int64(repository.compatibilityIssues.count)
        )
    }
}
