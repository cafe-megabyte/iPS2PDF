import Foundation

enum IncomingDocument {
    case postScript(URL)
    case joboptions(URL, LosslessJoboptionsDocument)
}
