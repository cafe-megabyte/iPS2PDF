import Foundation

struct MacOSPostScriptExportInput {
    let url: URL
    let sourceName: String
    let inputPassword: String?
    let retainedInput: PDFInspectionInput?
}
