import Foundation

enum EnhancedSecurityEnvelope {
    static let version: Int64 = 1
    static let operation = "operation"
    static let envelopeVersion = "envelopeVersion"
    static let validate = "validate"
    static let convert = "convert"
    static let profiles = "profiles"
    static let begin = "begin"
    static let append = "append"
    static let run = "run"
    static let read = "read"
    static let finish = "finish"
    static let joboptionsFD = "joboptionsFD"
    static let inputFD = "inputFD"
    static let outputFD = "outputFD"
    static let journalFD = "journalFD"
    static let stream = "stream"
    static let inputStream = "input"
    static let joboptionsStream = "joboptions"
    static let userProfileStream = "userProfile"
    static let outputStream = "output"
    static let journalStream = "journal"
    static let chunk = "chunk"
    static let offset = "offset"
    static let length = "length"
    static let hasMore = "hasMore"
    static let sourceFileName = "sourceFileName"
    static let limitsEnabled = "limitsEnabled"
    static let allowTransparency = "allowTransparency"
    static let standard = "standard"
    static let postScriptRandomSeed = "postScriptRandomSeed"
    static let deadline = "deadline"
    static let maximumOutputBytes = "maximumOutputBytes"
    static let status = "status"
    static let ghostscriptCode = "ghostscriptCode"
    static let stage = "stage"
    static let message = "message"
    static let profileMetadataJSON = "profileMetadataJSON"
    static let profileSelectionCount = "profileSelectionCount"
    static func profileSelectionKey(_ index: Int) -> String { "profileSelectionKey\(index)" }
    static func profileSelectionName(_ index: Int) -> String { "profileSelectionName\(index)" }
    static let userProfileCount = "userProfileCount"
    static func userProfileKey(_ index: Int) -> String { "userProfileKey\(index)" }
    static func userProfileFD(_ index: Int) -> String { "userProfileFD\(index)" }
}
