import SwiftUI

struct MacOSStartView: View {
    @ObservedObject var repository: JoboptionsRepository
    let onEditJoboptions: () -> Void
    let onManageJoboptions: () -> Void
    let onShowGhostscriptSettings: () -> Void
    let onShowPDFInfo: () -> Void
    let onOpenFile: () -> Void
    let onOpenPostScriptFile: () -> Void
    let onEncryptPostScriptFile: () -> Void

    var body: some View {
        FrontConversionView(
            repository: repository,
            selectedPDFVersion: displayedPDFVersion,
            isPDFVersionConstrained: constrainedCompatibilityLevel != nil,
            selectedPDFACompatibility: selectedPDFACompatibility,
            controlsAreDisabled: false,
            controlsAppearDisabled: false,
            onSelectPDFVersion: selectPDFVersion,
            onSelectPDFACompatibility: selectPDFACompatibility,
            onShowSettings: onEditJoboptions,
            onManageJoboptions: onManageJoboptions,
            onShowPDFInfo: onShowPDFInfo,
            onOpenFile: onOpenFile,
            onOpenPostScriptFile: onOpenPostScriptFile,
            onEncryptPostScriptFile: onEncryptPostScriptFile,
            onShowGhostscriptSettings: onShowGhostscriptSettings
        )
        .tint(.appTint)
        .alert("Error", isPresented: errorIsPresented) {
            Button("OK") { repository.lastError = nil }
        } message: {
            Text(verbatim: repository.lastError ?? "")
        }
    }

    private var constrainedCompatibilityLevel: String? {
        JoboptionsConsistencyEngine.pdfAConstrainedCompatibilityLevel(
            in: repository.activeDocument
        )
    }

    private var displayedPDFVersion: PDFVersion {
        PDFVersion(
            rawValue: constrainedCompatibilityLevel ?? repository.compatibilityLevel
        ) ?? .v13
    }

    private var selectedPDFACompatibility: PDFACompatibility {
        switch repository.activeStandard {
        case .pdfa1b: .pdfa1b
        case .pdfa2b: .pdfa2b
        case .pdfa3b: .pdfa3b
        default: .none
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { repository.lastError != nil },
            set: { isPresented in
                if !isPresented { repository.lastError = nil }
            }
        )
    }

    private func selectPDFVersion(_ version: PDFVersion) {
        guard constrainedCompatibilityLevel == nil else { return }
        do {
            try repository.update(
                key: "CompatibilityLevel",
                value: .number(
                    Double(version.rawValue) ?? 1.3,
                    original: version.rawValue
                )
            )
        } catch {
            repository.lastError = error.localizedDescription
        }
    }

    private func selectPDFACompatibility(_ compatibility: PDFACompatibility) {
        let standard: PDFStandard = switch compatibility {
        case .none: .none
        case .pdfa1b: .pdfa1b
        case .pdfa2b: .pdfa2b
        case .pdfa3b: .pdfa3b
        }
        do {
            try repository.setStandard(standard)
        } catch {
            repository.lastError = error.localizedDescription
        }
    }
}
