import SwiftUI

@main
struct iPS2PDFApp: App {
    @StateObject private var viewModel: ConversionViewModel

    init() {
        try? WorkingDirectoryService.clearStaleStagingDirectories()
        try? PDFInspectionInput.clearStaleDirectories()
        _viewModel = StateObject(wrappedValue: ConversionViewModel())
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .tint(.appTint)
        }
    }
}
