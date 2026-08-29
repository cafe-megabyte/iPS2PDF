import Foundation

enum DistillerSemanticEditor: Sendable {
    case scalar
    case description
    case deviceResolution
    case pageRange
    case pageSize
    case downsampling(SemanticJoboptions.ImageKind)
    case compression(SemanticJoboptions.ImageKind)
    case imagePolicy(SemanticJoboptions.ImageKind)
    case monoSmoothing
    case distillerOverrides
    case standard
    case pdfXBoxes
    case companion
}
