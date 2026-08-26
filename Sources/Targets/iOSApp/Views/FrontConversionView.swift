import SwiftUI

struct FrontConversionView: View {
    @ObservedObject var viewModel: ConversionViewModel
    let onShowSettings: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            HStack {
                Spacer()
                Button(action: onShowSettings) {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.controlsAreDisabled)
            }

            Spacer(minLength: 0)

            Button(String(localized: "open_file")) {
                viewModel.isFileImporterPresented = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.controlsAreDisabled)

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Joboptions")
                        .font(.headline)

                    JoboptionsDropdown(
                        repository: viewModel.joboptionsRepository,
                        isDisabled: viewModel.controlsAreDisabled
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "pdf_version"))
                        .font(.headline)

                    PDFVersionDropdown(
                        selectedVersion: viewModel.selectedPDFVersion,
                        isDisabled: viewModel.controlsAreDisabled || viewModel.joboptionsRepository.activeStandard != .none
                    ) { version in
                        viewModel.setPDFVersion(version)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "pdfa_compatibility"))
                        .font(.headline)

                    PDFACompatibilityDropdown(
                        selectedCompatibility: viewModel.selectedPDFACompatibility,
                        isDisabled: viewModel.controlsAreDisabled
                    ) { compatibility in
                        viewModel.setPDFACompatibility(compatibility)
                    }
                }
            }
            .frame(maxWidth: 360, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)

            Spacer(minLength: 0)
        }
        .padding(32)
    }
}
