import SwiftUI

struct DistillerOptionEditor: View {
    let definition: DistillerOptionDefinition
    @ObservedObject var repository: JoboptionsRepository
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            control
            if let note = definition.localizedCompatibilityNote {
                Text(note).font(.caption).foregroundStyle(.orange)
            } else {
                Text(definition.localizedHelp).font(.caption).foregroundStyle(.secondary)
            }
        }
        .consistencyHighlight(isAffected)
        .onAppear(perform: reloadDraft)
        .onChange(of: documentToken) { _, _ in reloadDraft() }
    }

    @ViewBuilder
    private var control: some View {
        switch definition.semanticEditor {
        case .scalar:
            scalarControl
        default:
            SemanticDistillerEditor(definition: definition, repository: repository)
        }
    }

    @ViewBuilder
    private var scalarControl: some View {
        switch definition.kind {
        case .boolean:
            Picker(definition.localizedTitle, selection: booleanSelection) {
                Text(DistillerOptionCatalog.localizedChoice("False")).tag("false")
                Text(DistillerOptionCatalog.localizedChoice("True")).tag("true")
            }
            .pickerStyle(.menu)
        case let .name(choices):
            Picker(definition.localizedTitle, selection: nameSelection) {
                choiceRows(choices: choices, localizes: true)
            }
            .pickerStyle(.menu)
        case let .literal(choices):
            Picker(definition.localizedTitle, selection: literalSelection) {
                choiceRows(choices: choices, localizes: false)
            }
            .pickerStyle(.menu)
        case .integer:
            LabeledContent(definition.localizedTitle) {
                TextField("", text: draftBinding)
#if os(iOS)
                    .keyboardType(.numbersAndPunctuation)
#endif
                    .multilineTextAlignment(.trailing)
                    .invalidDraftStyle(!draft.isEmpty && Int(draft) == nil)
            }
        case .number:
            LabeledContent(definition.localizedTitle) {
                TextField("", text: draftBinding)
#if os(iOS)
                    .keyboardType(.decimalPad)
#endif
                    .multilineTextAlignment(.trailing)
                    .invalidDraftStyle(!draft.isEmpty && Double(draft.replacingOccurrences(of: ",", with: ".")) == nil)
            }
        case .string:
            if isProfileSetting {
                Picker(definition.localizedTitle, selection: profileSelection) {
                    if !currentText.isEmpty,
                       !profileCandidates.contains(where: { $0.name == currentText }) {
                        Text(String.localizedStringWithFormat(
                            String(localized: "Custom: %@"), currentText
                        )).tag(currentText)
                    }
                    Text(String(localized: "None")).tag("")
                    ForEach(profileCandidates) { profile in
                        Text(profile.name).tag(profile.name)
                    }
                }
                .pickerStyle(.menu)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(definition.localizedTitle)
                    TextField("", text: draftBinding, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
        }
    }

    @ViewBuilder
    private func choiceRows(choices: [String], localizes: Bool) -> some View {
        if currentValue == nil {
            Text(String(localized: "Not set")).tag("__not_set__")
        } else if !choices.contains(currentText) {
            Text(String.localizedStringWithFormat(
                String(localized: "Custom: %@"), currentText
            )).tag(currentText)
        }
        ForEach(choices, id: \.self) { choice in
            Text(localizes ? DistillerOptionCatalog.localizedChoice(choice) : choice).tag(choice)
        }
    }

    private var currentValue: JoboptionsValue? {
        JoboptionsConsistencyEngine.displayValue(
            forKey: definition.key,
            in: repository.activeDocument,
            context: repository.consistencyAnalysisContext
        )
    }

    private var currentText: String {
        if isProfileSetting {
            return JoboptionsRuntimeDefaults.profileSelection(currentValue)
        }
        return currentValue?.textualValue ?? currentValue?.postScript ?? ""
    }

    private var documentToken: Data? {
        repository.activeDocument?.data
    }

    private var isAffected: Bool {
        JoboptionsConsistencyIssueIndex(repository.compatibilityIssues)
            .affects(any: definition.keyPaths)
    }

    private var booleanSelection: Binding<String> {
        Binding(
            get: {
                (currentValue?.boolValue ?? JoboptionsRuntimeDefaults.booleanValue(
                    forKey: definition.key,
                    in: repository.activeDocument
                )) ? "true" : "false"
            },
            set: { value in
                update(.boolean(value == "true"))
            }
        )
    }

    private var nameSelection: Binding<String> {
        Binding(
            get: { currentValue == nil ? "__not_set__" : currentText },
            set: { value in
                guard value != "__not_set__" else { return }
                update(.name(value))
            }
        )
    }

    private var literalSelection: Binding<String> {
        Binding(
            get: { currentValue == nil ? "__not_set__" : currentText },
            set: { value in
                guard value != "__not_set__", let number = Double(value) else { return }
                update(.number(number, original: value))
            }
        )
    }

    private var profileSelection: Binding<String> {
        Binding(
            get: { currentText },
            set: { value in
                update(.string(value))
            }
        )
    }

    private var isProfileSetting: Bool {
        JoboptionsRuntimeDefaults.profileKeys.contains(definition.key)
    }

    private var profileCandidates: [ICCProfileRecord] {
        repository.profiles
    }

    private func reloadDraft() {
        let value = currentValue
        draft = value?.textualValue ?? (value.map(\.postScript) ?? "")
    }

    /// Reloading presentation state must not be mistaken for a user edit.
    private var draftBinding: Binding<String> {
        Binding(get: { draft }, set: { value in
            draft = value
            commitDraft(value)
        })
    }

    private func commitDraft(_ value: String) {
        switch definition.kind {
        case .integer:
            guard let number = Int(value) else { return }
            update(.number(Double(number), original: String(number)))
        case .number:
            let normalized = value.replacingOccurrences(of: ",", with: ".")
            guard let number = Double(normalized) else { return }
            update(.number(number, original: normalized))
        case .string where !isProfileSetting:
            update(.string(value))
        default:
            break
        }
    }

    private func update(_ value: JoboptionsValue) {
        do {
            try repository.update(key: definition.key, value: value)
        } catch {
            repository.lastError = error.localizedDescription
        }
    }
}

extension View {
    func consistencyHighlight(_ isAffected: Bool) -> some View {
        padding(.vertical, 5)
            .padding(.horizontal, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isAffected ? Color.orange.opacity(0.20) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isAffected ? Color.orange.opacity(0.62) : Color.clear, lineWidth: 1)
            )
    }

    func invalidDraftStyle(_ isInvalid: Bool) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(isInvalid ? Color.red.opacity(0.72) : Color.clear, lineWidth: 1)
        )
    }
}
