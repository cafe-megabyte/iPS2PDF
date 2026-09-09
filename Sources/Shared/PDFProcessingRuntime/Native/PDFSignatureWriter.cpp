#include "PDFSignatureWriter.h"
#include "PDFProcessingControl.h"

#include <qpdf/QPDFPageDocumentHelper.hh>
#include <qpdf/QUtil.hh>
#include <cmath>
#include <cstdint>
#include <fcntl.h>
#include <map>
#include <stdexcept>
#include <string_view>
#include <sys/stat.h>
#include <unistd.h>

namespace ips2pdf {
namespace {
using Object = QPDFObjectHandle;
constexpr std::string_view postScriptName = "AAAAAC+SignatureFont-Book";
constexpr std::size_t maximumFontBytes = 1024 * 1024;

std::uint16_t unsigned16(std::string_view bytes, std::size_t offset) {
    if (offset > bytes.size() || 2 > bytes.size() - offset) throw std::runtime_error("Invalid signature font");
    return (static_cast<std::uint16_t>(static_cast<unsigned char>(bytes[offset])) << 8) |
        static_cast<unsigned char>(bytes[offset + 1]);
}

std::int16_t signed16(std::string_view bytes, std::size_t offset) {
    return static_cast<std::int16_t>(unsigned16(bytes, offset));
}

std::uint32_t unsigned32(std::string_view bytes, std::size_t offset) {
    if (offset > bytes.size() || 4 > bytes.size() - offset) throw std::runtime_error("Invalid signature font");
    return (static_cast<std::uint32_t>(static_cast<unsigned char>(bytes[offset])) << 24) |
        (static_cast<std::uint32_t>(static_cast<unsigned char>(bytes[offset + 1])) << 16) |
        (static_cast<std::uint32_t>(static_cast<unsigned char>(bytes[offset + 2])) << 8) |
        static_cast<unsigned char>(bytes[offset + 3]);
}

std::string readFont(const std::filesystem::path& path) {
    const int descriptor = ::open(path.c_str(), O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (descriptor < 0) throw std::runtime_error("Could not open the private signature font");
    try {
        struct stat status{};
        if (fstat(descriptor, &status) || !S_ISREG(status.st_mode) || status.st_size <= 0 ||
            static_cast<std::uintmax_t>(status.st_size) > maximumFontBytes)
            throw std::runtime_error("Invalid signature font file");
        std::string result(static_cast<std::size_t>(status.st_size), '\0');
        std::size_t offset = 0;
        while (offset < result.size()) {
            checkPDFProcessing();
            const auto count = ::read(descriptor, result.data() + offset, result.size() - offset);
            if (count <= 0) throw std::runtime_error("Could not read the signature font");
            offset += static_cast<std::size_t>(count);
        }
        close(descriptor);
        return result;
    } catch (...) {
        close(descriptor);
        throw;
    }
}

struct Table { std::size_t offset = 0; std::size_t length = 0; };

std::map<std::string, Table> fontTables(std::string_view bytes) {
    if (bytes.size() < 12 || bytes.substr(0, 4) != "OTTO") throw std::runtime_error("A CFF OpenType signature font is required");
    const auto count = unsigned16(bytes, 4);
    if (count == 0 || count > 64 || 12 + static_cast<std::size_t>(count) * 16 > bytes.size())
        throw std::runtime_error("Invalid signature font table directory");
    std::map<std::string, Table> result;
    for (std::uint16_t index = 0; index < count; ++index) {
        const auto record = 12 + static_cast<std::size_t>(index) * 16;
        std::string tag(bytes.substr(record, 4));
        const auto offset = static_cast<std::size_t>(unsigned32(bytes, record + 8));
        const auto length = static_cast<std::size_t>(unsigned32(bytes, record + 12));
        if (offset > bytes.size() || length > bytes.size() - offset || !result.emplace(tag, Table{offset, length}).second)
            throw std::runtime_error("Invalid signature font table");
    }
    return result;
}

Table requiredTable(const std::map<std::string, Table>& tables, std::string_view name, std::size_t minimum) {
    const auto found = tables.find(std::string(name));
    if (found == tables.end() || found->second.length < minimum) throw std::runtime_error("Signature font table is missing");
    return found->second;
}

std::string cffName(std::string_view cff) {
    if (cff.size() < 7 || static_cast<unsigned char>(cff[0]) != 1) throw std::runtime_error("Invalid signature CFF program");
    std::size_t offset = static_cast<unsigned char>(cff[2]);
    const auto count = unsigned16(cff, offset);
    offset += 2;
    if (count != 1 || offset >= cff.size()) throw std::runtime_error("Invalid signature CFF name index");
    const auto offSize = static_cast<unsigned char>(cff[offset++]);
    if (offSize == 0 || offSize > 4 || offset + 2 * offSize > cff.size()) throw std::runtime_error("Invalid signature CFF offset");
    auto readOffset = [&](std::size_t position) {
        std::size_t value = 0;
        for (std::size_t index = 0; index < offSize; ++index)
            value = (value << 8) | static_cast<unsigned char>(cff[position + index]);
        return value;
    };
    const auto first = readOffset(offset), last = readOffset(offset + offSize);
    const auto data = offset + 2 * offSize;
    if (first != 1 || last <= first || data > cff.size() || last - 1 > cff.size() - data)
        throw std::runtime_error("Invalid signature CFF name");
    return std::string(cff.substr(data + first - 1, last - first));
}

struct SignatureFont {
    std::string cff;
    double width = 1000;
    double ascent = 1000;
    double descent = 0;
    double xMin = 0;
    double yMin = 0;
    double xMax = 1000;
    double yMax = 1000;
};

SignatureFont parseFont(const std::filesystem::path& path) {
    const auto bytes = readFont(path);
    const auto tables = fontTables(bytes);
    const auto cffTable = requiredTable(tables, "CFF ", 8);
    const auto head = requiredTable(tables, "head", 54);
    const auto hhea = requiredTable(tables, "hhea", 36);
    const auto maxp = requiredTable(tables, "maxp", 6);
    const auto units = unsigned16(bytes, head.offset + 18);
    const auto glyphs = unsigned16(bytes, maxp.offset + 4);
    if (units < 16 || units > 16384 || glyphs < 2 || glyphs > 3)
        throw std::runtime_error("Unsupported signature font metrics");
    SignatureFont result;
    result.cff = bytes.substr(cffTable.offset, cffTable.length);
    if (cffName(result.cff) != postScriptName) throw std::runtime_error("Unexpected signature font identity");
    const double scale = 1000.0 / units;
    result.width = unsigned16(bytes, hhea.offset + 10) * scale;
    result.ascent = signed16(bytes, hhea.offset + 4) * scale;
    result.descent = signed16(bytes, hhea.offset + 6) * scale;
    result.xMin = signed16(bytes, head.offset + 36) * scale;
    result.yMin = signed16(bytes, head.offset + 38) * scale;
    result.xMax = signed16(bytes, head.offset + 40) * scale;
    result.yMax = signed16(bytes, head.offset + 42) * scale;
    if (!(result.width > 0) || !(result.xMax > result.xMin) || !(result.yMax > result.yMin))
        throw std::runtime_error("Invalid signature font geometry");
    return result;
}

Object real(double value) { return Object::newReal(value, 5, true); }

Object embeddedFont(QPDF& pdf, const SignatureFont& source) {
    auto program = pdf.newStream(source.cff);
    program.getDict().replaceKey("/Subtype", Object::newName("/Type1C"));
    program.getDict().replaceKey("/Length1", Object::newInteger(static_cast<long long>(source.cff.size())));
    auto descriptor = Object::newDictionary({
        {"/Type", Object::newName("/FontDescriptor")},
        {"/FontName", Object::newName("/" + std::string(postScriptName))},
        {"/Flags", Object::newInteger(32)},
        {"/FontBBox", Object::newArray({real(source.xMin), real(source.yMin), real(source.xMax), real(source.yMax)})},
        {"/ItalicAngle", Object::newInteger(0)},
        {"/Ascent", real(source.ascent)},
        {"/Descent", real(source.descent)},
        {"/CapHeight", real(source.yMax)},
        {"/StemV", Object::newInteger(80)},
        {"/FontFile3", program},
    });
    auto unicode = pdf.newStream(
        "/CIDInit /ProcSet findresource begin\n12 dict begin\nbegincmap\n"
        "/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def\n"
        "/CMapName /IPS2PDFSignatureToUnicode def\n/CMapType 2 def\n"
        "1 begincodespacerange\n<E2> <E2>\nendcodespacerange\n"
        "1 beginbfchar\n<E2> <201A>\nendbfchar\n"
        "endcmap\nCMapName currentdict /CMap defineresource pop\nend\nend\n");
    auto encoding = Object::newDictionary({
        {"/Type", Object::newName("/Encoding")},
        {"/BaseEncoding", Object::newName("/MacRomanEncoding")},
        {"/Differences", Object::newArray({Object::newInteger(226), Object::newName("/quotesinglbase")})},
    });
    auto font = Object::newDictionary({
        {"/Type", Object::newName("/Font")},
        {"/Subtype", Object::newName("/Type1")},
        {"/BaseFont", Object::newName("/" + std::string(postScriptName))},
        {"/FirstChar", Object::newInteger(226)},
        {"/LastChar", Object::newInteger(226)},
        {"/Widths", Object::newArray({real(source.width)})},
        {"/Encoding", encoding},
        {"/FontDescriptor", pdf.makeIndirectObject(descriptor)},
        {"/ToUnicode", unicode},
    });
    return pdf.makeIndirectObject(font);
}

std::string number(double value) {
    if (!std::isfinite(value)) throw std::runtime_error("Invalid signature placement");
    return QUtil::double_to_string(value, 5, true);
}
} // namespace

PDFStructuralWriteResult addPDFSignatures(const std::filesystem::path& input,
                                          const std::filesystem::path& output,
                                          const std::filesystem::path& font,
                                          const std::string& password,
                                          const std::vector<PDFSignaturePlacement>& placements) {
    if (input == output || placements.empty() || placements.size() > 10000)
        throw std::runtime_error("Invalid signature request");
    auto pdf = openPDFDocument(input, password);
    auto pages = QPDFPageDocumentHelper(*pdf).getAllPages();
    std::map<int, std::vector<PDFSignaturePlacement>> byPage;
    for (const auto& placement : placements) {
        checkPDFProcessing();
        if (placement.pageIndex < 0 || static_cast<std::size_t>(placement.pageIndex) >= pages.size() ||
            !std::isfinite(placement.x) || !std::isfinite(placement.y) || !std::isfinite(placement.fontSize) ||
            placement.fontSize < 5 || placement.fontSize > 500)
            throw std::runtime_error("Invalid signature placement");
        byPage[placement.pageIndex].push_back(placement);
    }
    const auto source = parseFont(font);
    const auto sharedFont = embeddedFont(*pdf, source);
    for (const auto& [pageIndex, pagePlacements] : byPage) {
        auto page = pages[static_cast<std::size_t>(pageIndex)];
        auto resources = page.getAttribute("/Resources", true);
        resources = resources.isDictionary() ? resources.shallowCopy() : Object::newDictionary();
        // Never mutate an inherited resource dictionary shared by unrelated
        // pages. Each touched page gets its own dictionary and font alias.
        page.getObjectHandle().replaceKey("/Resources", resources);
        int suffix = 1;
        const auto name = resources.getUniqueResourceName("/IPS2PDFSignatureFont", suffix);
        auto fonts = resources.getKey("/Font");
        fonts = fonts.isDictionary() ? fonts.shallowCopy() : Object::newDictionary();
        fonts.replaceKey(name, sharedFont);
        resources.replaceKey("/Font", fonts);
        std::string content = "q\n";
        for (const auto& placement : pagePlacements) {
            content += "BT " + name + " " + number(placement.fontSize) + " Tf 1 0 0 1 " +
                number(placement.x) + " " + number(placement.y) + " Tm <E2> Tj ET\n";
        }
        content += "Q\n";
        page.addPageContents(pdf->newStream(content), false);
    }
    PDFStructuralWriteResult result;
    result.protectionRemoved = !canPreservePDFEncryption(*pdf);
    result.sanitization = invalidatePDFDigitalSignatures(*pdf);
    result.outputBytes = writePDFDocument(*pdf, output, !result.protectionRemoved, false);
    return result;
}

} // namespace ips2pdf
