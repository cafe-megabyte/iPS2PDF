import SwiftUI

struct AdvancedSettingsView: View {
    @ObservedObject var viewModel: ConversionViewModel
    let onShowFront: () -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selection: BackSelection? = .category(.general)

    private var repository: JoboptionsRepository { viewModel.joboptionsRepository }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Active Joboptions")
                        .font(.headline)
                    Text(repository.activeName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onShowFront) {
                    Label("Conversion", systemImage: "arrow.uturn.backward.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)

            if !repository.compatibilityIssues.isEmpty {
                GhostscriptCompatibilityBanner(repository: repository)
            }

            if horizontalSizeClass == .regular {
                regularLayout
            } else {
                compactLayout
            }
        }
    }

    private var compactLayout: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        JoboptionsManagementView(viewModel: viewModel)
                    } label: {
                        Label {
                            Text("Manage …")
                        } icon: {
                            Image(systemName: "folder")
                                .foregroundStyle(Color.appTint)
                        }
                        .font(.headline)
                        .padding(.vertical, 6)
                    }
                }

                Section("Settings") {
                    ForEach(DistillerCategory.allCases) { category in
                        NavigationLink {
                            SettingsCategoryView(category: category, viewModel: viewModel)
                        } label: {
                            SettingsNavigationLabel(verbatim: category.title, systemImage: category.systemImage)
                        }
                    }
                }
            }
            .navigationTitle("Joboptions")
        }
    }

    private var regularLayout: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    Label {
                        Text("Manage …")
                    } icon: {
                        Image(systemName: "folder")
                            .foregroundStyle(Color.appTint)
                    }
                    .font(.headline)
                    .tag(BackSelection.management)
                    .padding(.vertical, 6)
                }

                Section("Settings") {
                    ForEach(DistillerCategory.allCases) { category in
                        SettingsNavigationLabel(verbatim: category.title, systemImage: category.systemImage)
                            .tag(BackSelection.category(category))
                    }
                }
            }
            .navigationTitle("Joboptions")
        } detail: {
            switch selection ?? .category(.general) {
            case .management:
                JoboptionsManagementView(viewModel: viewModel)
            case let .category(category):
                SettingsCategoryView(category: category, viewModel: viewModel)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}
