import SwiftUI

@main
struct iPS2PDFApp: App {
    @StateObject private var viewModel: ConversionViewModel

    init() {
        _viewModel = StateObject(wrappedValue: ConversionViewModel())
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .tint(AppTint.color)
        }
    }
}
