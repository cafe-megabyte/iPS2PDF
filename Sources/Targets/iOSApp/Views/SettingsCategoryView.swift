import SwiftUI

struct SettingsCategoryView: View {
    let category: DistillerCategory
    @ObservedObject var viewModel: ConversionViewModel
    @State private var showsPDFXOutputIntentNotice = false

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
                        repository: repository,
                        isLocked: isLocked(definition)
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
        .alert(
            "PDF/X output intent",
            isPresented: $showsPDFXOutputIntentNotice
        ) {
            Button("OK") {}
        } message: {
            Text("Generic CMYK Profile has been selected as the PDF/X output intent. Check whether this profile matches the intended print condition.")
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
            let checkboxes = Set(["EmbedAllFonts", "EmbedSubstituteFonts", "SubsetFonts", "EmbedOpenType"])
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
                ForEach(PDFStandard.allCases) { standard in
                    Text(standard.title).tag(standard)
                }
            }
            .pickerStyle(.menu)

            if repository.activeStandard != .none {
                Label(
                    String(localized: "Required PDF version, encryption, font embedding, output intent and color-space changes are listed as repairable consistency settings."),
                    systemImage: "lock.fill"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
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
        return (repository.activeDocument?.keys ?? [])
            .subtracting(catalogued)
            .sorted()
    }

    private var standardBinding: Binding<PDFStandard> {
        Binding(
            get: { repository.activeStandard },
            set: { standard in
                do {
                    let showsNotice = try repository.setStandard(standard)
                    if showsNotice {
                        showsPDFXOutputIntentNotice = true
                    }
                }
                catch { repository.lastError = error.localizedDescription }
            }
        )
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

    private func isLocked(_ definition: DistillerOptionDefinition) -> Bool {
        repository.activeStandard != .none && definition.isDisabledBySelectedStandard
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
