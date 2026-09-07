#include "PDFSignatureFontAnonymizer.h"
#include "PDFProcessingControl.h"

#include <qpdf/QPDFObjectHandle.hh>
#include <algorithm>
#include <array>
#include <cstdint>
#include <limits>
#include <span>
#include <string>
#include <string_view>
#include <vector>
#include <zlib.h>

namespace ips2pdf {
namespace {
using Object = QPDFObjectHandle;

constexpr std::string_view originalPostScriptName = "AppleGaramond-Book";
constexpr std::string_view anonymousPostScriptName = "SignatureFont-Book";
constexpr std::string_view originalFullName = "Apple Garamond Book";
constexpr std::string_view anonymousFullName = "Signature Font Book";
constexpr std::string_view originalFamilyName = "Apple Garamond";
constexpr std::string_view anonymousFamilyName = "Signature Font";
constexpr size_t maximumCFFBytes = 1024 * 1024;

static_assert(originalPostScriptName.size() == anonymousPostScriptName.size());
static_assert(originalFullName.size() == anonymousFullName.size());
static_assert(originalFamilyName.size() == anonymousFamilyName.size());

struct Range {
    size_t begin = 0;
    size_t end = 0;
    size_t size() const { return end - begin; }
};

bool add(size_t left, size_t right, size_t& result) {
    if (right > std::numeric_limits<size_t>::max() - left) return false;
    result = left + right;
    return true;
}

bool readUnsigned(std::span<const uint8_t> bytes, size_t offset, size_t count, uint32_t& value) {
    if (count == 0 || count > 4 || offset > bytes.size() || count > bytes.size() - offset) return false;
    value = 0;
    for (size_t index = 0; index < count; ++index) value = (value << 8) | bytes[offset + index];
    return true;
}

bool readIndex(std::span<const uint8_t> bytes, size_t& offset, size_t maximumCount,
               std::vector<Range>& entries) {
    uint32_t count = 0;
    if (!readUnsigned(bytes, offset, 2, count) || count > maximumCount) return false;
    offset += 2;
    entries.clear();
    if (count == 0) return true;
    if (offset >= bytes.size()) return false;
    const size_t offsetSize = bytes[offset++];
    if (offsetSize == 0 || offsetSize > 4) return false;
    size_t tableBytes = 0;
    if (!add(static_cast<size_t>(count), 1, tableBytes) ||
        tableBytes > std::numeric_limits<size_t>::max() / offsetSize) return false;
    tableBytes *= offsetSize;
    if (offset > bytes.size() || tableBytes > bytes.size() - offset) return false;
    std::vector<uint32_t> offsets;
    offsets.reserve(static_cast<size_t>(count) + 1);
    for (uint32_t index = 0; index <= count; ++index) {
        uint32_t value = 0;
        if (!readUnsigned(bytes, offset + static_cast<size_t>(index) * offsetSize, offsetSize, value)) return false;
        if (value == 0 || (!offsets.empty() && value < offsets.back())) return false;
        offsets.push_back(value);
    }
    if (offsets.front() != 1) return false;
    const size_t data = offset + tableBytes;
    const size_t payload = static_cast<size_t>(offsets.back() - 1);
    if (data > bytes.size() || payload > bytes.size() - data) return false;
    entries.reserve(count);
    for (uint32_t index = 0; index < count; ++index) {
        entries.push_back({data + offsets[index] - 1, data + offsets[index + 1] - 1});
    }
    offset = data + payload;
    return true;
}

bool equals(std::span<const uint8_t> bytes, Range range, std::string_view value) {
    return range.size() == value.size() &&
        std::equal(bytes.begin() + static_cast<std::ptrdiff_t>(range.begin),
                   bytes.begin() + static_cast<std::ptrdiff_t>(range.end), value.begin());
}

struct TopDictionary {
    int64_t fullNameSID = -1;
    int64_t familyNameSID = -1;
    int64_t charsetOffset = -1;
    int64_t charStringsOffset = -1;
};

bool readInteger(std::span<const uint8_t> bytes, size_t& offset, int64_t& value) {
    if (offset >= bytes.size()) return false;
    const uint8_t first = bytes[offset++];
    if (first >= 32 && first <= 246) { value = static_cast<int64_t>(first) - 139; return true; }
    if (first >= 247 && first <= 250) {
        if (offset >= bytes.size()) return false;
        value = (static_cast<int64_t>(first) - 247) * 256 + bytes[offset++] + 108;
        return true;
    }
    if (first >= 251 && first <= 254) {
        if (offset >= bytes.size()) return false;
        value = -(static_cast<int64_t>(first) - 251) * 256 - bytes[offset++] - 108;
        return true;
    }
    if (first == 28) {
        uint32_t encoded = 0;
        if (!readUnsigned(bytes, offset, 2, encoded)) return false;
        offset += 2;
        value = static_cast<int16_t>(encoded);
        return true;
    }
    if (first == 29) {
        uint32_t encoded = 0;
        if (!readUnsigned(bytes, offset, 4, encoded)) return false;
        offset += 4;
        value = static_cast<int32_t>(encoded);
        return true;
    }
    --offset;
    return false;
}

bool skipReal(std::span<const uint8_t> bytes, size_t& offset) {
    while (offset < bytes.size()) {
        const uint8_t value = bytes[offset++];
        if ((value >> 4) == 15 || (value & 15) == 15) return true;
    }
    return false;
}

bool readTopDictionary(std::span<const uint8_t> bytes, Range range, TopDictionary& result) {
    std::vector<int64_t> operands;
    size_t offset = range.begin;
    while (offset < range.end) {
        const uint8_t byte = bytes[offset];
        int64_t value = 0;
        if (readInteger(bytes.first(range.end), offset, value)) {
            operands.push_back(value);
            if (operands.size() > 48) return false;
            continue;
        }
        ++offset;
        if (byte == 30) {
            if (!skipReal(bytes.first(range.end), offset)) return false;
            operands.push_back(0);
            continue;
        }
        if (byte == 255) {
            if (offset > range.end || 4 > range.end - offset) return false;
            offset += 4;
            operands.push_back(0);
            continue;
        }
        if (byte > 21) return false;
        int operation = byte;
        if (byte == 12) {
            if (offset >= range.end) return false;
            operation = 0x0c00 | bytes[offset++];
        }
        if (operands.size() == 1) {
            if (operation == 2) result.fullNameSID = operands.front();
            if (operation == 3) result.familyNameSID = operands.front();
            if (operation == 15) result.charsetOffset = operands.front();
            if (operation == 17) result.charStringsOffset = operands.front();
        }
        operands.clear();
    }
    return operands.empty();
}

bool subsetPDFName(const std::string& name, std::string& prefix) {
    if (name.size() != 1 + 6 + 1 + originalPostScriptName.size() || name.front() != '/' || name[7] != '+')
        return false;
    prefix = name.substr(1, 6);
    if (!std::all_of(prefix.begin(), prefix.end(), [](unsigned char value) { return value >= 'A' && value <= 'Z'; }))
        return false;
    return std::string_view(name).substr(8) == originalPostScriptName;
}

bool signatureWidths(Object font) {
    auto first = font.getKey("/FirstChar"), last = font.getKey("/LastChar"), widths = font.getKey("/Widths");
    if (!first.isInteger() || first.getIntValue() != 32 || !last.isInteger() || last.getIntValue() != 226 ||
        !widths.isArray() || widths.getArrayNItems() != 195) return false;
    for (int index = 1; index + 1 < widths.getArrayNItems(); ++index) {
        auto width = widths.getArrayItem(index);
        if (!width.isNumber() || width.getNumericValue() != 0) return false;
    }
    auto space = widths.getArrayItem(0), signature = widths.getArrayItem(widths.getArrayNItems() - 1);
    return space.isNumber() && signature.isNumber() && space.getNumericValue() > 0 &&
        signature.getNumericValue() > 1000;
}

bool inflateCFF(std::span<const uint8_t> input, std::string& output) {
    z_stream stream{};
    if (inflateInit(&stream) != Z_OK) return false;
    stream.next_in = const_cast<Bytef*>(reinterpret_cast<const Bytef*>(input.data()));
    stream.avail_in = static_cast<uInt>(input.size());
    std::array<uint8_t, 8192> buffer{};
    int status = Z_OK;
    while (status == Z_OK) {
        stream.next_out = buffer.data();
        stream.avail_out = static_cast<uInt>(buffer.size());
        status = inflate(&stream, Z_NO_FLUSH);
        const size_t produced = buffer.size() - stream.avail_out;
        if (produced > maximumCFFBytes - output.size()) { inflateEnd(&stream); return false; }
        output.append(reinterpret_cast<const char*>(buffer.data()), produced);
    }
    const bool complete = status == Z_STREAM_END && stream.avail_in == 0;
    inflateEnd(&stream);
    return complete;
}

bool replaceCFFNames(std::string& data, const std::string& originalName, const std::string& anonymousName) {
    auto bytes = std::span<const uint8_t>(reinterpret_cast<const uint8_t*>(data.data()), data.size());
    if (bytes.size() < 4 || bytes[0] != 1 || bytes[2] < 4 || bytes[2] > bytes.size()) return false;
    size_t offset = bytes[2];
    std::vector<Range> names, dictionaries, strings, subroutines, charStrings;
    if (!readIndex(bytes, offset, 1, names) || names.size() != 1 || !equals(bytes, names.front(), originalName) ||
        !readIndex(bytes, offset, 1, dictionaries) || dictionaries.size() != 1 ||
        !readIndex(bytes, offset, 64, strings) || !readIndex(bytes, offset, 65535, subroutines)) return false;
    TopDictionary top;
    if (!readTopDictionary(bytes, dictionaries.front(), top) || top.fullNameSID < 391 || top.familyNameSID < 391 ||
        top.charsetOffset < 0 || top.charStringsOffset < 0) return false;
    const size_t fullIndex = static_cast<size_t>(top.fullNameSID - 391);
    const size_t familyIndex = static_cast<size_t>(top.familyNameSID - 391);
    if (fullIndex >= strings.size() || familyIndex >= strings.size() ||
        !equals(bytes, strings[fullIndex], originalFullName) ||
        !equals(bytes, strings[familyIndex], originalFamilyName)) return false;
    size_t charStringsOffset = static_cast<size_t>(top.charStringsOffset);
    if (!readIndex(bytes, charStringsOffset, 3, charStrings) || charStrings.size() != 3 || charStrings[2].size() < 64)
        return false;
    const size_t charsetOffset = static_cast<size_t>(top.charsetOffset);
    uint32_t firstSID = 0, secondSID = 0;
    if (charsetOffset > bytes.size() || bytes.size() - charsetOffset < 5 || bytes[charsetOffset] != 0 ||
        !readUnsigned(bytes, charsetOffset + 1, 2, firstSID) ||
        !readUnsigned(bytes, charsetOffset + 3, 2, secondSID) || firstSID != 1 || secondSID != 117) return false;

    std::copy(anonymousName.begin(), anonymousName.end(), data.begin() + static_cast<std::ptrdiff_t>(names.front().begin));
    std::copy(anonymousFullName.begin(), anonymousFullName.end(), data.begin() + static_cast<std::ptrdiff_t>(strings[fullIndex].begin));
    std::copy(anonymousFamilyName.begin(), anonymousFamilyName.end(), data.begin() + static_cast<std::ptrdiff_t>(strings[familyIndex].begin));
    return data.find(originalPostScriptName) == std::string::npos &&
        data.find(originalFullName) == std::string::npos && data.find(originalFamilyName) == std::string::npos;
}

std::string flate(std::string_view bytes) {
    uLongf size = compressBound(bytes.size());
    std::string result(size, '\0');
    if (compress2(reinterpret_cast<Bytef*>(result.data()), &size,
                  reinterpret_cast<const Bytef*>(bytes.data()), bytes.size(), Z_BEST_COMPRESSION) != Z_OK)
        return {};
    result.resize(size);
    return result;
}
} // namespace

bool anonymizeSignatureFont(Object font) {
    checkPDFProcessing();
    if (!font.isDictionary() || !font.getKey("/Type").isNameAndEquals("/Font") ||
        !font.getKey("/Subtype").isNameAndEquals("/Type1") ||
        !font.getKey("/Encoding").isNameAndEquals("/MacRomanEncoding") || !signatureWidths(font)) return false;
    auto baseFont = font.getKey("/BaseFont");
    if (!baseFont.isName()) return false;
    std::string prefix;
    if (!subsetPDFName(baseFont.getName(), prefix)) return false;
    const std::string originalName = prefix + "+" + std::string(originalPostScriptName);
    const std::string anonymousName = prefix + "+" + std::string(anonymousPostScriptName);
    auto descriptor = font.getKey("/FontDescriptor");
    if (!descriptor.isDictionary() || !descriptor.getKey("/FontName").isNameAndEquals("/" + originalName)) return false;
    auto stream = descriptor.getKey("/FontFile3");
    if (!stream.isStream() || !stream.getDict().getKey("/Subtype").isNameAndEquals("/Type1C") ||
        !stream.getDict().getKey("/Filter").isNameAndEquals("/FlateDecode") ||
        !stream.getDict().getKey("/DecodeParms").isNull()) return false;
    auto compressed = stream.getRawStreamData();
    if (compressed->getSize() == 0 || compressed->getSize() > maximumCFFBytes ||
        compressed->getSize() > std::numeric_limits<uInt>::max()) return false;
    std::string cff;
    if (!inflateCFF({compressed->getBuffer(), compressed->getSize()}, cff) ||
        !replaceCFFNames(cff, originalName, anonymousName)) return false;
    auto replacement = flate(cff);
    if (replacement.empty()) return false;

    font.replaceKey("/BaseFont", Object::newName("/" + anonymousName));
    descriptor.replaceKey("/FontName", Object::newName("/" + anonymousName));
    stream.replaceStreamData(replacement, Object::newName("/FlateDecode"), Object::newNull());
    stream.setFilterOnWrite(false);
    return true;
}

} // namespace ips2pdf
