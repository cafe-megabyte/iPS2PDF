import SwiftUI

struct MacOSSettingsView: View {
    @ObservedObject var repository: JoboptionsRepository
    @State private var selectedCategory: DistillerCategory = .general
    @State private var showsManagement = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedCategory) {
                Section {
                    Button {
                        showsManagement = true
                    } label: {
                        Label(String(localized: "Manage Joboptions..."), systemImage: "folder")
                    }
                }

                Section(String(localized: "Settings")) {
                    ForEach(DistillerCategory.allCases) { category in
                        Label(category.title, systemImage: category.systemImage)
                            .tag(category)
                    }
                }
            }
            .navigationTitle("iPS2PDF")
        } detail: {
            MacOSSettingsCategoryView(
                category: selectedCategory,
                repository: repository
            )
        }
        .sheet(isPresented: $showsManagement) {
            MacOSJoboptionsManagementView(repository: repository)
                .frame(minWidth: 620, minHeight: 520)
        }
        .alert(String(localized: "Joboptions"), isPresented: Binding(
            get: { repository.lastError != nil },
            set: { if !$0 { repository.lastError = nil } }
        )) {
            Button(String(localized: "OK")) { repository.lastError = nil }
        } message: {
            Text(repository.lastError ?? "")
        }
    }
}
