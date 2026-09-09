#include "PDFStructuralSmoke.h"
#include "PDFStructuralSanitizer.h"
#include "PDFStructuralWriter.h"
#include "PDFConformityMetadata.h"
#include "PDFCompressionPolicy.h"
#include "PDFOpenTypeFont.h"

#include <qpdf/QPDFPageDocumentHelper.hh>
#include <qpdf/QPDFWriter.hh>
#include <algorithm>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string_view>
#include <vector>
#include <zlib.h>

namespace {
using Object = QPDFObjectHandle;
namespace fs = std::filesystem;

void require(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
}

std::string decoded(Object stream) {
    auto bytes = stream.getStreamData();
    return {reinterpret_cast<const char*>(bytes->getBuffer()), bytes->getSize()};
}

void append16(std::string& bytes, uint16_t value) {
    bytes.push_back(static_cast<char>(value >> 8));
    bytes.push_back(static_cast<char>(value));
}

void append32(std::string& bytes, uint32_t value) {
    for (int shift : {24, 16, 8, 0}) bytes.push_back(static_cast<char>(value >> shift));
}

std::string cffIndex(const std::vector<std::string>& objects) {
    std::string result;
    append16(result, static_cast<uint16_t>(objects.size()));
    if (objects.empty()) return result;
    result.push_back(2);
    uint16_t offset = 1;
    append16(result, offset);
    for (const auto& object : objects) {
        offset = static_cast<uint16_t>(offset + object.size());
        append16(result, offset);
    }
    for (const auto& object : objects) result += object;
    return result;
}

void appendDictionaryInteger(std::string& dictionary, uint32_t value) {
    dictionary.push_back(29);
    append32(dictionary, value);
}

std::string signatureCFFDictionary(uint32_t charsetOffset, uint32_t charStringsOffset) {
    std::string result;
    for (const auto& [value, operation] : std::array<std::pair<uint32_t, uint8_t>, 5>{
             std::pair{391u, uint8_t{0}}, std::pair{392u, uint8_t{2}}, std::pair{393u, uint8_t{3}},
             std::pair{charsetOffset, uint8_t{15}}, std::pair{charStringsOffset, uint8_t{17}}}) {
        appendDictionaryInteger(result, value);
        result.push_back(static_cast<char>(operation));
    }
    return result;
}

std::string signatureCFF(const std::string& subsetPrefix) {
    std::string signatureGlyph;
    for (char byte : {char(139), char(139), char(21)}) signatureGlyph.push_back(byte);
    for (int index = 0; index < 21; ++index)
        for (char byte : {char(140), char(140), char(5)}) signatureGlyph.push_back(byte);
    signatureGlyph.push_back(char(14));
    const auto names = cffIndex({subsetPrefix + "+AppleGaramond-Book"});
    const auto strings = cffIndex({"2.0-1.0", "Apple Garamond Book", "Apple Garamond"});
    const auto subroutines = cffIndex({});
    const auto charStrings = cffIndex({std::string(1, char(14)), std::string(1, char(14)), signatureGlyph});
    const std::string header({char(1), char(0), char(4), char(2)});
    auto dictionary = signatureCFFDictionary(0, 0);
    auto dictionaries = cffIndex({dictionary});
    const uint32_t charsetOffset = static_cast<uint32_t>(header.size() + names.size() + dictionaries.size() +
                                                         strings.size() + subroutines.size());
    const uint32_t charStringsOffset = charsetOffset + 5;
    dictionary = signatureCFFDictionary(charsetOffset, charStringsOffset);
    dictionaries = cffIndex({dictionary});
    std::string charset(1, char(0));
    append16(charset, 1);   // space
    append16(charset, 117); // quotesinglbase, selected by MacRoman code E2
    return header + names + dictionaries + strings + subroutines + charset + charStrings;
}

uint16_t read16(const std::vector<uint8_t>& bytes, size_t offset) {
    require(offset + 2 <= bytes.size(), "Generated OpenType integer is out of bounds");
    return static_cast<uint16_t>((bytes[offset] << 8) | bytes[offset + 1]);
}

uint32_t read32(const std::vector<uint8_t>& bytes, size_t offset) {
    require(offset + 4 <= bytes.size(), "Generated OpenType integer is out of bounds");
    uint32_t result = 0;
    for (size_t index = 0; index < 4; ++index) result = (result << 8) | bytes[offset + index];
    return result;
}

void openTypeCFFContainer() {
    const std::string source = signatureCFF("ABCDEF");
    const auto output = ips2pdf::openTypeContainerForCFF(std::span<const uint8_t>(
        reinterpret_cast<const uint8_t*>(source.data()), source.size()));
    require(output.size() > source.size() && std::equal(output.begin(), output.begin() + 4, "OTTO"),
            "Bare CFF was not wrapped in an OpenType sfnt");
    const uint16_t tableCount = read16(output, 4);
    bool foundCFF = false;
    for (uint16_t index = 0; index < tableCount; ++index) {
        const size_t record = 12 + index * 16;
        require(record + 16 <= output.size(), "Generated OpenType table record is truncated");
        if (!std::equal(output.begin() + record, output.begin() + record + 4, "CFF ")) continue;
        const uint32_t offset = read32(output, record + 8);
        const uint32_t length = read32(output, record + 12);
        require(offset <= output.size() && length <= output.size() - offset && length == source.size() &&
                    std::equal(output.begin() + offset, output.begin() + offset + length,
                               reinterpret_cast<const uint8_t*>(source.data())),
                "OpenType wrapping changed the embedded CFF program");
        foundCFF = true;
    }
    require(foundCFF, "Generated OpenType font has no CFF table");
    uint32_t sum = 0;
    for (size_t offset = 0; offset < output.size(); offset += 4) sum += read32(output, offset);
    require(sum == 0xb1b0afba, "Generated OpenType checksum is invalid");
    bool rejected = false;
    try { ips2pdf::openTypeContainerForCFF(std::array<uint8_t, 4>{1, 0, 4, 0}); }
    catch (const std::exception&) { rejected = true; }
    require(rejected, "Malformed bare CFF was labeled as OpenType");
    std::cout << "PASS font export: valid OpenType/CFF container, exact glyph program and malformed fallback\n";
}

std::string deflated(std::string_view bytes) {
    uLongf size = compressBound(bytes.size());
    std::string result(size, '\0');
    require(compress2(reinterpret_cast<Bytef*>(result.data()), &size,
                      reinterpret_cast<const Bytef*>(bytes.data()), bytes.size(), Z_BEST_COMPRESSION) == Z_OK,
            "Could not create the signature-font test stream");
    result.resize(size);
    return result;
}

Object signatureFont(QPDF& pdf, const std::string& prefix, bool signatureWidth, Object& program) {
    const auto cff = signatureCFF(prefix);
    program = pdf.newStream("");
    program.replaceStreamData(deflated(cff), Object::newName("/FlateDecode"), Object::newNull());
    program.getDict().replaceKey("/Subtype", Object::newName("/Type1C"));
    auto descriptor = pdf.makeIndirectObject(Object::newDictionary());
    descriptor.replaceKey("/Type", Object::newName("/FontDescriptor"));
    descriptor.replaceKey("/FontName", Object::newName("/" + prefix + "+AppleGaramond-Book"));
    descriptor.replaceKey("/FontFile3", program);
    std::vector<Object> values(195, Object::newInteger(0));
    values.front() = Object::newInteger(219);
    values.back() = Object::newInteger(signatureWidth ? 3474 : 219);
    auto font = pdf.makeIndirectObject(Object::newDictionary());
    font.replaceKey("/Type", Object::newName("/Font"));
    font.replaceKey("/Subtype", Object::newName("/Type1"));
    font.replaceKey("/BaseFont", Object::newName("/" + prefix + "+AppleGaramond-Book"));
    font.replaceKey("/Encoding", Object::newName("/MacRomanEncoding"));
    font.replaceKey("/FirstChar", Object::newInteger(32));
    font.replaceKey("/LastChar", Object::newInteger(226));
    font.replaceKey("/Widths", Object::newArray(values));
    font.replaceKey("/FontDescriptor", descriptor);
    return font;
}

void replaceOnce(std::string& value, std::string_view from, std::string_view to) {
    require(from.size() == to.size(), "Signature-font test replacement length changed");
    const auto offset = value.find(from);
    require(offset != std::string::npos, "Signature-font test name is missing");
    value.replace(offset, from.size(), to);
    require(value.find(from) == std::string::npos, "Signature-font test contains a duplicate name");
}

void signatureFontAnonymization() {
    QPDF pdf;
    pdf.emptyPDF();
    Object targetProgram, ordinaryProgram;
    auto target = signatureFont(pdf, "ABCDEF", true, targetProgram);
    auto ordinary = signatureFont(pdf, "GHIJKL", false, ordinaryProgram);
    auto fonts = Object::newDictionary({{"/Signature", target}, {"/OrdinaryQuote", ordinary}});
    auto page = pdf.makeIndirectObject(Object::parse("<< /Type /Page /MediaBox [0 0 300 300] >>"));
    page.replaceKey("/Resources", Object::newDictionary({{"/Font", fonts}}));
    page.replaceKey("/Contents", pdf.newStream("BT /Signature 50 Tf <E220> Tj ET"));
    QPDFPageDocumentHelper(pdf).addPage(QPDFPageObjectHelper(page), false);
    const auto originalCFF = decoded(targetProgram);
    const auto ordinaryCFF = decoded(ordinaryProgram);

    const auto result = ips2pdf::sanitizePDFMetadata(pdf);
    require(result.signatureFontsAnonymized == 1, "The Pages signature font was not uniquely recognized");
    require(target.getKey("/BaseFont").isNameAndEquals("/ABCDEF+SignatureFont-Book") &&
            target.getKey("/FontDescriptor").getKey("/FontName").isNameAndEquals("/ABCDEF+SignatureFont-Book"),
            "The PDF signature-font names were not anonymized consistently");
    auto expectedCFF = originalCFF;
    replaceOnce(expectedCFF, "ABCDEF+AppleGaramond-Book", "ABCDEF+SignatureFont-Book");
    replaceOnce(expectedCFF, "Apple Garamond Book", "Signature Font Book");
    replaceOnce(expectedCFF, "Apple Garamond", "Signature Font");
    require(decoded(targetProgram) == expectedCFF, "The signature CFF changed outside its three name strings");
    require(ordinary.getKey("/BaseFont").isNameAndEquals("/GHIJKL+AppleGaramond-Book") &&
            decoded(ordinaryProgram) == ordinaryCFF, "An ordinary Apple Garamond subset was anonymized");
    require(ips2pdf::sanitizePDFMetadata(pdf).signatureFontsAnonymized == 0,
            "Signature-font anonymization is not idempotent");
    std::cout << "PASS metadata signature font: exact glyph subset anonymized without changing its outline\n";
}

std::vector<std::string> retainedPayloads(QPDF& pdf) {
    std::vector<std::string> data;
    for (auto object : pdf.getAllObjects()) {
        if (object.isDictionary()) {
            for (const char* key : {"/FontFile", "/FontFile2", "/FontFile3", "/DestOutputProfile"}) {
                auto payload = object.getKey(key);
                if (payload.isStream()) data.push_back(decoded(payload));
            }
        }
        if (object.isStream() && object.getDict().getKey("/Type").isNameAndEquals("/EmbeddedFile"))
            data.push_back(decoded(object));
    }
    std::sort(data.begin(), data.end());
    return data;
}

void write(QPDF& pdf, const fs::path& output) {
    QPDFWriter writer(pdf, output.c_str());
    writer.setPreserveUnreferencedObjects(false);
    writer.setObjectStreamMode(qpdf_o_preserve);
    writer.setStreamDataMode(qpdf_s_preserve);
    writer.setPreserveEncryption(true);
    writer.write();
}

void verifyNoMetadata(QPDF& pdf) {
    require(pdf.getTrailer().getKey("/Info").isNull(), "Info survived metadata cleanup");
    for (auto object : pdf.getAllObjects()) {
        auto dictionary = object.isStream() ? object.getDict() : object;
        if (!dictionary.isDictionary()) continue;
        require(!dictionary.hasKey("/Metadata"), "Object XMP survived metadata cleanup");
        require(!dictionary.hasKey("/PieceInfo"), "Application private data survived metadata cleanup");
    }
}

void synthetic(const fs::path& fixtures, const fs::path& output) {
    QPDF pdf;
    pdf.processFile((fixtures / "InfoPlain.pdf").c_str());
    auto root = pdf.getRoot();
    auto page = QPDFPageDocumentHelper(pdf).getAllPages().at(0).getObjectHandle();
    auto metadata = pdf.newStream("<private>Hidden author marker</private>");
    metadata.getDict().replaceKey("/Type", Object::newName("/Metadata"));
    metadata.getDict().replaceKey("/Subtype", Object::newName("/XML"));
    root.replaceKey("/Metadata", metadata);
    page.replaceKey("/Metadata", metadata);
    page.replaceKey("/PieceInfo", Object::parse("<< /Private << /LastModified (D:20260101000000Z) /Private (Hidden revision marker) >> >>"));
    auto attachment = pdf.newStream("Payload with its own author must remain byte-identical");
    attachment.getDict().replaceKey("/Type", Object::newName("/EmbeddedFile"));
    attachment.getDict().replaceKey("/Params", Object::parse("<< /CreationDate (D:20260101000000Z) /ModDate (D:20260101000000Z) >>"));
    auto file = pdf.makeIndirectObject(Object::parse("<< /Type /Filespec /F (fixture.txt) /AFRelationship /Data >>"));
    file.replaceKey("/EF", Object::newDictionary({{"/F", attachment}}));
    root.replaceKey("/AF", Object::newArray({file}));
    auto annotation = pdf.makeIndirectObject(Object::parse(
        "<< /Type /Annot /Subtype /Text /Rect [10 10 30 30] /T (Hidden author marker) "
        "/M (D:20260101000000Z) /CreationDate (D:20260101000000Z) /NM (functional-id) /Contents (Keep comment text) >>"));
    auto reply = pdf.makeIndirectObject(Object::parse("<< /Type /Annot /Subtype /Text /Rect [10 10 30 30] /Contents (Keep reply text) >>"));
    reply.replaceKey("/IRT", annotation);
    auto signature = pdf.makeIndirectObject(Object::parse(
        "<< /Type /Annot /Subtype /Widget /FT /Sig /F 4 /T (SignedField) /Rect [40 40 160 80] "
        "/V << /Type /Sig /Contents (Hidden signature marker) /ByteRange [0 1 2 3] >> >>"));
    auto appearance = pdf.newStream("0 0 1 rg 0 0 120 40 re f");
    appearance.getDict().replaceKey("/Type", Object::newName("/XObject"));
    appearance.getDict().replaceKey("/Subtype", Object::newName("/Form"));
    appearance.getDict().replaceKey("/BBox", Object::parse("[0 0 120 40]"));
    signature.replaceKey("/AP", Object::newDictionary({{"/N", appearance}}));
    signature.replaceKey("/P", page);
    auto emptySignature = pdf.makeIndirectObject(Object::parse("<< /FT /Sig /T (UnsignedField) >>"));
    auto ordinaryField = pdf.makeIndirectObject(Object::parse("<< /FT /Tx /T (FunctionalFieldName) /V (Keep editable value) >>"));
    auto form = Object::newDictionary({{"/Fields", Object::newArray({signature, emptySignature, ordinaryField})}});
    form.replaceKey("/CO", Object::newArray({signature, ordinaryField}));
    root.replaceKey("/AcroForm", form);
    page.replaceKey("/Annots", Object::newArray({annotation, reply, signature}));
    auto payloads = retainedPayloads(pdf);
    const auto appearanceBytes = decoded(appearance);
    const auto result = ips2pdf::sanitizePDFMetadata(pdf);
    require(result.signaturesRemoved, "Signature removal warning missing");
    require(signature.getKey("/Subtype").isNameAndEquals("/Widget") && signature.getKey("/V").isNull(), "Signature field or signature removal lost");
    require(decoded(appearance) == appearanceBytes, "Signature vector appearance changed");
    require(decoded(signature.getKey("/AP").getKey("/N")).empty(), "Signature appearance would paint twice");
    require(form.getKey("/Fields").getArrayNItems() == 3, "Existing form fields were removed");
    require(form.getKey("/CO").getArrayNItems() == 2, "Calculation order changed");
    require(reply.getKey("/IRT").isSameObjectAs(annotation), "Comment reply relationship lost");
    require(annotation.getKey("/Contents").getUTF8Value() == "Keep comment text", "Comment content removed");
    require(annotation.getKey("/T").isNull() && annotation.getKey("/M").isNull(), "Annotation metadata retained");
    const auto path = output / "MetadataSynthetic-cleaned.pdf";
    write(pdf, path);
    QPDF reopened;
    reopened.processFile(path.c_str());
    verifyNoMetadata(reopened);
    require(retainedPayloads(reopened) == payloads, "Embedded payload changed");
    std::ifstream source(path, std::ios::binary);
    std::string bytes((std::istreambuf_iterator<char>(source)), {});
    for (const char* marker : {"Hidden author marker", "Hidden revision marker", "Hidden signature marker"})
        require(bytes.find(marker) == std::string::npos, "Removed historical bytes remain in full output");
    std::cout << "PASS metadata synthetic: attachment, comments, fields and signature appearance retained\n";
}
} // namespace

