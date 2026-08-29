import SwiftUI

struct DistillerOptionEditor: View {
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
#if os(iOS)
                    .keyboardType(.numbersAndPunctuation)
#endif
                    .multilineTextAlignment(.trailing)
                    .onSubmit { commitInteger(range: range) }
            }
        case let .number(range):
            LabeledContent(definition.localizedTitle) {
                TextField("Value", text: $draft)
#if os(iOS)
                    .keyboardType(.decimalPad)
#endif
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
