import CoreGraphics
import Foundation

/// Tracks actual text/image operators without rendering or executing document actions.
final class PDFContentScanner {
    private(set) var usedFonts: Set<UInt> = []
    struct ImageUse {
        let identity: String
        let fields: [PDFInfoField]
        let horizontalPPI: Double?
        let verticalPPI: Double?
        let resource: PDFExtractableResource?
    }
    private(set) var colorSpaces: Set<String> = []
    private var resources: CGPDFDictionaryRef?
    // Type 3 glyph images require the complete text rendering matrix. Until that
    // is evaluated, report their pixel dimensions but explicitly omit guessed PPI.
    private var imageScaleKnown = true
    private(set) var images: [ImageUse] = []
    private(set) var incomplete = false
    private var font: CGPDFDictionaryRef?
    private var matrix = CGAffineTransform.identity
    private var stack: [(CGPDFDictionaryRef?, CGAffineTransform)] = []
    private var activeStreams: Set<UInt> = []
    private var operations = 0
    private let userUnit: Double

    init(userUnit: Double) { self.userUnit = userUnit }

    func scan(page: CGPDFPage) {
        var node: CGPDFDictionaryRef? = page.dictionary
        var seen: Set<UInt> = []
        while let dictionary = node, seen.insert(UInt(bitPattern: dictionary.rawValue)).inserted {
            if let inherited = PDFObjectReader.dictionary(PDFObjectReader.object(dictionary, "Resources")) { resources = inherited; break }
            node = PDFObjectReader.dictionary(PDFObjectReader.object(dictionary, "Parent"))
        }
        scan(content: CGPDFContentStreamCreateWithPage(page))
    }
    func scan(stream: CGPDFStreamRef, resources: CGPDFDictionaryRef?, parent: CGPDFContentStreamRef) {
        let identity = UInt(bitPattern: stream.rawValue)
        guard activeStreams.count < 64, !activeStreams.contains(identity) else { incomplete = true; return }
        let dictionary = CGPDFStreamGetDictionary(stream)
        guard let resources = PDFObjectReader.dictionary(PDFObjectReader.object(dictionary, "Resources")) ?? resources else {
            incomplete = true; return
        }
        activeStreams.insert(identity)
        defer { activeStreams.remove(identity) }
        let saved = (font, matrix, stack, self.resources)
        defer { (font, matrix, stack, self.resources) = saved }
        self.resources = resources
        if let transform = Self.transform(PDFObjectReader.object(dictionary, "Matrix")) { matrix = transform.concatenating(matrix) }
        scan(content: CGPDFContentStreamCreateWithStream(stream, resources, parent))
    }
    private func scan(content: CGPDFContentStreamRef) {
        guard let table = CGPDFOperatorTableCreate() else { incomplete = true; return }
        CGPDFOperatorTableSetCallback(table, "Tf", { scanner, info in
            let state = PDFContentScanner.context(info)
            var size: CGPDFReal = 0; var name: UnsafePointer<CChar>?
            if CGPDFScannerPopNumber(scanner, &size), CGPDFScannerPopName(scanner, &name), let name {
                state.font = PDFObjectReader.dictionary(CGPDFContentStreamGetResource(CGPDFScannerGetContentStream(scanner), "Font", name))
            } else { state.incomplete = true }
            state.tick(scanner)
        })
        for op in ["Tj", "TJ", "'", "\""] {
            CGPDFOperatorTableSetCallback(table, op, { scanner, info in
                let state = PDFContentScanner.context(info)
                state.text(scanner)
                state.tick(scanner)
            })
        }
        CGPDFOperatorTableSetCallback(table, "q", { scanner, info in
            let state = PDFContentScanner.context(info); state.stack.append((state.font, state.matrix)); state.tick(scanner)
        })
        CGPDFOperatorTableSetCallback(table, "Q", { scanner, info in
            let state = PDFContentScanner.context(info)
            if let saved = state.stack.popLast() { (state.font, state.matrix) = saved }
            state.tick(scanner)
        })
        CGPDFOperatorTableSetCallback(table, "cm", { scanner, info in
            let state = PDFContentScanner.context(info)
            var values = [CGPDFReal](repeating: 0, count: 6)
            for i in (0..<6).reversed() {
                if !CGPDFScannerPopNumber(scanner, &values[i]) { state.incomplete = true; return }
            }
            state.matrix = CGAffineTransform(a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5]).concatenating(state.matrix)
            state.tick(scanner)
        })
        CGPDFOperatorTableSetCallback(table, "Do", { scanner, info in
            let state = PDFContentScanner.context(info)
            var name: UnsafePointer<CChar>?
            guard CGPDFScannerPopName(scanner, &name), let name else { state.incomplete = true; return }
            let content = CGPDFScannerGetContentStream(scanner)
            guard let object = CGPDFContentStreamGetResource(content, "XObject", name), let stream = PDFObjectReader.stream(object) else { state.incomplete = true; return }
            if PDFObjectReader.name(CGPDFStreamGetDictionary(stream), "Subtype") == "Image" {
                state.image(stream)
            } else {
                state.scan(stream: stream, resources: state.resources, parent: content)
            }
            state.tick(scanner)
        })
        CGPDFOperatorTableSetCallback(table, "EI", { scanner, info in
            let state = PDFContentScanner.context(info); var stream: CGPDFStreamRef?
            if CGPDFScannerPopStream(scanner, &stream), let stream { state.image(stream, inline: true) }
            else { state.incomplete = true }
            state.tick(scanner)
        })
        for op in ["scn", "SCN"] {
            CGPDFOperatorTableSetCallback(table, op, { scanner, info in
                let state = PDFContentScanner.context(info); var value: CGPDFObjectRef?
                // scn/SCN also accept ordinary numeric color components. A typed
                // PopName on those operands would put the scanner into an error state.
                if CGPDFScannerPopObject(scanner, &value), let value, CGPDFObjectGetType(value) == .name {
                    let content = CGPDFScannerGetContentStream(scanner)
                    let name = PDFObjectReader.describe(value)
                    if let object = CGPDFContentStreamGetResource(content, "Pattern", name), let stream = PDFObjectReader.stream(object) {
                        state.scan(stream: stream, resources: state.resources, parent: content)
                    }
                }
                state.tick(scanner)
            })
        }
        for op in ["rg", "RG"] {
            CGPDFOperatorTableSetCallback(table, op, { scanner, info in
                let state = PDFContentScanner.context(info); state.colorSpaces.insert("DeviceRGB"); state.tick(scanner)
            })
        }
        for op in ["k", "K"] {
            CGPDFOperatorTableSetCallback(table, op, { scanner, info in
                let state = PDFContentScanner.context(info); state.colorSpaces.insert("DeviceCMYK"); state.tick(scanner)
            })
        }
        for op in ["g", "G"] {
            CGPDFOperatorTableSetCallback(table, op, { scanner, info in
                let state = PDFContentScanner.context(info); state.colorSpaces.insert("DeviceGray"); state.tick(scanner)
            })
        }
        for op in ["cs", "CS"] {
            CGPDFOperatorTableSetCallback(table, op, { scanner, info in
                let state = PDFContentScanner.context(info); var name: UnsafePointer<CChar>?
                if CGPDFScannerPopName(scanner, &name), let name {
                    let name = String(cString: name)
                    let resource = CGPDFContentStreamGetResource(CGPDFScannerGetContentStream(scanner), "ColorSpace", name)
                    state.colorSpaces.insert(resource.map { PDFObjectReader.describe($0) } ?? name)
                } else { state.incomplete = true }
                state.tick(scanner)
            })
        }
        CGPDFOperatorTableSetCallback(table, "gs", { scanner, info in
            let state = PDFContentScanner.context(info); var name: UnsafePointer<CChar>?
            guard CGPDFScannerPopName(scanner, &name), let name else { state.incomplete = true; return }
            let content = CGPDFScannerGetContentStream(scanner)
            let dictionary = PDFObjectReader.dictionary(CGPDFContentStreamGetResource(content, "ExtGState", name))
            if let fontObject = PDFObjectReader.elements(PDFObjectReader.array(PDFObjectReader.object(dictionary, "Font"))).first {
                state.font = PDFObjectReader.dictionary(fontObject)
            }
            let mask = PDFObjectReader.dictionary(PDFObjectReader.object(dictionary, "SMask"))
            if let stream = PDFObjectReader.stream(PDFObjectReader.object(mask, "G")) {
                state.scan(stream: stream, resources: state.resources, parent: content)
            }
            state.tick(scanner)
        })
        let scanner = CGPDFScannerCreate(content, table, Unmanaged.passUnretained(self).toOpaque())
        if !CGPDFScannerScan(scanner) { incomplete = true }
    }
    private func text(_ scanner: CGPDFScannerRef) {
        var object: CGPDFObjectRef?
        guard CGPDFScannerPopObject(scanner, &object), let object else { incomplete = true; return }
        let objects = PDFObjectReader.array(object).map(PDFObjectReader.elements) ?? [object]
        var codes: [UInt8] = []
        for object in objects where CGPDFObjectGetType(object) == .string {
            var string: CGPDFStringRef?
            if CGPDFObjectGetValue(object, .string, &string), let string, let bytes = CGPDFStringGetBytePtr(string) {
                codes += UnsafeBufferPointer(start: bytes, count: CGPDFStringGetLength(string))
            }
        }
        guard !codes.isEmpty else { return }
        guard let font else { incomplete = true; return }
        usedFonts.insert(UInt(bitPattern: font.rawValue))
        guard PDFObjectReader.name(font, "Subtype") == "Type3" else { return }
        let encoding = PDFObjectReader.dictionary(PDFObjectReader.object(font, "Encoding"))
        var names: [Int: String] = [:], code = 0
        for value in PDFObjectReader.elements(PDFObjectReader.array(PDFObjectReader.object(encoding, "Differences"))) {
            if CGPDFObjectGetType(value) == .integer { code = Int(PDFObjectReader.describe(value)) ?? 0 }
            else if CGPDFObjectGetType(value) == .name { names[code] = PDFObjectReader.describe(value); code += 1 }
        }
        let procedures = PDFObjectReader.dictionary(PDFObjectReader.object(font, "CharProcs"))
        for code in Set(codes) {
            guard let name = names[Int(code)], let glyph = PDFObjectReader.stream(PDFObjectReader.object(procedures, name)) else { incomplete = true; continue }
            let savedScaleKnown = imageScaleKnown
            imageScaleKnown = false
            scan(stream: glyph, resources: PDFObjectReader.dictionary(PDFObjectReader.object(font, "Resources")) ?? resources, parent: CGPDFScannerGetContentStream(scanner))
            imageScaleKnown = savedScaleKnown
        }
    }
    private func tick(_ scanner: CGPDFScannerRef) {
        operations += 1
        if operations > 5_000_000 || Task.isCancelled { incomplete = true; CGPDFScannerStop(scanner) }
    }
    private func image(_ stream: CGPDFStreamRef, inline: Bool = false) {
        let dictionary = CGPDFStreamGetDictionary(stream)
        let width = PDFObjectReader.number(dictionary, "Width") ?? PDFObjectReader.number(dictionary, "W")
        let height = PDFObjectReader.number(dictionary, "Height") ?? PDFObjectReader.number(dictionary, "H")
        let horizontal = hypot(matrix.a, matrix.b) * userUnit
        let vertical = hypot(matrix.c, matrix.d) * userUnit
        var fields = PDFObjectReader.fields(dictionary, excluding: ["SMask", "Mask", "Metadata"])
        if !imageScaleKnown {
            incomplete = true
            fields.append(PDFInfoField("Effective resolution", String(localized: "Unknown — Type 3 text transformation not evaluated")))
        }
        images.append(ImageUse(identity: inline ? "inline-\(images.count)" : "image-\(UInt(bitPattern: stream.rawValue))",
                               fields: fields,
                               horizontalPPI: width.flatMap { imageScaleKnown && horizontal > 0 ? $0 * 72 / horizontal : nil },
                               verticalPPI: height.flatMap { imageScaleKnown && vertical > 0 ? $0 * 72 / vertical : nil },
                               resource: PDFResourceDescriptorFactory.image(stream)))
    }
    private static func context(_ info: UnsafeMutableRawPointer?) -> PDFContentScanner {
        Unmanaged<PDFContentScanner>.fromOpaque(info!).takeUnretainedValue()
    }
    private static func transform(_ object: CGPDFObjectRef?) -> CGAffineTransform? {
        let values = PDFObjectReader.elements(PDFObjectReader.array(object)).compactMap { Double(PDFObjectReader.describe($0)) }
        guard values.count == 6, values.allSatisfy(\.isFinite) else { return nil }
        return CGAffineTransform(a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5])
    }
}
