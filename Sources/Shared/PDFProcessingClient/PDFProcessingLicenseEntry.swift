import SwiftUI
import Foundation

struct PDFProcessingLicenseEntry: Identifiable, Sendable {
    let id: String
    let license: String
    let text: String

    static func load() throws -> [Self] {
        let app = Bundle.main
        var bundles: [Bundle] = [app]
        if let frameworks = app.privateFrameworksURL,
           let bundle = Bundle(url: frameworks.appendingPathComponent("PDFProcessingRuntime.framework")) { bundles.append(bundle) }
        for directory in [app.bundleURL.appendingPathComponent("Extensions"), app.builtInPlugInsURL].compactMap({ $0 }) {
            for url in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
                where url.pathExtension == "appex" {
                if let bundle = Bundle(url: url) { bundles.append(bundle) }
            }
        }
        guard let root = bundles.compactMap({ $0.resourceURL?.appendingPathComponent("PDFProcessingLicenses") })
            .first(where: { FileManager.default.fileExists(atPath: $0.appendingPathComponent("components.json").path) }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        struct Component: Decodable {
            struct Resource: Decodable { let file: String }
            let component: String
            let license: String
            let resources: [Resource]
        }
        let components = try JSONDecoder().decode([Component].self, from: Data(contentsOf: root.appendingPathComponent("components.json")))
        var entries: [Self] = []
        for component in components {
            var texts: [String] = []
            for resource in component.resources {
                guard !resource.file.contains("/"), resource.file != ".", resource.file != ".." else { throw CocoaError(.fileReadCorruptFile) }
                texts.append(try String(contentsOf: root.appendingPathComponent(resource.file), encoding: .utf8))
            }
            entries.append(Self(id: component.component, license: component.license, text: texts.joined(separator: "\n\n")))
        }
        entries.insert(Self(id: "Acknowledgments", license: "", text: try String(contentsOf: root.appendingPathComponent("ACKNOWLEDGMENTS.txt"), encoding: .utf8)), at: 0)
        let pins = try String(contentsOf: root.appendingPathComponent("source-archives.txt"), encoding: .utf8)
        entries.append(Self(id: "Source revisions", license: "", text: pins))
        return entries
    }
}
