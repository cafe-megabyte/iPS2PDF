import Foundation

enum IncomingDocument {
    case conversionInput(URL)
    case pdfInformation(URL)
    case joboptions(URL, LosslessJoboptionsDocument)
}

enum IncomingDocumentPurpose { case automatic, conversion }
