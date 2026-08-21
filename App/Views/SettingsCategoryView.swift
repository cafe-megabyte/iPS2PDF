import SwiftUI

struct SettingsCategoryView: View {
    let category: DistillerCategory
    @ObservedObject var viewModel: ConversionViewModel

    private var repository: JoboptionsRepository { viewModel.joboptionsRepository }

    var body: some View {
        Form {
            if category == .standards {
                standardSection
            }

            Section {
                ForEach(visibleDefinitions) { definition in
                    DistillerOptionEditor(
                        definition: definition,
                        repository: repository,
                        isLocked: isLocked(definition.key)
                    )
                }
            } footer: {
                Text("The catalogue targets Ghostscript \(DistillerOptionCatalog.ghostscriptVersion). Missing settings are inserted into the active user Joboptions; unrelated source bytes stay unchanged.")
            }

            if category == .color {
                ICCProfileLibrarySection(repository: repository)
            }

            if category == .additional {
                additionalSection
            }
        }
        .formStyle(.grouped)
        .navigationTitle(category.title)
        .alert("Joboptions", isPresented: errorIsPresented) {
            Button("OK") { repository.lastError = nil }
        } message: {
            Text(repository.lastError ?? "")
        }
    }

    private var visibleDefinitions: [DistillerOptionDefinition] {
        var definitions = DistillerOptionCatalog.options(in: category)
        if category == .standards {
            definitions.removeAll { $0.key == "iPS2PDFStandard" }
        }
        if category == .fonts {
            let checkboxes = Set(["EmbedAllFonts", "EmbedSubstituteFonts", "SubsetFonts", "EmbedOpenType"])
            definitions.removeAll { !checkboxes.contains($0.key) }
        }
        return definitions
    }

    private var standardSection: some View {
        Section("PDF standard") {
            Picker("Conformance", selection: standardBinding) {
                ForEach(PDFStandard.allCases) { standard in
                    Text(standard.title).tag(standard)
                }
            }
            .pickerStyle(.menu)

            if repository.activeStandard != .none {
                Label(
                    "Mandatory PDF version, encryption, font embedding, output intent and color-space dependencies are locked by the selected standard.",
                    systemImage: "lock.fill"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var additionalSection: some View {
        Group {
            Section("iPS2PDF") {
                Toggle("Security limits", isOn: Binding(
                    get: { repository.securityLimitsEnabled },
                    set: { repository.securityLimitsEnabled = $0 }
                ))
                Text("Enabled by default: 15 minutes, 1 GB PostScript input and 2 GB PDF output. Process isolation, SAFER, diagnostics, cancellation and PDF validation always remain active.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !additionalKeys.isEmpty {
                Section {
                    ForEach(additionalKeys, id: \.self) { key in
                        GenericJoboptionsValueEditor(key: key, repository: repository)
                    }
                } header: {
                    Text("Preserved settings")
                } footer: {
                    Text("These recognizable keys are preserved even though they have no dedicated Distiller control.")
                }
            }

            Section("Original source") {
                DisclosureGroup("Show preserved PostScript") {
                    ScrollView([.horizontal, .vertical]) {
                        Text(repository.activeDocument?.sourceText ?? "")
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 220)
                }
                if repository.activeDocument?.hasUnclassifiedFragments == true {
                    Label("Unclassified PostScript fragments are read-only and are preserved byte-for-byte.", systemImage: "exclamationmark.shield")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var additionalKeys: [String] {
        let catalogued = Set(DistillerOptionCatalog.options.map(\.key))
        return (repository.activeDocument?.keys ?? [])
            .subtracting(catalogued)
            .sorted()
    }

    private var standardBinding: Binding<PDFStandard> {
        Binding(
            get: { repository.activeStandard },
            set: { standard in
                do { try repository.setStandard(standard) }
                catch { repository.lastError = error.localizedDescription }
            }
        )
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { repository.lastError != nil },
            set: { if !$0 { repository.lastError = nil } }
        )
    }

    private func isLocked(_ key: String) -> Bool {
        guard repository.activeStandard != .none else { return false }
        return [
            "CompatibilityLevel", "EmbedAllFonts", "CannotEmbedFontPolicy",
            "PDFXOutputIntentProfile", "OutputICCProfile", "ColorConversionStrategy",
            "Encrypt", "EncryptionR", "OwnerPassword", "UserPassword", "Permissions"
        ].contains(key)
    }
}