void runStructuralSmoke(const fs::path& fixtures, const fs::path& output) {
    openTypeCFFContainer();
    signatureFontAnonymization();
    {
        QPDF pdf; pdf.emptyPDF();
        pdf.getTrailer().replaceKey("/Info", Object::parse("<< /GTS_PDFXVersion (PDF/X-4) /Trapped /False /Title (Private title) >>"));
        const std::string original = R"(<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description rdf:about="" xmlns:pdfxid="http://www.npes.org/pdfx/ns/id/" xmlns:pdf="http://ns.adobe.com/pdf/1.3/" xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmlns:xmpMM="http://ns.adobe.com/xap/1.0/mm/" pdfxid:GTS_PDFXVersion="PDF/X-4" pdf:Trapped="False" xmp:CreatorTool="Private application" xmp:CreateDate="1999-01-01" xmpMM:DocumentID="Private document identity" xmpMM:RenditionClass="proof:pdf"/></rdf:RDF></x:xmpmeta>)";
        pdf.getRoot().replaceKey("/Metadata", pdf.newStream(original));
        const auto retained = ips2pdf::metadataPreservingConformity(pdf);
        require(retained.infoStrings.empty() && retained.xmp.find("PDF/X-4") != std::string::npos,
                "PDF/X-4 identification was not retained in XMP");
        require(retained.xmp.find("Private") == std::string::npos && retained.xmp.find("1999-01-01") == std::string::npos,
                "PDF/X cleanup retained private history");
        for (const char* required : {"CreateDate", "ModifyDate", "MetadataDate", "DocumentID", "VersionID", "RenditionClass", "proof:pdf", "Trapped", "Document"})
            require(retained.xmp.find(required) != std::string::npos, "Required PDF/X-4 metadata is missing");
        auto mixed = original;
        mixed.insert(mixed.find("pdfxid:GTS_PDFXVersion"), "xmlns:pdfaid=\"http://www.aiim.org/pdfa/ns/id/\" pdfaid:part=\"2\" pdfaid:conformance=\"B\" ");
        pdf.getRoot().replaceKey("/Metadata", pdf.newStream(mixed));
        require(ips2pdf::metadataPreservingConformity(pdf).xmp.find("PDF/X identification schema") != std::string::npos,
                "Combined PDF/A and PDF/X lost its extension schema");
        pdf.getTrailer().replaceKey("/Info", Object::parse("<< /GTS_PDFXVersion (PDF/X-3:2003) /Trapped /False /Title (Private title) >>"));
        bool conflict = false;
        try { ips2pdf::metadataPreservingConformity(pdf); } catch (const ips2pdf::PDFConformityError&) { conflict = true; }
        require(conflict, "Conflicting Info and XMP PDF/X declarations were accepted");
        pdf.getRoot().removeKey("/Metadata");
        const auto legacy = ips2pdf::metadataPreservingConformity(pdf);
        require(legacy.xmp.empty() && legacy.trappedState == "False" && legacy.infoStrings.at("/Title") == "Document" &&
                legacy.infoStrings.contains("/CreationDate") && legacy.infoStrings.contains("/ModDate"), "Legacy PDF/X lost required minimal Info fields");
        auto onlyXMP = original;
        onlyXMP.replace(onlyXMP.find("PDF/X-4"), 7, "PDF/X-3:2003");
        pdf.getTrailer().removeKey("/Info");
        pdf.getRoot().replaceKey("/Metadata", pdf.newStream(onlyXMP));
        ips2pdf::sanitizePDFMetadata(pdf, ips2pdf::metadataPreservingConformity(pdf));
        require(pdf.getTrailer().getKey("/Info").getKey("/Trapped").isNameAndEquals("/False"),
                "Legacy PDF/X did not retain its XMP trapped state in the required Info field");
        std::cout << "PASS PDF/X metadata: modern/legacy required fields, reset private identity/history, PDF/A extension schema and conflicting declarations\n";
    }
    {
        QPDF pdf;
        pdf.emptyPDF();
        const std::string xmp = R"(<x:xmpmeta xmlns:x="adobe:ns:meta/">
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
        <rdf:Description rdf:about="" xmlns:pdfaid="http://www.aiim.org/pdfa/ns/id/"
          xmlns:pdfuaid="http://www.aiim.org/pdfua/ns/id/" xmlns:dc="http://purl.org/dc/elements/1.1/"
          xmlns:xmp="http://ns.adobe.com/xap/1.0/" pdfaid:part="2" pdfaid:conformance="A" pdfuaid:part="1">
        <dc:title><rdf:Alt><rdf:li xml:lang="x-default">Meaningful &amp; accessible title</rdf:li>
        <rdf:li xml:lang="de">Aussagekräftiger Titel</rdf:li></rdf:Alt></dc:title>
        <dc:creator><rdf:Seq><rdf:li>Private author</rdf:li></rdf:Seq></dc:creator>
        <xmp:CreatorTool>Private application</xmp:CreatorTool>
        </rdf:Description></rdf:RDF></x:xmpmeta>)";
        pdf.getRoot().replaceKey("/Metadata", pdf.newStream(xmp));
        const auto retention = ips2pdf::metadataPreservingConformity(pdf);
        require(retention.xmp.find("Private author") == std::string::npos &&
                retention.xmp.find("Private application") == std::string::npos, "Private XMP survived conformity retention");
        require(retention.xmp.find("Meaningful &amp; accessible title") != std::string::npos &&
                retention.xmp.find("xml:lang=\"de\"") != std::string::npos, "Required accessible title was damaged");
        require(retention.xmp.find("pdfaExtension:schemas") != std::string::npos, "PDF/A lost the required PDF/UA extension schema");
        ips2pdf::sanitizePDFMetadata(pdf, retention);
        require(ips2pdf::metadataPreservingConformity(pdf).xmp == retention.xmp, "Conformity cleanup is not idempotent");
        auto conflict = xmp;
        conflict.insert(conflict.find("</rdf:Description>"), "<pdfaid:part>3</pdfaid:part>");
        pdf.getRoot().replaceKey("/Metadata", pdf.newStream(conflict));
        bool rejected = false;
        try { ips2pdf::metadataPreservingConformity(pdf); } catch (const std::exception&) { rejected = true; }
        require(rejected, "Conflicting declarations were silently combined");
        pdf.getRoot().replaceKey("/Metadata", pdf.newStream("<!DOCTYPE x [<!ENTITY private 'secret'>]><x>&private;</x>"));
        rejected = false;
        try { ips2pdf::metadataPreservingConformity(pdf); } catch (const std::exception&) { rejected = true; }
        require(rejected, "XMP with a DTD was accepted");
        std::cout << "PASS conformity metadata: multilingual UA title, A/UA extension schema, privacy and conflict handling\n";
    }
    {
        ips2pdf::PDFCompressionPolicy policy;
        require(policy.level == ips2pdf::PDFCompressionLevel::balanced && !policy.monochrome &&
                    policy.threshold == 75 && policy.contrast == 25 && policy.paperCleanup == 50,
                "Compression defaults are not Color, Balanced, threshold 75, contrast 25 and paper cleanup 50");
        policy.level = ips2pdf::PDFCompressionLevel::strong;
        require(policy.maximumPPI() == 110 && policy.jpegQuality() == 60,
                "Strong color compression does not protect its smaller bitmap");
        require(policy.resizeScale(72) == 1 && std::abs(policy.resizeScale(225) - 110.0 / 225.0) < 0.001,
                "Color compression did not apply its strict scan resolution cap");
        policy.level = ips2pdf::PDFCompressionLevel::gentle;
        require(policy.maximumPPI() == 225 && policy.jpegQuality() == 20,
                "Gentle color compression did not retain the high-resolution policy");
        policy.level = ips2pdf::PDFCompressionLevel::balanced;
        require(policy.maximumPPI() == 140 && policy.jpegQuality() == 40,
                "Balanced color compression lost its selected policy");
        policy.contrast = 100;
        policy.validate();
        policy.contrast = -1;
        bool invalidContrast = false;
        try { policy.validate(); } catch (const std::exception&) { invalidContrast = true; }
        require(invalidContrast, "Compression accepted a contrast below the UI range");
        policy.contrast = 25;
        policy.paperCleanup = -1;
        bool invalidCleanup = false;
        try { policy.validate(); } catch (const std::exception&) { invalidCleanup = true; }
        require(invalidCleanup, "Compression accepted paper cleanup below the UI range");
        policy.paperCleanup = 50;
        policy.monochrome = true;
        policy.level = ips2pdf::PDFCompressionLevel::strong;
        require(policy.maximumPPI() == 300 && policy.resizeScale(360) == 1,
                "Monochrome compression lost its scan-safe resampling margin");
        require(policy.threshold == 75, "Monochrome compression lost its default threshold");
        require(policy.blackPixel(0, 0, 0) && !policy.blackPixel(255, 255, 255), "Monochrome threshold endpoints are wrong");
        std::cout << "PASS compression policy: fresh defaults, scan-only color targets, counter-running JPEG quality and monochrome threshold\n";
    }
    synthetic(fixtures, output);
    for (const char* name : {"InfoEmbeddedFull.pdf", "InfoEmbeddedSubset.pdf", "InfoICC.pdf", "InfoType3.pdf",
                             "InfoEncrypted-RC4-40.pdf", "InfoEncrypted-RC4-128.pdf", "InfoEncrypted-AES-128.pdf",
                             "InfoEncrypted-AES-256.pdf", "InfoEncryptedIncremental.pdf", "InfoEncryptedXRefStream.pdf"}) {
        QPDF pdf;
        pdf.processFile((fixtures / name).c_str(), "user-test");
        const auto payloads = retainedPayloads(pdf);
        int revision = 0, permissions = 0;
        const bool encrypted = pdf.isEncrypted(revision, permissions);
        const auto pages = QPDFPageDocumentHelper(pdf).getAllPages().size();
        const auto path = output / (fs::path(name).stem().string() + "-metadata.pdf");
        fs::remove(path);
        const auto result = ips2pdf::removePDFMetadata(fixtures / name, path, "user-test");
        require(!result.protectionRemoved && result.outputBytes > 0, "Protection was unexpectedly removed");
        QPDF reopened;
        reopened.processFile(path.c_str(), "user-test");
        verifyNoMetadata(reopened);
        require(retainedPayloads(reopened) == payloads, "A retained font or profile payload changed");
        require(QPDFPageDocumentHelper(reopened).getAllPages().size() == pages, "Page count changed");
        int newRevision = 0, newPermissions = 0;
        require(reopened.isEncrypted(newRevision, newPermissions) == encrypted &&
                revision == newRevision && permissions == newPermissions, "Encryption or permissions changed");
        std::cout << "PASS metadata " << name << ": retained payloads and encryption permissions\n";
    }
    const auto outputPath = output / "Writer-canary.pdf";
    fs::remove(outputPath);
    {
        std::ofstream canary(outputPath);
        canary << "Existing file must never be replaced";
    }
    bool rejected = false;
    try { ips2pdf::removePDFMetadata(fixtures / "InfoPlain.pdf", outputPath, ""); }
    catch (const std::exception&) { rejected = true; }
    require(rejected && fs::file_size(outputPath) == 36, "Writer replaced an existing file");
    fs::remove(outputPath);
    rejected = false;
    try { ips2pdf::removePDFMetadata(fixtures / "InfoEncrypted-AES-256.pdf", outputPath, "wrong-password"); }
    catch (const QPDFExc& error) { rejected = error.getErrorCode() == qpdf_e_password; }
    require(rejected && !fs::exists(outputPath), "Password failure produced an output");
    for (const auto& [name, password] : std::vector<std::pair<std::string, std::string>>{
             {"InfoEmptyPassword.pdf", ""}, {"InfoUnicodePassword.pdf", "Päss (\\) € 🔒"}}) {
        const auto path = output / (fs::path(name).stem().string() + "-metadata.pdf");
        fs::remove(path);
        const auto result = ips2pdf::removePDFMetadata(fixtures / name, path, password);
        require(!result.protectionRemoved, "Opening password caused protection loss");
        QPDF reopened;
        reopened.processFile(path.c_str(), password.c_str());
        verifyNoMetadata(reopened);
    }
    std::cout << "PASS metadata writer: exclusive output, wrong/empty/Unicode passwords\n";
}
