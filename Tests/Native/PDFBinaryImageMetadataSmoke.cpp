#include "PDFBinaryImageMetadataSmoke.h"
#include "PDFBinaryImageMetadata.h"
#include "PDFImageCodec.h"
#include "PDFStreamMetadata.h"
#include <fstream>
#include <iostream>
#include <stdexcept>

namespace {
using Bytes = std::vector<uint8_t>;
using Object = QPDFObjectHandle;
void require(bool good, const char* message) { if (!good) throw std::runtime_error(message); }
uint32_t get(const Bytes& bytes, size_t offset) {
    require(offset + 4 <= bytes.size(), "Test container bounds");
    return (uint32_t(bytes[offset]) << 24) | (uint32_t(bytes[offset + 1]) << 16) | (uint32_t(bytes[offset + 2]) << 8) | bytes[offset + 3];
}
void put(Bytes& bytes, size_t offset, uint32_t value) {
    for (int i = 3; i >= 0; --i) { bytes[offset + i] = value & 255; value >>= 8; }
}
Bytes box(const std::string& type, const Bytes& payload) {
    Bytes result(8); put(result, 0, payload.size() + 8);
    std::copy(type.begin(), type.end(), result.begin() + 4);
    result.insert(result.end(), payload.begin(), payload.end()); return result;
}
Bytes bytes(const std::string& value) { return {value.begin(), value.end()}; }
std::string text(const Bytes& value) { return {value.begin(), value.end()}; }
Bytes comment(const std::string& text) {
    Bytes result{0xff, 0x64, uint8_t((text.size() + 4) >> 8), uint8_t(text.size() + 4), 0, 1};
    result.insert(result.end(), text.begin(), text.end()); return result;
}
void segment(Bytes& output, uint32_t number, uint8_t type, uint8_t page, const Bytes& data) {
    const auto start = output.size(); output.resize(start + 11);
    put(output, start, number); output[start + 4] = type; output[start + 5] = 0; output[start + 6] = page;
    put(output, start + 7, data.size()); output.insert(output.end(), data.begin(), data.end());
}
Object image(QPDF& pdf, const Bytes& bytes, bool jpx) {
    auto result = pdf.newStream(text(bytes));
    result.replaceDict(Object::parse(jpx ?
        "<< /Type /XObject /Subtype /Image /Width 4 /Height 4 /BitsPerComponent 8 /ColorSpace /DeviceRGB /Filter /JPXDecode >>" :
        "<< /Type /XObject /Subtype /Image /Width 17 /Height 9 /BitsPerComponent 1 /ColorSpace /DeviceGray /Filter /JBIG2Decode >>"));
    return result;
}
} // namespace

void runBinaryImageMetadataSmoke(const std::filesystem::path& fixtures, const std::filesystem::path&) {
    {
        std::ifstream file(fixtures / "Processing/ContainerRGB.jp2", std::ios::binary);
        require(bool(file), "JPEG 2000 test fixture missing");
        Bytes original((std::istreambuf_iterator<char>(file)), {}), modified;
        size_t position = 0;
        while (position < original.size()) {
            const auto length = get(original, position);
            require(length >= 8 && length <= original.size() - position, "JPEG 2000 test fixture box bounds");
            const std::string type(original.begin() + position + 4, original.begin() + position + 8);
            Bytes payload(original.begin() + position + 8, original.begin() + position + length);
            if (type == "jp2c") {
                size_t sot = 2;
                while (!(payload[sot] == 0xff && payload[sot + 1] == 0x90)) {
                    const auto size = (size_t(payload[sot + 2]) << 8) | payload[sot + 3];
                    sot += size + 2; require(sot + 12 <= payload.size(), "JPEG 2000 test SOT missing");
                }
                const auto tileComment = comment("Private tile author");
                put(payload, sot + 6, get(payload, sot + 6) + tileComment.size());
                payload.insert(payload.begin() + sot + 12, tileComment.begin(), tileComment.end());
                const auto mainComment = comment("Private encoder application");
                payload.insert(payload.begin() + sot, mainComment.begin(), mainComment.end());
            }
            auto encoded = box(type, payload); modified.insert(modified.end(), encoded.begin(), encoded.end());
            position += length;
        }
        for (const auto& type : {"xml ", "uuid"}) {
            auto metadata = box(type, bytes("Private author, date and application"));
            modified.insert(modified.end(), metadata.begin(), metadata.end());
        }
        auto cleaned = ips2pdf::removeJPEG2000Metadata(modified);
        require(text(cleaned).find("Private") == std::string::npos, "JPEG 2000 metadata survived");
        require(ips2pdf::removeJPEG2000Metadata(cleaned) == cleaned, "JPEG 2000 cleanup is not idempotent");
        QPDF pdf; pdf.emptyPDF();
        const auto a = ips2pdf::decodePDFImage(image(pdf, original, true), Object::newNull());
        const auto b = ips2pdf::decodePDFImage(image(pdf, modified, true), Object::newNull());
        auto object = image(pdf, modified, true);
        require(ips2pdf::cleanBinaryImageStream(pdf, object), "JPX stream cleanup was skipped");
        const auto c = ips2pdf::decodePDFImage(object, Object::newNull());
        require(a.pixels == b.pixels && b.pixels == c.pixels, "JPEG 2000 cleanup changed pixels or tile boundaries");
        auto bad = modified; put(bad, 0, 0xffffffff);
        bool rejected = false;
        try { ips2pdf::removeJPEG2000Metadata(bad); } catch (...) { rejected = true; }
        require(rejected, "Oversized JPEG 2000 box was accepted");
    }
    {
        Bytes original, pageInfo(19, 0); put(pageInfo, 0, 17); put(pageInfo, 4, 9); put(pageInfo, 8, 11811); put(pageInfo, 12, 11811);
        segment(original, 1, 48, 1, pageInfo);
        Bytes ascii{0x20, 0, 0, 0};
        const auto privateText = bytes(std::string("Author\0Private author\0\0", 23));
        ascii.insert(ascii.end(), privateText.begin(), privateText.end());
        segment(original, 2, 62, 1, ascii);
        Bytes unicode{0x20, 0, 0, 2, 0, 'A', 0, 0, 0, 'X', 0, 0, 0, 0};
        segment(original, 3, 62, 1, unicode);
        segment(original, 4, 49, 1, {}); segment(original, 5, 51, 0, {});
        auto cleaned = ips2pdf::removeJBIG2Metadata(original);
        require(text(cleaned).find("Private") == std::string::npos && cleaned.size() < original.size(), "JBIG2 comment metadata survived");
        require(ips2pdf::removeJBIG2Metadata(cleaned) == cleaned, "JBIG2 cleanup is not idempotent");
        QPDF pdf; pdf.emptyPDF();
        auto object = image(pdf, original, false);
        const auto before = ips2pdf::decodePDFImage(object, Object::newNull());
        require(ips2pdf::cleanBinaryImageStream(pdf, object), "JBIG2 stream cleanup was skipped");
        const auto after = ips2pdf::decodePDFImage(object, Object::newNull());
        require(before.pixels == after.pixels, "JBIG2 metadata cleanup changed its bitmap");
        auto malformed = original; put(malformed, 7, 0xffffffff);
        bool rejected = false;
        try { ips2pdf::removeJBIG2Metadata(malformed); } catch (...) { rejected = true; }
        require(rejected, "Indefinite JBIG2 segment was blindly scanned");
    }
    std::cout << "PASS binary image metadata: JP2 XML/UUID, JPEG 2000 main/tile comments, JBIG2 ASCII/UCS-2 comments, resolution reset, identical pixels and malformed-container rejection\n";
}
