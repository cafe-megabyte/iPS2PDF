import Foundation

final class PDFXMPReader: NSObject, XMLParserDelegate {
    private(set) var fields: [PDFInfoField] = []
    private(set) var declarations: [String] = []
    private(set) var hasConflictingStandardMetadata = false
    private(set) var isValid = false
    private(set) var propertyValues: [String: [String]] = [:]
    private static let rdf = "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
    private static let pdfa = "http://www.aiim.org/pdfa/ns/id/|"
    private static let identificationNamespaces = [
        "http://www.aiim.org/pdfa/ns/id/|", "http://www.aiim.org/pdfua/ns/id/|",
        "http://www.npes.org/pdfx/ns/id/|", "http://ns.adobe.com/pdfx/1.3/|",
        "http://www.npes.org/pdfvt/ns/id/|", "http://www.aiim.org/pdfe/ns/id/|"
    ]
    private struct Description {
        let subject: String
        let depth: Int
        var values: [String: [String]] = [:]
    }
    private var descriptions: [Description] = []
    private var activeDescription: Description?
    private var elementKeys: [String] = []
    private var namespaceHistory: [String: [String?]] = [:]
    private var path: [String] = []
    private var texts: [String] = []
    private var namespaces: [String: String] = [:]

    init(data: Data) {
        super.init()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = self
        isValid = parser.parse()
        // RDF descriptions of the same subject form one property bag. Keep every
        // occurrence: contradictory values must never be silently overwritten.
        for subject in Set(descriptions.map(\.subject)).sorted() {
            let group = descriptions.filter { $0.subject == subject }
            var merged: [String: [String]] = [:]
            for description in group {
                for (key, values) in description.values { merged[key, default: []] += values }
            }
            merged = merged.mapValues { Array(Set($0)).sorted() }
            let conflicts = merged.filter { key, values in
                values.count > 1 && Self.identificationNamespaces.contains(where: key.hasPrefix)
            }
            if conflicts.isEmpty { declarations += claims(merged) }
            else {
                hasConflictingStandardMetadata = true
                // Retain coherent individual claims, but never form a Cartesian
                // product from contradictory part/conformance properties.
                for description in group { declarations += claims(description.values.mapValues { Array(Set($0)).sorted() }) }
                let details = conflicts.keys.sorted().map { key in
                    let families = ["http://www.aiim.org/pdfa/ns/id/|": "PDF/A", "http://www.aiim.org/pdfua/ns/id/|": "PDF/UA", "http://www.npes.org/pdfx/ns/id/|": "PDF/X", "http://ns.adobe.com/pdfx/1.3/|": "PDF/X", "http://www.npes.org/pdfvt/ns/id/|": "PDF/VT", "http://www.aiim.org/pdfe/ns/id/|": "PDF/E"]
                    let family = families.first(where: { key.hasPrefix($0.key) })?.value ?? ""
                    return family + " " + (key.split(separator: "|").last.map(String.init) ?? key) + " = " + (conflicts[key] ?? []).joined(separator: ", ")
                }.joined(separator: "; ")
                declarations.append(String(localized: "Conflicting standard metadata") + ": " + details)
            }
        }
        var seen: Set<String> = []
        declarations = declarations.filter { seen.insert($0).inserted }
    }
    private func claims(_ values: [String: [String]]) -> [String] {
        var result: [String] = []
        let parts = values[Self.pdfa + "part"] ?? []
        let conformance = values[Self.pdfa + "conformance"] ?? []
        if parts.count == 1, conformance.count <= 1 {
            result.append("PDF/A-" + parts[0] + (conformance.first?.lowercased() ?? ""))
        }
        for key in values.keys.sorted() {
            let entries = values[key] ?? []
            if (key.hasPrefix("http://www.npes.org/pdfx/ns/id/|") || key.hasPrefix("http://ns.adobe.com/pdfx/1.3/|")), (key.hasSuffix("|GTS_PDFXVersion") || key.hasSuffix("|GTS_PDFXConformance")) { result += entries }
            if key == "http://www.aiim.org/pdfua/ns/id/|part" { result += entries.map { "PDF/UA-" + $0 } }
            if key == "http://www.npes.org/pdfvt/ns/id/|GTS_PDFVTVersion" || key == "http://www.aiim.org/pdfe/ns/id/|GTS_PDFEVersion" { result += entries }
        }
        return result
    }
    private func expandedAttribute(_ name: String) -> String {
        let parts = name.split(separator: ":", maxSplits: 1).map(String.init)
        return (parts.count == 2 ? namespaces[parts[0]] ?? "" : "") + "|" + (parts.last ?? name)
    }
    func parser(_ parser: XMLParser, didStartMappingPrefix prefix: String, toURI namespaceURI: String) {
        namespaceHistory[prefix, default: []].append(namespaces[prefix])
        namespaces[prefix] = namespaceURI
    }
    func parser(_ parser: XMLParser, didEndMappingPrefix prefix: String) {
        namespaces[prefix] = namespaceHistory[prefix]?.popLast() ?? nil
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        let isDescription = elementName == "Description" && namespaceURI == Self.rdf && elementKeys.last == Self.rdf + "|RDF"
        path.append(qName ?? elementName); texts.append("")
        elementKeys.append((namespaceURI ?? "") + "|" + elementName)
        if isDescription {
            let expanded = attributes.reduce(into: [String: String]()) { $0[expandedAttribute($1.key)] = $1.value }
            let subject = expanded[Self.rdf + "|about"] ?? expanded[Self.rdf + "|nodeID"].map { "_node:" + $0 } ?? ""
            activeDescription = Description(subject: subject, depth: path.count)
        }
        for (key, value) in attributes.sorted(by: { $0.key < $1.key }) {
            record(value, key: expandedAttribute(key), location: path.joined(separator: "/") + "/@" + key, directProperty: isDescription)
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if !texts.isEmpty { texts[texts.count - 1] += string }
    }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        self.parser(parser, foundCharacters: String(decoding: CDATABlock, as: UTF8.self))
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let value = texts.removeLast().trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty {
            record(value, key: (namespaceURI ?? "") + "|" + elementName, location: path.joined(separator: "/"), directProperty: activeDescription.map { path.count == $0.depth + 1 } ?? false)
            if let property = elementKeys.last(where: { !$0.hasPrefix(Self.rdf + "|") && !$0.hasPrefix("adobe:ns:meta/|") }), property != elementKeys.last {
                propertyValues[property, default: []].append(value)
            }
        }
        if let description = activeDescription, path.count == description.depth {
            descriptions.append(description); activeDescription = nil
        }
        elementKeys.removeLast(); path.removeLast()
    }
    private func record(_ value: String, key: String, location: String, directProperty: Bool) {
        if directProperty { activeDescription?.values[key, default: []].append(value) }
        propertyValues[key, default: []].append(value)
        fields.append(PDFInfoField(location, value, id: "xmp-\(fields.count)"))
    }
}
