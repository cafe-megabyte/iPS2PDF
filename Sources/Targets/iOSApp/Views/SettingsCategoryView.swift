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

            if category == .additional {
                applicationSection
            }

            Section {
                ForEach(visibleDefinitions) { definition in
                    DistillerOptionEditor(
                        definition: definition,
                        repository: repository
                    )
                }
            } header: {
                if category == .additional {
                    Text("Known additional settings")
                }
            } footer: {
                Text("The catalogue targets Ghostscript \(DistillerOptionCatalog.ghostscriptVersion). Missing settings are inserted into the active user Joboptions; unrelated source bytes stay unchanged.")
            }

            if category == .color {
                ICCProfileLibrarySection(repository: repository)
            }

            if category == .additional {
                additionalDetailsSection
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
        var definitions: [DistillerOptionDefinition]
        if category == .additional {
            definitions = DistillerOptionCatalog.options.filter {
                $0.classification == .knownAdditional
            }
        } else {
            definitions = DistillerOptionCatalog.options(in: category).filter {
                $0.classification == .distillerControl
            }
        }
        if category == .standards {
            definitions.removeAll { $0.key == "iPS2PDFStandard" }
        }
        if category == .fonts {
            let checkboxes = Set(["EmbedAllFonts", "EmbedSubstituteFonts", "SubsetFonts"])
            definitions.removeAll { !checkboxes.contains($0.key) }
        }
        return definitions.filter {
            if case .companion = $0.semanticEditor { return false }
            return true
        }
    }

    private var standardSection: some View {
        Section("PDF standard") {
            Picker("Conformance", selection: standardBinding) {
                if PDFStandard(rawValue: standardText) == nil {
                    Text(String.localizedStringWithFormat(
                        String(localized: "Custom: %@"), standardText
                    )).tag(Optional<PDFStandard>.none)
                }
                ForEach(PDFStandard.allCases) { standard in
                    Text(standard.title).tag(Optional(standard))
                }
            }
            .pickerStyle(.menu)

        }
    }

    private var applicationSection: some View {
        Section("iPS2PDF") {
            Toggle("Embed output intent profile", isOn: Binding(
                get: {
                    guard let document = repository.activeDocument else { return false }
                    return SemanticJoboptions.embedsOutputIntentProfile(in: document)
                },
                set: { value in
                    do {
                        try repository.apply(
                            SemanticJoboptions.changeEmbedsOutputIntentProfile(value)
                        )
                    } catch {
                        repository.lastError = error.localizedDescription
                    }
                }
            ))

            Toggle("Security limits", isOn: Binding(
                get: { repository.securityLimitsEnabled },
                set: { repository.securityLimitsEnabled = $0 }
            ))
            Text("Enabled by default: 15 minutes, 1 GB PostScript input and 2 GB PDF output. Process isolation, SAFER, diagnostics, cancellation and PDF validation always remain active.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Toggle("Random numbers", isOn: Binding(
                get: { repository.automaticRandomSeed },
                set: { repository.setAutomaticRandomSeed($0) }
            ))

            if !repository.automaticRandomSeed {
                LabeledContent("Seed") {
                    TextField(
                        "Seed",
                        value: manualRandomSeedBinding,
                        formatter: randomSeedFormatter
                    )
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                }
                Text(Self.randomSeedRangeDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var additionalDetailsSection: some View {
        Group {
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
            .union(DistillerOptionCatalog.uiHiddenPreservedKeys)
        return (repository.activeDocument?.keys ?? [])
            .subtracting(catalogued)
            .sorted()
    }

    private var standardBinding: Binding<PDFStandard?> {
        Binding(
            get: { PDFStandard(rawValue: standardText) },
            set: { standard in
                guard let standard else { return }
                do {
                    try repository.setStandard(standard)
                }
                catch { repository.lastError = error.localizedDescription }
            }
        )
    }

    private var standardText: String {
        let value = JoboptionsConsistencyEngine.displayValue(
            forKey: "iPS2PDFStandard", in: repository.activeDocument,
            context: repository.consistencyAnalysisContext
        )
        return value?.textualValue ?? value?.postScript ?? "none"
    }

    private var manualRandomSeedBinding: Binding<Int> {
        Binding(
            get: { repository.manualRandomSeed },
            set: { repository.setManualRandomSeed($0) }
        )
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { repository.lastError != nil },
            set: { if !$0 { repository.lastError = nil } }
        )
    }

    private var randomSeedFormatter: NumberFormatter {
        Self.makeRandomSeedFormatter()
    }

    private static func makeRandomSeedFormatter() -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.allowsFloats = false
        formatter.minimum = NSNumber(value: PostScriptRandomSeedSettings.range.lowerBound)
        formatter.maximum = NSNumber(value: PostScriptRandomSeedSettings.range.upperBound)
        return formatter
    }

    private static func formattedSeed(_ seed: Int) -> String {
        makeRandomSeedFormatter().string(from: NSNumber(value: seed)) ?? String(seed)
    }

    private static var randomSeedRangeDescription: String {
        String(
            format: String(localized: "Allowed range: %@ - %@"),
            formattedSeed(PostScriptRandomSeedSettings.range.lowerBound),
            formattedSeed(PostScriptRandomSeedSettings.range.upperBound)
        )
    }
}
