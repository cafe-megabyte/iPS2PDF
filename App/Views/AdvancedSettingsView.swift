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
                                .foregroundStyle(AppTint.color)
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
                            .foregroundStyle(AppTint.color)
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

private struct GhostscriptCompatibilityBanner: View {
    @ObservedObject var repository: JoboptionsRepository

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .foregroundStyle(AppTint.color)
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

private enum BackSelection: Hashable {
    case management
    case category(DistillerCategory)
}

private struct SettingsNavigationLabel: View {
    let title: Text
    let systemImage: String

    init(_ titleKey: LocalizedStringKey, systemImage: String) {
        self.title = Text(titleKey)
        self.systemImage = systemImage
    }

    init(verbatim title: String, systemImage: String) {
        self.title = Text(title)
        self.systemImage = systemImage
    }

    var body: some View {
        Label {
            title
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(AppTint.color)
        }
    }
}

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

private struct DistillerOptionEditor: View {
    let definition: DistillerOptionDefinition
    @ObservedObject var repository: JoboptionsRepository
    let isLocked: Bool
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            control
            if let note = definition.localizedCompatibilityNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Text(definition.localizedHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(isLocked)
        .opacity(isLocked ? 0.65 : 1)
        .onAppear { draft = currentText }
        .onChange(of: currentText) { _, value in draft = value }
    }

    @ViewBuilder
    private var control: some View {
        switch definition.kind {
        case .boolean:
            Toggle(definition.localizedTitle, isOn: booleanBinding)
        case let .name(choices):
            Picker(definition.localizedTitle, selection: nameBinding(default: choices.first ?? "None")) {
                ForEach(choices, id: \.self) { choice in
                    Text(localizedChoice(choice)).tag(choice)
                }
            }
            .pickerStyle(.menu)
        case let .literal(choices):
            Picker(definition.localizedTitle, selection: literalBinding(default: choices.first ?? "0")) {
                ForEach(choices, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
        case let .integer(range):
            LabeledContent(definition.localizedTitle) {
                TextField("Value", text: $draft)
                    .keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.trailing)
                    .onSubmit { commitInteger(range: range) }
            }
        case let .number(range):
            LabeledContent(definition.localizedTitle) {
                TextField("Value", text: $draft)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .onSubmit { commitNumber(range: range) }
            }
        case .string:
            if isProfileSetting {
                Picker(definition.localizedTitle, selection: profileBinding) {
                    if !currentText.isEmpty,
                       !profileCandidates.contains(where: { $0.name == currentText }) {
                        Text(currentText).tag(currentText)
                    }
                    ForEach(profileCandidates) { profile in
                        Text(profile.name).tag(profile.name)
                    }
                }
                .pickerStyle(.menu)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(definition.localizedTitle)
                    TextField("Value", text: $draft, axis: .vertical)
                        .lineLimit(1...4)
                        .onSubmit { update(.string(draft)) }
                }
            }
        }
    }

    private var currentValue: JoboptionsValue? {
        repository.activeDocument?.value(forKey: definition.key)
    }

    private func localizedChoice(_ choice: String) -> String {
        DistillerOptionCatalog.localizedChoice(choice)
    }

    private var currentText: String { currentValue?.textualValue ?? "" }

    private var isProfileSetting: Bool {
        [
            "CalGrayProfile", "CalRGBProfile", "CalCMYKProfile", "sRGBProfile",
            "OutputICCProfile", "GraphicICCProfile", "ImageICCProfile", "TextICCProfile",
            "PDFXOutputIntentProfile"
        ].contains(definition.key)
    }

    private var profileCandidates: [ICCProfileRecord] {
        repository.profiles.filter { profile in
            switch definition.key {
            case "CalGrayProfile":
                return profile.colorSpace == "GRAY"
            case "CalCMYKProfile", "PDFXOutputIntentProfile":
                return profile.colorSpace == "CMYK"
            case "CalRGBProfile", "sRGBProfile":
                return profile.colorSpace == "RGB"
            default:
                return ["GRAY", "RGB", "CMYK", "Lab", "XYZ"].contains(profile.colorSpace)
            }
        }
    }

