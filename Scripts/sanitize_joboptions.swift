import Foundation

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: sanitize_joboptions input output\n".utf8))
    exit(2)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let destinationURL = URL(fileURLWithPath: CommandLine.arguments[2])
var document = try LosslessJoboptionsDocument(data: Data(contentsOf: sourceURL))
document = try document.removingValues(forKeys: [
    "Description", "Namespace", "OtherNamespaces", "PresetSelector"
])
document = try document.replacingValue(forKey: "AlwaysEmbed", with: .array([]))
document = try document.replacingValue(forKey: "NeverEmbed", with: .array([]))
try document.data.write(to: destinationURL, options: [.atomic])
