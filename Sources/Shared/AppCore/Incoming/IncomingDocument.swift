import Foundation

enum IncomingDocument {
    case conversionInput(URL)
    case joboptions(URL, LosslessJoboptionsDocument)
}
