import Foundation

enum ConversionFailure: Error, Sendable {
    case startupCleanup
    case workingDirectoryCleanup
    case inputIsNotRegularFile
    case inputCannotBeRead
    case inputCopy
    case joboptions(diagnostics: String)
    case ghostscriptInstance(returnCode: Int32, diagnostics: String)
    case ghostscriptInitialization(returnCode: Int32, diagnostics: String)
    case ghostscriptConversion(returnCode: Int32, diagnostics: String)
    case ghostscriptProcessTerminated(diagnostics: String)
    case outputMissing
    case outputEmpty
    case invalidPDF

    var localizedMessage: String {
        switch self {
        case .startupCleanup:
            String(localized: "error_startup_cleanup")
        case .workingDirectoryCleanup:
            String(localized: "error_working_directory_cleanup")
        case .inputIsNotRegularFile:
            String(localized: "error_input_not_regular_file")
        case .inputCannotBeRead:
            String(localized: "error_input_unreadable")
        case .inputCopy:
            String(localized: "error_input_copy")
        case .joboptions:
            String(localized: "error_joboptions")
        case .ghostscriptInstance:
            String(localized: "error_ghostscript_instance")
        case .ghostscriptInitialization:
            String(localized: "error_ghostscript_initialization")
        case .ghostscriptConversion:
            String(localized: "error_ghostscript_conversion")
        case .ghostscriptProcessTerminated:
            String(localized: "error_ghostscript_process_terminated")
        case .outputMissing:
            String(localized: "error_output_missing")
        case .outputEmpty:
            String(localized: "error_output_empty")
        case .invalidPDF:
            String(localized: "error_invalid_pdf")
        }
    }

    var returnCode: Int32? {
        switch self {
        case let .ghostscriptInstance(returnCode, _),
             let .ghostscriptInitialization(returnCode, _),
             let .ghostscriptConversion(returnCode, _):
            return returnCode
        default:
            return nil
        }
    }

    var diagnostics: String? {
        switch self {
        case let .joboptions(diagnostics):
            return diagnostics.isEmpty ? nil : diagnostics
        case let .ghostscriptInstance(_, diagnostics),
             let .ghostscriptInitialization(_, diagnostics),
             let .ghostscriptConversion(_, diagnostics):
            return diagnostics.isEmpty ? nil : diagnostics
        case let .ghostscriptProcessTerminated(diagnostics):
            return diagnostics.isEmpty ? nil : diagnostics
        default:
            return nil
        }
    }
}
