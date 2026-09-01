import SwiftUI

struct GhostscriptCompatibilityBanner: View {
    @ObservedObject var repository: JoboptionsRepository
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Button {
                    isExpanded.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        Image(systemName: "wrench.and.screwdriver.fill")
                            .foregroundStyle(Color.appTint)
                        Text(issueCountTitle)
                            .font(.subheadline.weight(.semibold))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(
                    isExpanded
                        ? String(localized: "Collapse consistency details")
                        : String(localized: "Expand consistency details")
                )
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
                .disabled(repository.compatibilityIssues.isEmpty)
            }

            if isExpanded {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(repository.compatibilityIssues) { issue in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(issue.summary)
                                    .font(.caption.monospaced())
                                Text(issue.reason)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: detailsMaximumHeight)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.20))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.orange.opacity(0.62))
                .frame(height: 1)
        }
    }

    private var issueCountTitle: String {
        String.localizedStringWithFormat(
            String(localized: "%lld inconsistent settings"),
            Int64(repository.compatibilityIssues.count)
        )
    }

    private var detailsMaximumHeight: CGFloat {
        verticalSizeClass == .compact ? 140 : 240
    }
}