    private var profileBinding: Binding<String> {
        Binding(
            get: { currentText },
            set: { update(.string($0)) }
        )
    }

    private var booleanBinding: Binding<Bool> {
        Binding(
            get: { currentValue?.boolValue ?? false },
            set: { update(.boolean($0)) }
        )
    }

    private func nameBinding(default defaultValue: String) -> Binding<String> {
        Binding(
            get: { currentValue?.textualValue ?? defaultValue },
            set: { update(.name($0)) }
        )
    }

    private func literalBinding(default defaultValue: String) -> Binding<String> {
        Binding(
            get: { currentValue?.textualValue ?? defaultValue },
            set: { value in
                update(.number(Double(value) ?? 0, original: value))
            }
        )
    }

    private func commitInteger(range: ClosedRange<Int>) {
        guard let value = Int(draft), range.contains(value) else {
            draft = currentText
            return
        }
        update(.number(Double(value), original: String(value)))
    }

    private func commitNumber(range: ClosedRange<Double>) {
        guard let value = Double(draft), range.contains(value) else {
            draft = currentText
            return
        }
        update(.number(value, original: draft))
    }

    private func update(_ value: JoboptionsValue) {
        do { try repository.update(key: definition.key, value: value) }
        catch { repository.lastError = error.localizedDescription }
    }
}

private struct GenericJoboptionsValueEditor: View {
    let key: String
    @ObservedObject var repository: JoboptionsRepository
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("/\(key)")
                .font(.subheadline.monospaced())
            if let value = repository.activeDocument?.value(forKey: key),
               value.boolValue != nil {
                Toggle("Value", isOn: Binding(
                    get: { value.boolValue ?? false },
                    set: { update(.boolean($0)) }
                ))
            } else if isEditableScalar {
                TextField("PostScript value", text: $draft, axis: .vertical)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1...5)
                    .onSubmit { update(.raw(draft)) }
            } else {
                Text(repository.activeDocument?.value(forKey: key)?.postScript ?? "")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .onAppear { draft = repository.activeDocument?.value(forKey: key)?.postScript ?? "" }
    }

    private var isEditableScalar: Bool {
        guard let value = repository.activeDocument?.value(forKey: key) else { return false }
        switch value {
        case .array, .dictionary: return false
        default: return true
        }
    }

    private func update(_ value: JoboptionsValue) {
        do { try repository.update(key: key, value: value) }
        catch { repository.lastError = error.localizedDescription }
    }
}

private struct ICCProfileLibrarySection: View {
    @ObservedObject var repository: JoboptionsRepository
    @State private var showsImporter = false

    var body: some View {
        Section("ICC profiles") {
            LabeledContent("Available") {
                Text("\(repository.profiles.count)")
                    .foregroundStyle(.secondary)
            }
            ForEach(repository.profiles) { profile in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading) {
                        Text(profile.name)
                        Text("\(profile.profileClass) · \(profile.colorSpace) → \(profile.connectionSpace)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: profile.isBundled ? "shippingbox.fill" : "person.crop.circle")
                        .foregroundStyle(.secondary)
                    if !profile.isBundled {
                        Button(role: .destructive) {
                            do { try repository.deleteProfile(profile) }
                            catch { repository.lastError = error.localizedDescription }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            Button("Import ICC Profile…", systemImage: "square.and.arrow.down") {
                showsImporter = true
            }
        }
        .fileImporter(
            isPresented: $showsImporter,
            allowedContentTypes: [.iccProfileFile, .data],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let url = try result.get().first else { return }
                try repository.importProfile(from: url)
            } catch {
                repository.lastError = error.localizedDescription
            }
        }
    }
}
