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

@MainActor
struct PDFProcessingLicensesView: View {
    var closeAction: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [PDFProcessingLicenseEntry] = []
    @State private var failed = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Link("iPS2PDF source code", destination: URL(string: "https://github.com/cafe-megabyte/iPS2PDF")!)
                    Link("Hyper Compress source code", destination: URL(string: "https://github.com/alam00000/bentopdf-hyper-compress")!)
                }
                if failed { Text("The bundled license notices could not be read.").foregroundStyle(.red) }
                ForEach(entries) { entry in
                    DisclosureGroup {
                        Text(entry.text).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(entry.id)
                            if !entry.license.isEmpty { Text(entry.license).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            .navigationTitle("PDF processing licenses")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { if let closeAction { closeAction() } else { dismiss() } } } }
        }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 480)
        #endif
        .task {
            do { entries = try await Task.detached { try PDFProcessingLicenseEntry.load() }.value }
            catch { failed = true }
        }
    }
}
