import SwiftUI
import UIKit

struct PostScriptEncryptionPasswordView: View {
    let sourceName: String
    let cancel: () -> Void
    let encrypt: (String) -> Void

    @State private var password = ""
    @State private var confirmation = ""
    @FocusState private var focusedField: Field?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(verbatim: sourceName)
                        .lineLimit(2)
                        .textSelection(.enabled)
                } header: {
                    Text("PostScript file")
                }

                Section {
                    passwordField(
                        LocalizedStringResource("Password"),
                        text: $password,
                        field: .password
                    )
                    passwordField(
                        LocalizedStringResource("Confirm password"),
                        text: $confirmation,
                        field: .confirmation
                    )
                    if let validationMessage {
                        Text(validationMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } footer: {
                    Text("Use printable ASCII characters except parentheses and backslashes.")
                }

                Section {
                    Text("The encrypted file contains a password placeholder. Replace it with this password before opening or converting the file.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Encrypt PostScript")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Encrypt") {
                        encrypt(password)
                    }
                    .disabled(!canEncrypt)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled()
        .onAppear {
            focusedField = .password
        }
    }

    private var canEncrypt: Bool {
        guard !password.isEmpty, password == confirmation else { return false }
        return (try? PostScriptEncryptor.validatePassword(password)) != nil
    }

    private var validationMessage: String? {
        guard !password.isEmpty else { return nil }
        do {
            try PostScriptEncryptor.validatePassword(password)
        } catch {
            return error.localizedDescription
        }
        guard !confirmation.isEmpty else { return nil }
        return password == confirmation
            ? nil
            : String(localized: "The passwords do not match.")
    }

    private func passwordField(
        _ title: LocalizedStringResource,
        text: Binding<String>,
        field: Field
    ) -> some View {
        HStack {
            SecureField(title, text: text)
                .textContentType(.newPassword)
                .focused($focusedField, equals: field)
                .onSubmit {
                    if field == .password {
                        focusedField = .confirmation
                    } else if canEncrypt {
                        encrypt(password)
                    }
                }
            Button {
                if let value = UIPasteboard.general.string {
                    text.wrappedValue = value
                }
            } label: {
                Label("Paste", systemImage: "doc.on.clipboard")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
        }
    }

    private enum Field {
        case password
        case confirmation
    }
}
