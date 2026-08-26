import SwiftUI

struct MacOSSettingsCategoryView: View {
    let category: DistillerCategory
    @ObservedObject var repository: JoboptionsRepository

    var body: some View {
        Form {
            Section(String(localized: "Active Joboptions")) {
                Picker(String(localized: "Preset"), selection: activeRecordBinding) {
                    ForEach(repository.records) { record in
                        Text(record.name).tag(Optional(record))
                    }
                }
                .pickerStyle(.menu)

                if !repository.compatibilityIssues.isEmpty {
                    GhostscriptCompatibilityBanner(repository: repository)
                }
            }

            if category == .standards {
                Section(String(localized: "PDF standard")) {
                    Picker(String(localized: "Conformance"), selection: standardBinding) {
                        ForEach(PDFStandard.allCases) { standard in
                            Text(standard.title).tag(standard)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            Section(category.title) {
                ForEach(visibleDefinitions) { definition in
                    DistillerOptionEditor(
                        definition: definition,
                        repository: repository,
                        isLocked: isLocked(definition.key)
                    )
                }
            }

            if category == .color {
                ICCProfileLibrarySection(repository: repository)
            }

            if category == .additional {
                Section("iPS2PDF") {
                    Toggle(String(localized: "Security limits"), isOn: Binding(
                        get: { repository.securityLimitsEnabled },
                        set: { repository.securityLimitsEnabled = $0 }
                    ))
                    Toggle(String(localized: "Automatic random seed"), isOn: Binding(
                        get: { repository.automaticRandomSeed },
                        set: { repository.setAutomaticRandomSeed($0) }
                    ))
                    if !repository.automaticRandomSeed {
                        TextField(String(localized: "Seed"), value: Binding(
                            get: { repository.manualRandomSeed },
                            set: { repository.setManualRandomSeed($0) }
                        ), formatter: NumberFormatter())
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(category.title)
    }

    private var visibleDefinitions: [DistillerOptionDefinition] {
        var definitions = DistillerOptionCatalog.options(in: category)
        if category == .standards {
            definitions.removeAll { $0.key == "iPS2PDFStandard" }
        }
        if category == .fonts {
            let visible = Set(["EmbedAllFonts", "EmbedSubstituteFonts", "SubsetFonts", "EmbedOpenType"])
            definitions.removeAll { !visible.contains($0.key) }
        }
        return definitions
    }

    private var activeRecordBinding: Binding<JoboptionsRecord?> {
        Binding(
            get: { repository.activeRecord },
            set: { record in
                guard let record else { return }
                do { try repository.activate(record) }
                catch { repository.lastError = error.localizedDescription }
            }
        )
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

    private func isLocked(_ key: String) -> Bool {
        guard repository.activeStandard != .none else { return false }
        return [
            "CompatibilityLevel", "EmbedAllFonts", "CannotEmbedFontPolicy",
            "PDFXOutputIntentProfile", "OutputICCProfile", "ColorConversionStrategy",
            "Encrypt", "EncryptionR", "OwnerPassword", "UserPassword", "Permissions"
        ].contains(key)
    }
}
