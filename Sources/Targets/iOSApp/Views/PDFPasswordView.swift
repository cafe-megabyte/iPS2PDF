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
