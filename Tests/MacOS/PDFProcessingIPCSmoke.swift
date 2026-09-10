import Foundation
import CryptoKit
import CoreGraphics
import ImageIO
import PDFKit
import XPC

@main
struct PDFProcessingIPCSmoke {
    static func require(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !value() { throw NSError(domain: "PDFProcessingIPCSmoke", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    static func renderedPixels(of page: PDFPage) throws -> Data {
        let bounds = page.bounds(for: .mediaBox)
        let width = max(1, Int(bounds.width.rounded(.up)))
        let height = max(1, Int(bounds.height.rounded(.up)))
        let bytesPerRow = width * 4
        var pixels = Data(count: bytesPerRow * height)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.translateBy(x: -bounds.minX, y: -bounds.minY)
            page.draw(with: .mediaBox, to: context)
            return true
        }
        try require(rendered, "Could not render PDF page")
        return pixels
    }

    static func pdfWithEmbeddedCFF(_ cff: Data) -> Data {
        var result = Data("%PDF-1.7\n%âãÏÓ\n".utf8)
        var offsets = [Int](repeating: 0, count: 8)
        func appendObject(_ number: Int, _ body: Data) {
            offsets[number] = result.count
            result.append(Data("\(number) 0 obj\n".utf8))
            result.append(body)
            result.append(Data("\nendobj\n".utf8))
        }
        appendObject(1, Data("<< /Type /Catalog /Pages 2 0 R >>".utf8))
        appendObject(2, Data("<< /Type /Pages /Kids [3 0 R] /Count 1 >>".utf8))
        appendObject(3, Data("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources << /Font << /F1 4 0 R >> >> /Contents 7 0 R >>".utf8))
        appendObject(4, Data("<< /Type /Font /Subtype /Type1 /BaseFont /ABCDEF+AppleGaramond-Book /FirstChar 32 /LastChar 32 /Widths [500] /Encoding /WinAnsiEncoding /FontDescriptor 5 0 R >>".utf8))
        appendObject(5, Data("<< /Type /FontDescriptor /FontName /ABCDEF+AppleGaramond-Book /Flags 4 /FontBBox [0 0 1000 1000] /ItalicAngle 0 /Ascent 800 /Descent -200 /CapHeight 700 /StemV 80 /FontFile3 6 0 R >>".utf8))
        var fontStream = Data("<< /Length \(cff.count) /Subtype /Type1C >>\nstream\n".utf8)
        fontStream.append(cff)
        fontStream.append(Data("\nendstream".utf8))
        appendObject(6, fontStream)
        let content = Data("BT /F1 12 Tf 10 10 Td ( ) Tj ET".utf8)
        var contentStream = Data("<< /Length \(content.count) >>\nstream\n".utf8)
        contentStream.append(content)
        contentStream.append(Data("\nendstream".utf8))
        appendObject(7, contentStream)
        let xref = result.count
        result.append(Data("xref\n0 8\n0000000000 65535 f \n".utf8))
        for offset in offsets.dropFirst() {
            result.append(Data(String(format: "%010d 00000 n \n", offset).utf8))
        }
        result.append(Data("trailer\n<< /Size 8 /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n".utf8))
        return result
    }
    static func pdfWithLargeImage(width: Int = 8_000, height: Int = 8_000) -> Data {
        let rowBytes = (width + 7) / 8
        let pixels = Data(repeating: 0x55, count: rowBytes * height)
        var result = Data("%PDF-1.7\n%âãÏÓ\n".utf8)
        var offsets = [Int](repeating: 0, count: 6)
        func appendObject(_ number: Int, _ body: Data) {
            offsets[number] = result.count
            result.append(Data("\(number) 0 obj\n".utf8))
            result.append(body)
            result.append(Data("\nendobj\n".utf8))
        }
        appendObject(1, Data("<< /Type /Catalog /Pages 2 0 R >>".utf8))
        appendObject(2, Data("<< /Type /Pages /Kids [3 0 R] /Count 1 >>".utf8))
        appendObject(3, Data("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources << /XObject << /Im0 4 0 R >> >> /Contents 5 0 R >>".utf8))
        var image = Data("<< /Type /XObject /Subtype /Image /Width \(width) /Height \(height) /ColorSpace /DeviceGray /BitsPerComponent 1 /Length \(pixels.count) >>\nstream\n".utf8)
        image.append(pixels)
        image.append(Data("\nendstream".utf8))
        appendObject(4, image)
        let content = Data("q 200 0 0 200 0 0 cm /Im0 Do Q".utf8)
        var contentStream = Data("<< /Length \(content.count) >>\nstream\n".utf8)
        contentStream.append(content)
        contentStream.append(Data("\nendstream".utf8))
        appendObject(5, contentStream)
        let xref = result.count
        result.append(Data("xref\n0 6\n0000000000 65535 f \n".utf8))
        for offset in offsets.dropFirst() {
            result.append(Data(String(format: "%010d 00000 n \n", offset).utf8))
        }
        result.append(Data("trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n".utf8))
        return result
    }
    static func pdfWithTIFFPredictorImage() -> Data {
        // Four RGB pixels per row, encoded with PDF's TIFF predictor 2 and zlib.
        // The compressed bytes are fixed so the smoke test does not depend on a
        // second compression implementation.
        let pixels = Data([0x78, 0x9c, 0xe3, 0x12, 0x91, 0x63, 0x64, 0x62, 0x86, 0x20,
                           0x6e, 0x51, 0x79, 0x38, 0x1b, 0x00, 0x09, 0x89, 0x00, 0xa0])
        var result = Data("%PDF-1.7\n%âãÏÓ\n".utf8)
        var offsets = [Int](repeating: 0, count: 6)
        func appendObject(_ number: Int, _ body: Data) {
            offsets[number] = result.count
            result.append(Data("\(number) 0 obj\n".utf8))
            result.append(body)
            result.append(Data("\nendobj\n".utf8))
        }
        appendObject(1, Data("<< /Type /Catalog /Pages 2 0 R >>".utf8))
        appendObject(2, Data("<< /Type /Pages /Kids [3 0 R] /Count 1 >>".utf8))
        appendObject(3, Data("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 4 2] /Resources << /XObject << /Im0 4 0 R >> >> /Contents 5 0 R >>".utf8))
        var image = Data("<< /Type /XObject /Subtype /Image /Width 4 /Height 2 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode /DecodeParms << /Predictor 2 /Colors 3 /Columns 4 /BitsPerComponent 8 >> /Length \(pixels.count) >>\nstream\n".utf8)
        image.append(pixels)
        image.append(Data("\nendstream".utf8))
        appendObject(4, image)
        let content = Data("q 4 0 0 2 0 0 cm /Im0 Do Q".utf8)
        var contentStream = Data("<< /Length \(content.count) >>\nstream\n".utf8)
        contentStream.append(content)
        contentStream.append(Data("\nendstream".utf8))
        appendObject(5, contentStream)
        let xref = result.count
        result.append(Data("xref\n0 6\n0000000000 65535 f \n".utf8))
        for offset in offsets.dropFirst() {
            result.append(Data(String(format: "%010d 00000 n \n", offset).utf8))
        }
        result.append(Data("trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n".utf8))
        return result
    }
    static func pdfWithRunLengthImage() -> Data {
        // Two one-byte monochrome rows encoded as one RunLengthDecode literal
        // packet followed by the end-of-data marker.
        let pixels = Data([1, 0x00, 0xff, 128])
        var result = Data("%PDF-1.7\n%âãÏÓ\n".utf8)
        var offsets = [Int](repeating: 0, count: 6)
        func appendObject(_ number: Int, _ body: Data) {
            offsets[number] = result.count
            result.append(Data("\(number) 0 obj\n".utf8))
            result.append(body)
            result.append(Data("\nendobj\n".utf8))
        }
        appendObject(1, Data("<< /Type /Catalog /Pages 2 0 R >>".utf8))
        appendObject(2, Data("<< /Type /Pages /Kids [3 0 R] /Count 1 >>".utf8))
        appendObject(3, Data("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 8 2] /Resources << /XObject << /Im0 4 0 R >> >> /Contents 5 0 R >>".utf8))
        var image = Data("<< /Type /XObject /Subtype /Image /Width 8 /Height 2 /ColorSpace /DeviceGray /BitsPerComponent 1 /Filter [/RunLengthDecode] /Length \(pixels.count) >>\nstream\n".utf8)
        image.append(pixels)
        image.append(Data("\nendstream".utf8))
        appendObject(4, image)
        let content = Data("q 8 0 0 2 0 0 cm /Im0 Do Q".utf8)
        var contentStream = Data("<< /Length \(content.count) >>\nstream\n".utf8)
        contentStream.append(content)
        contentStream.append(Data("\nendstream".utf8))
        appendObject(5, contentStream)
        let xref = result.count
        result.append(Data("xref\n0 6\n0000000000 65535 f \n".utf8))
        for offset in offsets.dropFirst() {
            result.append(Data(String(format: "%010d 00000 n \n", offset).utf8))
        }
        result.append(Data("trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n".utf8))
        return result
    }
    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            throw NSError(domain: "PDFProcessingIPCSmoke", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Expected fixture directory and dummy signature font"])
        }
        let fixtures = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let dummySignatureFont = URL(fileURLWithPath: CommandLine.arguments[2])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let root = directory.appendingPathComponent("PDFProcessingJobs", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        func send(_ job: PDFProcessingJobDirectory, password: String? = nil,
                  version: Int = PDFProcessingEnvelope.version, operation: PDFProcessingRequest.Operation = .removeMetadata,
                  options: PDFCompressionOptions = .init(), previewPage: Int? = nil,
                  pageOverrides: [PDFPageCompressionOverride] = [],
                  signaturePlacements: [PDFSignaturePlacement] = [],
                  resource: PDFExtractableResource? = nil, handler: PDFProcessingRequestHandler? = nil) throws -> PDFProcessingReply {
            var envelope = XPCDictionary()
            let request = PDFProcessingRequest(version: version, jobID: job.id, operation: operation,
                                                preserveConformity: false, compression: options,
                                                pageCompressionOverrides: pageOverrides, previewPage: previewPage,
                                                signaturePlacements: signaturePlacements,
                                                resourceFingerprint: resource?.fingerprint,
                                                resourceFormat: resource?.format.rawValue,
                                                resourceWidth: resource?.pixelWidth,
                                                resourceHeight: resource?.pixelHeight,
                                                resourceBitsPerComponent: resource?.bitsPerComponent)
            envelope[GhostscriptExtensionEnvelope.operation] = PDFProcessingEnvelope.operation
            envelope[PDFProcessingEnvelope.payload] = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
            if let password { envelope[PDFProcessingEnvelope.password] = Data(password.utf8).base64EncodedString() }
            // Exercise the actual Mac wire codec on both sides of the helper,
            // including UTF-8 passwords kept out of the Codable job request.
            let delivered = try MacOSXPCMessageCodec.decode(MacOSXPCMessageCodec.encode(envelope))
            let response = (handler ?? PDFProcessingRequestHandler(jobRoot: root)).handle(delivered)
            let decoded = try MacOSXPCMessageCodec.decode(MacOSXPCMessageCodec.encode(response))
            let payload: String = decoded[PDFProcessingEnvelope.response] ?? ""
            let reply = try JSONDecoder().decode(PDFProcessingReply.self, from: Data(payload.utf8))
            try require(reply.jobID == job.id && reply.version == PDFProcessingEnvelope.version, "Reply identity changed")
            return reply
        }
        func staged(_ name: String) throws -> PDFProcessingJobDirectory {
            let job = try PDFProcessingJobDirectory.create(root: root)
            try FileManager.default.copyItem(at: fixtures.appendingPathComponent(name), to: job.inputURL)
            return job
        }
        let job = try staged("InfoPlain.pdf")
        let original = try Data(contentsOf: job.inputURL)
        let finished = try send(job)
        try require(finished.status == .success && finished.outputBytes > 0, "Metadata request did not succeed")
        let pdf = PDFDocument(url: job.outputURL)
        try require(pdf?.pageCount == 1 && pdf?.documentAttributes?[PDFDocumentAttribute.titleAttribute] == nil, "Result did not reopen without title")
        try require(try Data(contentsOf: job.inputURL) == original, "Input changed")
        let candidate = try Data(contentsOf: job.outputURL)
        try require(try send(job).status == .failed, "Existing output was overwritten")
        try require(try Data(contentsOf: job.outputURL) == candidate, "Existing output canary changed")

        let versionJob = try staged("InfoPlain.pdf")
        try require(try send(versionJob, version: 99).status == .invalidRequest, "Invalid protocol accepted")
        try require(try send(versionJob, password: "bad\0password").status == .invalidRequest, "C-string truncation password accepted")
        let cancelled = PDFProcessingRequestHandler(jobRoot: root)
        cancelled.cancel()
        try require(try send(versionJob, handler: cancelled).status == .cancelled, "Pre-cancelled request ran")
        try require(!FileManager.default.fileExists(atPath: versionJob.outputURL.path), "Cancelled output remained")
        var lease = try PDFNativeRequestLease.acquire(library: directory)
        try require(lease != nil, "Could not acquire test engine gate")
        try require(try send(versionJob).status == .busy, "Overlapping native operation ran")
        lease = nil
        try require(try send(versionJob).status == .success, "Engine gate did not recover")

        let protected = try staged("InfoEncrypted-AES-256.pdf")
        try require(try send(protected, password: "wrong-password").status == .passwordRequired, "Wrong password accepted")
        try require(!FileManager.default.fileExists(atPath: protected.outputURL.path), "Password failure created output")
        for page: Int? in [nil, 0] {
            let compression = try staged("InfoICC.pdf")
            let options = page == nil
                ? PDFCompressionOptions(level: .strong, colorMode: .blackAndWhite, threshold: 60)
                : PDFCompressionOptions(level: .balanced, colorMode: .color, contrast: 20)
            let response = try send(compression, operation: .compress,
                                    options: options, previewPage: page,
                                    pageOverrides: [PDFPageCompressionOverride(pageIndex: 0, options: options)])
            try require(response.status == .success && response.outputBytes > 0, "Compression IPC did not return a candidate")
            try require(PDFDocument(url: compression.outputURL)?.pageCount == 1, "Compression IPC result did not reopen")
        }
        let invalidOverrides = try staged("InfoPlain.pdf")
        let repeated = PDFPageCompressionOverride(pageIndex: 0, options: .init())
        try require(try send(invalidOverrides, operation: .compress,
                             pageOverrides: [repeated, repeated]).status == .invalidRequest,
                    "Duplicate page compression overrides were accepted")
        try require(try send(invalidOverrides, operation: .compress,
                             pageOverrides: [PDFPageCompressionOverride(pageIndex: 1, options: .init())]).status == .failed,
                    "Out-of-range page compression override was accepted")
        try require(!FileManager.default.fileExists(atPath: invalidOverrides.outputURL.path),
                    "Invalid page compression override created output")
        let invalidPreview = try staged("InfoPlain.pdf")
        try require(try send(invalidPreview, previewPage: 0).status == .invalidRequest, "Metadata accepted a compression-only preview parameter")

        let signature = try staged("InfoPlain.pdf")
        let twoPages = try PDFDocument(url: signature.inputURL).unwrap("Signature fixture did not open")
        let duplicateSource = try PDFDocument(url: signature.inputURL).unwrap("Signature fixture duplicate did not open")
        let duplicatePage = try duplicateSource.page(at: 0).unwrap("Signature fixture page missing")
        twoPages.insert(duplicatePage, at: 1)
        try require(twoPages.write(to: signature.inputURL), "Could not create two-page signature fixture")
        let unsignedDocument = try PDFDocument(url: signature.inputURL).unwrap("Unsigned signature fixture did not reopen")
        let unsignedPixels = try renderedPixels(
            of: try unsignedDocument.page(at: 0).unwrap("Unsigned signature fixture page missing")
        )
        try FileManager.default.copyItem(at: dummySignatureFont, to: signature.signatureFontURL)
        let placements = [
            PDFSignaturePlacement(pageIndex: 0, x: 40, y: 80),
            PDFSignaturePlacement(pageIndex: 0, x: 120, y: 180, fontSize: 72),
            PDFSignaturePlacement(pageIndex: 1, x: 60, y: 100, fontSize: 35),
        ]
        let signatureReply = try send(signature, operation: .addSignatures,
                                      signaturePlacements: placements)
        try require(signatureReply.status == .success, "Signature insertion failed")
        let signedDocument = try PDFDocument(url: signature.outputURL).unwrap("Signed PDF did not reopen")
        try require(signedDocument.pageCount == 2, "Signature insertion changed page count")
        let signedPixels = try renderedPixels(
            of: try signedDocument.page(at: 0).unwrap("Signed PDF page missing")
        )
        try require(signedPixels != unsignedPixels, "Signatures did not change the rendered PDF page")
        let signatureReport = try PDFInspectionService.inspect(
            url: signature.outputURL, fileName: "Signed.pdf", password: nil
        )
        let embeddedSignatures = signatureReport.sections(in: .fonts).filter {
            $0.title == "AAAAAC+SignatureFont-Book" && $0.resource != nil
        }
        try require(embeddedSignatures.count == 1,
                    "Multiple placements did not share exactly one embedded signature font")
        let invalidSignature = try staged("InfoPlain.pdf")
        try require(try send(invalidSignature, operation: .addSignatures).status == .invalidRequest,
                    "Empty signature request was accepted")
        try require(try send(invalidSignature, signaturePlacements: [placements[0]]).status == .invalidRequest,
                    "Signature placement was accepted for another operation")

        let iccReport = try PDFInspectionService.inspect(url: fixtures.appendingPathComponent("InfoICC.pdf"), fileName: "InfoICC.pdf", password: nil)
        let iccResource = try iccReport.exportableResources.first { $0.kind == .iccProfile }.unwrap("ICC resource missing")
        let iccJob = try staged("InfoICC.pdf")
        let iccReply = try send(iccJob, operation: .extractResource, resource: iccResource)
        try require(iccReply.status == .success, "ICC extraction failed")
        let iccData = try Data(contentsOf: iccJob.outputURL)
        let iccDigest = SHA256.hash(data: iccData).map { String(format: "%02x", $0) }.joined()
        try require(iccDigest == iccResource.fingerprint, "ICC bytes changed during extraction")

        let imageReport = try PDFInspectionService.inspect(url: fixtures.appendingPathComponent("InfoInlineImage.pdf"), fileName: "InfoInlineImage.pdf", password: nil)
        let imageResource = try imageReport.exportableResources.first { $0.kind == .image }.unwrap("Inline image resource missing")
        let imageJob = try staged("InfoInlineImage.pdf")
        let imageReply = try send(imageJob, operation: .extractResource, resource: imageResource)
        try require(imageReply.status == .success, "Inline image extraction failed")
        try require(try Data(contentsOf: imageJob.outputURL).starts(with: [0x89, 0x50, 0x4e, 0x47]), "Inline image is not PNG")

        let predictorURL = directory.appendingPathComponent("PredictorImage.pdf")
        try pdfWithTIFFPredictorImage().write(to: predictorURL)
        let predictorReport = try PDFInspectionService.inspect(url: predictorURL, fileName: "PredictorImage.pdf", password: nil)
        let predictorResource = try predictorReport.exportableResources.first { $0.kind == .image }.unwrap("Predictor image resource missing")
        let predictorJob = try PDFProcessingJobDirectory.create(root: root)
        try FileManager.default.copyItem(at: predictorURL, to: predictorJob.inputURL)
        let predictorReply = try send(predictorJob, operation: .extractResource, resource: predictorResource)
        try require(predictorReply.status == .success, "TIFF predictor image extraction failed")
        let predictorSource = try CGImageSourceCreateWithURL(predictorJob.outputURL as CFURL, nil).unwrap("Predictor PNG could not be opened")
        let predictorImage = try CGImageSourceCreateImageAtIndex(predictorSource, 0, nil).unwrap("Predictor PNG could not be decoded")
        try require(predictorImage.width == 4 && predictorImage.height == 2, "Predictor PNG dimensions changed")

        let runLengthURL = directory.appendingPathComponent("RunLengthImage.pdf")
        try pdfWithRunLengthImage().write(to: runLengthURL)
        let runLengthReport = try PDFInspectionService.inspect(url: runLengthURL, fileName: "RunLengthImage.pdf", password: nil)
        let runLengthResource = try runLengthReport.exportableResources.first { $0.kind == .image }.unwrap("Run-length image resource missing")
        try require(runLengthResource.format == .png && runLengthResource.pixelWidth == 8 &&
                    runLengthResource.pixelHeight == 2 && runLengthResource.bitsPerComponent == 1,
                    "Run-length image descriptor changed")
        let runLengthJob = try PDFProcessingJobDirectory.create(root: root)
        try FileManager.default.copyItem(at: runLengthURL, to: runLengthJob.inputURL)
        let runLengthReply = try send(runLengthJob, operation: .extractResource, resource: runLengthResource)
        try require(runLengthReply.status == .success, "Run-length image extraction failed")
        let runLengthSource = try CGImageSourceCreateWithURL(runLengthJob.outputURL as CFURL, nil).unwrap("Run-length PNG could not be opened")
        let runLengthImage = try CGImageSourceCreateImageAtIndex(runLengthSource, 0, nil).unwrap("Run-length PNG could not be decoded")
        try require(runLengthImage.width == 8 && runLengthImage.height == 2, "Run-length PNG dimensions changed")

        let largeImageURL = directory.appendingPathComponent("LargeImage.pdf")
        try pdfWithLargeImage().write(to: largeImageURL)
        let largeImageReport = try PDFInspectionService.inspect(url: largeImageURL, fileName: "LargeImage.pdf", password: nil)
        let largeImageResource = try largeImageReport.exportableResources.first { $0.kind == .image }.unwrap("Large image resource missing")
        let largeImageJob = try PDFProcessingJobDirectory.create(root: root)
        try FileManager.default.copyItem(at: largeImageURL, to: largeImageJob.inputURL)
        let largeImageReply = try send(largeImageJob, operation: .extractResource, resource: largeImageResource)
        try require(largeImageReply.status == .success, "Large image extraction failed")
        let largeImageSource = try CGImageSourceCreateWithURL(largeImageJob.outputURL as CFURL, nil).unwrap("Large image PNG could not be opened")
        let largeImage = try CGImageSourceCreateImageAtIndex(largeImageSource, 0, nil).unwrap("Large image PNG could not be decoded")
        try require(largeImage.width == 8_000 && largeImage.height == 8_000, "Large image PNG dimensions changed")

        let attachmentReport = try PDFInspectionService.inspect(url: fixtures.appendingPathComponent("InfoAttachment.pdf"), fileName: "InfoAttachment.pdf", password: nil)
        let attachment = try attachmentReport.exportableResources.first { $0.kind == .attachment }.unwrap("Attachment resource missing")
        let attachmentJob = try staged("InfoAttachment.pdf")
        let attachmentReply = try send(attachmentJob, operation: .extractResource, resource: attachment)
        try require(attachmentReply.status == .success, "Attachment extraction failed")
        try require(try Data(contentsOf: attachmentJob.outputURL).starts(with: Data("iPS2PDF embedded attachment".utf8)), "Attachment bytes changed")

        let fontReport = try PDFInspectionService.inspect(url: fixtures.appendingPathComponent("InfoEmbeddedSubset.pdf"), fileName: "InfoEmbeddedSubset.pdf", password: nil)
        let font = try fontReport.exportableResources.first { $0.kind == .font }.unwrap("Embedded font resource missing")
        let fontJob = try staged("InfoEmbeddedSubset.pdf")
        let fontReply = try send(fontJob, operation: .extractResource, resource: font)
        try require(fontReply.status == .success, "Embedded font extraction failed")
        let fontData = try Data(contentsOf: fontJob.outputURL)
        if font.format == .type1 {
            try require(fontData.starts(with: [0x80, 0x01]), "Type 1 font was not reconstructed as PFB")
        } else if font.format == .openType {
            let provider = try CGDataProvider(data: fontData as CFData).unwrap("OpenType data provider could not be created")
            try require(fontData.starts(with: Data("OTTO".utf8)) && CGFont(provider) != nil,
                        "Embedded CFF font was not exported as valid OpenType")
        } else {
            let fontDigest = SHA256.hash(data: fontData).map { String(format: "%02x", $0) }.joined()
            try require(fontDigest == font.fingerprint, "Embedded font bytes changed during extraction")
        }

        let cff = try Data(base64Encoded: "AQAEAgABAgABABpBQkNERUYrQXBwbGVHYXJhbW9uZC1Cb29rAAECAAEAHx0AAAGHAB0AAAGIAh0AAAGJAx0AAAB+Dx0AAACDEQADAgABAAgAGwApMi4wLTEuMEFwcGxlIEdhcmFtb25kIEJvb2tBcHBsZSBHYXJhbW9uZAAAAAABAHUAAwIAAQACAAMARg4Oi4sVjIwFjIwFjIwFjIwFjIwFjIwFjIwFjIwFjIwFjIwFjIwFjIwFjIwFjIwFjIwFjIwFjIwFjIwFjIwFjIwFjIwFDg==").unwrap("CFF fixture is invalid")
        let cffURL = directory.appendingPathComponent("EmbeddedCFF.pdf")
        try pdfWithEmbeddedCFF(cff).write(to: cffURL)
        let cffReport = try PDFInspectionService.inspect(url: cffURL, fileName: "EmbeddedCFF.pdf", password: nil)
        let cffFont = try cffReport.exportableResources.first { $0.kind == .font }.unwrap("CFF font resource missing")
        try require(cffFont.format == .openType && cffFont.suggestedFilename.hasSuffix("-subset.otf"),
                    "Readable bare CFF was not offered as an OpenType subset")
        let cffJob = try PDFProcessingJobDirectory.create(root: root)
        try FileManager.default.copyItem(at: cffURL, to: cffJob.inputURL)
        let cffReply = try send(cffJob, operation: .extractResource, resource: cffFont)
        try require(cffReply.status == .success, "CFF to OpenType extraction failed")
        let openType = try Data(contentsOf: cffJob.outputURL)
        let provider = try CGDataProvider(data: openType as CFData).unwrap("OpenType data provider could not be created")
        let convertedFont = try CGFont(provider).unwrap("Generated OpenType font was rejected by Apple font services")
        try require(openType.starts(with: Data("OTTO".utf8)) && convertedFont.numberOfGlyphs == 3,
                    "Generated OpenType font lost its CFF glyphs")
        print("PASS PDF helper contract: wire codec, native result, original preservation, exclusive output, versions, cancellation, serialization, password failures, compression, previews, shared signature-font embedding, ICC, inline, TIFF-predictor, run-length and large image, attachment and OpenType font extraction")
    }
}

private extension Optional {
    func unwrap(_ message: String) throws -> Wrapped {
        guard let self else { throw NSError(domain: "PDFProcessingIPCSmoke", code: 2, userInfo: [NSLocalizedDescriptionKey: message]) }
        return self
    }
}
