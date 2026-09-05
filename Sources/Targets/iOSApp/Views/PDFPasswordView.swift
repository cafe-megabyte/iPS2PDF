import SwiftUI

struct PDFPasswordPresenter: ViewModifier {
    @ObservedObject var controller: PDFPasswordController
    func body(content: Content) -> some View {
        content.sheet(isPresented: Binding(get: { controller.request != nil }, set: { if !$0 { controller.cancel() } })) {
            PDFConversionPasswordView(controller: controller)
                .presentationDetents([.medium])
        }
    }
}

private struct PDFConversionPasswordView: View {
    @ObservedObject var controller: PDFPasswordController
    @State private var password = ""
    @FocusState private var isFocused: Bool
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(controller.request?.fileName ?? "").font(.headline)
                    Text("Enter the PDF opening password.")
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .focused($isFocused)
                        .onSubmit(submit)
                    if controller.request?.wasIncorrect == true {
                        Text("The password is incorrect. Please try again.").foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Password required")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { password = ""; controller.cancel() } }
                ToolbarItem(placement: .confirmationAction) { Button("Open", action: submit).disabled(controller.isChecking) }
            }
            .onAppear { isFocused = true }
            .onChange(of: controller.request?.id) { _, _ in password = ""; isFocused = true }
        }
    }
    private func submit() { controller.submit(password); password = "" }
}
