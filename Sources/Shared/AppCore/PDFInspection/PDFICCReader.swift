import Foundation
import CryptoKit

enum PDFICCReader {
    static func inspect(_ data: Data, location: String) -> PDFInfoSection {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        var result = PDFInfoSection(id: "icc-" + digest, category: .colors, title: "ICC", fields: [
            PDFInfoField("Profile size", PDFInspectionFormat.size(Int64(data.count))),
            PDFInfoField("SHA-256", digest)
        ])
        func uint(_ offset: Int, _ length: Int = 4) -> UInt32 {
            guard offset >= 0, offset + length <= data.count else { return 0 }
            return data[offset..<(offset + length)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        }
        func ascii(_ offset: Int, _ length: Int = 4) -> String {
            guard offset + length <= data.count else { return PDFInspectionFormat.unknown }
            return String(decoding: data[offset..<(offset + length)], as: UTF8.self).trimmingCharacters(in: .controlCharacters.union(.whitespaces))
        }
        guard data.count >= 132, ascii(36) == "acsp", uint(0) >= 132, uint(0) <= data.count else {
            result.isComplete = false
            result.fields.append(PDFInfoField("Profile status", String(localized: "ICC header unreadable")))
            return result
        }
        let descriptions = (try? ICCProfileDescriptionReader.descriptions(in: data)) ?? []
        result.title = descriptions.first ?? "ICC " + ascii(16)
        let version = "\(data[8]).\(data[9] >> 4).\(data[9] & 15)"
        let date = String(format: "%04d-%02d-%02d %02d:%02d:%02d", uint(24, 2), uint(26, 2), uint(28, 2), uint(30, 2), uint(32, 2), uint(34, 2))
        result.fields += [PDFInfoField("Description", descriptions.joined(separator: "\n")), PDFInfoField("ICC version", version),
            PDFInfoField("Profile class", ascii(12)), PDFInfoField("Color space", ascii(16)), PDFInfoField("Connection space", ascii(20)),
            PDFInfoField("Created", date), PDFInfoField("CMM", ascii(4)), PDFInfoField("Platform", ascii(40)),
            PDFInfoField("Manufacturer", ascii(48)), PDFInfoField("Model", ascii(52)), PDFInfoField("Creator", ascii(80)),
            PDFInfoField("Rendering intent", String(uint(64))), PDFInfoField("Flags", String(format: "0x%08x", uint(44))),
            PDFInfoField("Attributes", String(format: "%08x%08x", uint(56), uint(60))),
            PDFInfoField("Profile ID", data[84..<100].map { String(format: "%02x", $0) }.joined()),
            PDFInfoField("Illuminant XYZ", [68, 72, 76].map { String(format: "%.5f", Double(Int32(bitPattern: uint($0))) / 65536) }.joined(separator: ", "))]
        let count = Int(uint(128))
        guard count <= 4096, 132 + count * 12 <= data.count else {
            result.isComplete = false
            result.fields.append(PDFInfoField("Tag table", PDFInspectionFormat.unknown)); return result
        }
        for index in 0..<count {
            let base = 132 + index * 12, offset = Int(uint(base + 4)), size = Int(uint(base + 8))
            guard offset <= data.count, size <= data.count - offset, size >= 8 else {
                result.isComplete = false
                result.fields.append(PDFInfoField("ICC tag \(ascii(base))", PDFInspectionFormat.unknown, id: "tag-\(index)")); continue
            }
            let type = ascii(offset)
            var value = "\(type), \(PDFInspectionFormat.size(Int64(size)))"
            if type == "text" { value += "\n" + ascii(offset + 8, size - 8) }
            result.fields.append(PDFInfoField("ICC tag \(ascii(base))", value, id: "tag-\(index)"))
        }
        return result
    }
}
