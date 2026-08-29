import SwiftUI

struct GenericJoboptionsValueEditor: View {
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
