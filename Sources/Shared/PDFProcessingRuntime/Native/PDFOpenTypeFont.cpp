#include "PDFOpenTypeFont.h"
#include "PDFProcessingControl.h"

#include <ft2build.h>
#include FT_FREETYPE_H
#include FT_TYPE1_TABLES_H

#include <CoreGraphics/CoreGraphics.h>
#include <algorithm>
#include <array>
#include <cmath>
#include <limits>
#include <map>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>

namespace ips2pdf {
namespace {

using Bytes = std::vector<uint8_t>;

struct CharacterMapping {
    uint32_t character;
    uint16_t glyph;

    bool operator==(const CharacterMapping&) const = default;
};

struct FontMetrics {
    uint16_t unitsPerEm;
    int16_t xMin;
    int16_t yMin;
    int16_t xMax;
    int16_t yMax;
    int16_t ascender;
    int16_t descender;
    int16_t lineGap;
    uint16_t advanceWidthMax;
    int16_t minLeftSideBearing;
    int16_t minRightSideBearing;
    int16_t xMaxExtent;
    int16_t averageWidth;
    int16_t xHeight;
    int16_t capHeight;
    uint16_t fsType;
    bool bold;
    bool italic;
    bool fixedPitch;
    int32_t italicAngle;
    int16_t underlinePosition;
    int16_t underlineThickness;
    std::vector<uint16_t> advances;
    std::vector<int16_t> leftSideBearings;
    std::vector<CharacterMapping> mappings;
    std::string familyName;
    std::string styleName;
    std::string fullName;
    std::string postScriptName;
};

struct Table {
    std::array<char, 4> tag;
    Bytes data;
    uint32_t checksum = 0;
    uint32_t offset = 0;
};

uint16_t unsigned16(long value) {
    return static_cast<uint16_t>(std::clamp<long>(value, 0, std::numeric_limits<uint16_t>::max()));
}

int16_t signed16(long value) {
    return static_cast<int16_t>(std::clamp<long>(value, std::numeric_limits<int16_t>::min(),
                                                std::numeric_limits<int16_t>::max()));
}

void append16(Bytes& result, uint16_t value) {
    result.push_back(static_cast<uint8_t>(value >> 8));
    result.push_back(static_cast<uint8_t>(value));
}

void appendSigned16(Bytes& result, int16_t value) {
    append16(result, static_cast<uint16_t>(value));
}

void append32(Bytes& result, uint32_t value) {
    for (int shift : {24, 16, 8, 0}) result.push_back(static_cast<uint8_t>(value >> shift));
}

void replace32(Bytes& result, size_t offset, uint32_t value) {
    if (offset + 4 > result.size()) throw std::runtime_error("Invalid OpenType table offset");
    for (size_t index = 0; index < 4; ++index)
        result[offset + index] = static_cast<uint8_t>(value >> (24 - 8 * index));
}

uint32_t checksum(std::span<const uint8_t> bytes) {
    uint32_t result = 0;
    for (size_t offset = 0; offset < bytes.size(); offset += 4) {
        uint32_t word = 0;
        for (size_t index = 0; index < 4; ++index) {
            word <<= 8;
            if (offset + index < bytes.size()) word |= bytes[offset + index];
        }
        result += word;
    }
    return result;
}

std::string validName(const char* value, std::string_view fallback) {
    if (!value || !*value) return std::string(fallback);
    std::string result(value);
    result.erase(std::remove_if(result.begin(), result.end(), [](unsigned char byte) {
        return byte < 0x20 || byte == 0x7f;
    }), result.end());
    return result.empty() ? std::string(fallback) : result;
}

std::string postScriptName(const char* value, std::string_view family, std::string_view style) {
    std::string result = value && *value ? value : std::string(family) + "-" + std::string(style);
    result.erase(std::remove_if(result.begin(), result.end(), [](unsigned char byte) {
        return byte <= 0x20 || byte >= 0x7f || std::string_view("[](){}<>/%").find(static_cast<char>(byte)) != std::string_view::npos;
    }), result.end());
    if (result.empty()) result = "EmbeddedFont";
    return result.substr(0, 63);
}

std::vector<uint16_t> utf16(std::string_view value) {
    std::vector<uint16_t> result;
    for (size_t index = 0; index < value.size();) {
        const uint8_t first = static_cast<uint8_t>(value[index]);
        uint32_t scalar = 0xfffd;
        size_t length = 1;
        if (first < 0x80) {
            scalar = first;
        } else if ((first & 0xe0) == 0xc0 && index + 1 < value.size()) {
            scalar = first & 0x1f;
            length = 2;
        } else if ((first & 0xf0) == 0xe0 && index + 2 < value.size()) {
            scalar = first & 0x0f;
            length = 3;
        } else if ((first & 0xf8) == 0xf0 && index + 3 < value.size()) {
            scalar = first & 0x07;
            length = 4;
        }
        bool valid = length > 1;
        for (size_t byteIndex = 1; byteIndex < length; ++byteIndex) {
            const uint8_t continuation = static_cast<uint8_t>(value[index + byteIndex]);
            if ((continuation & 0xc0) != 0x80) { valid = false; break; }
            scalar = (scalar << 6) | (continuation & 0x3f);
        }
        if (length == 1 && first < 0x80) valid = true;
        if (!valid || (length == 2 && scalar < 0x80) || (length == 3 && scalar < 0x800) ||
            (length == 4 && scalar < 0x10000) || scalar > 0x10ffff ||
            (scalar >= 0xd800 && scalar <= 0xdfff)) {
            scalar = 0xfffd;
            length = 1;
        }
        if (scalar <= 0xffff) {
            result.push_back(static_cast<uint16_t>(scalar));
        } else {
            scalar -= 0x10000;
            result.push_back(static_cast<uint16_t>(0xd800 + (scalar >> 10)));
            result.push_back(static_cast<uint16_t>(0xdc00 + (scalar & 0x3ff)));
        }
        index += length;
    }
    return result;
}

std::vector<CharacterMapping> mappings(FT_Face face) {
    std::vector<CharacterMapping> result;
    if (FT_Select_Charmap(face, FT_ENCODING_UNICODE)) return result;
    FT_UInt glyph = 0;
    FT_ULong character = FT_Get_First_Char(face, &glyph);
    while (glyph != 0) {
        checkPDFProcessing();
        if (character <= 0x10ffff && !(character >= 0xd800 && character <= 0xdfff) &&
            glyph < static_cast<FT_UInt>(face->num_glyphs))
            result.push_back({static_cast<uint32_t>(character), static_cast<uint16_t>(glyph)});
        character = FT_Get_Next_Char(face, character, &glyph);
        if (result.size() > 1'000'000) throw std::runtime_error("Embedded CFF character map is too large");
    }
    return result;
}

int16_t glyphHeight(FT_Face face, uint32_t character) {
    const FT_UInt glyph = FT_Get_Char_Index(face, character);
    if (!glyph || FT_Load_Glyph(face, glyph, FT_LOAD_NO_SCALE | FT_LOAD_NO_HINTING | FT_LOAD_NO_BITMAP | FT_LOAD_IGNORE_TRANSFORM))
        return 0;
    return signed16(face->glyph->metrics.horiBearingY);
}

FontMetrics readMetrics(FT_Face face) {
    if (face->num_glyphs <= 0 || face->num_glyphs > std::numeric_limits<uint16_t>::max() ||
        face->units_per_EM < 16 || face->units_per_EM > 16384)
        throw std::runtime_error("Embedded CFF metrics cannot be represented in OpenType");

    FontMetrics result{};
    result.unitsPerEm = static_cast<uint16_t>(face->units_per_EM);
    result.xMin = signed16(face->bbox.xMin);
    result.yMin = signed16(face->bbox.yMin);
    result.xMax = signed16(face->bbox.xMax);
    result.yMax = signed16(face->bbox.yMax);
    result.ascender = signed16(face->ascender);
    result.descender = signed16(face->descender);
    result.lineGap = signed16(face->height - face->ascender + face->descender);
    result.advanceWidthMax = 0;
    result.minLeftSideBearing = std::numeric_limits<int16_t>::max();
    result.minRightSideBearing = std::numeric_limits<int16_t>::max();
    result.xMaxExtent = std::numeric_limits<int16_t>::min();
    result.bold = (face->style_flags & FT_STYLE_FLAG_BOLD) != 0;
    result.italic = (face->style_flags & FT_STYLE_FLAG_ITALIC) != 0;
    result.fixedPitch = (face->face_flags & FT_FACE_FLAG_FIXED_WIDTH) != 0;
    result.fsType = static_cast<uint16_t>(FT_Get_FSType_Flags(face));
    result.underlinePosition = signed16(face->underline_position);
    result.underlineThickness = signed16(face->underline_thickness);
    result.familyName = validName(face->family_name, "Embedded Font");
    result.styleName = validName(face->style_name, result.bold ? "Bold" : (result.italic ? "Italic" : "Regular"));
    result.fullName = result.familyName + (result.styleName == "Regular" ? "" : " " + result.styleName);
    result.postScriptName = postScriptName(FT_Get_Postscript_Name(face), result.familyName, result.styleName);

    PS_FontInfoRec fontInfo{};
    if (!FT_Get_PS_Font_Info(face, &fontInfo)) {
        result.fullName = validName(fontInfo.full_name, result.fullName);
        result.italicAngle = static_cast<int32_t>(std::clamp<long>(
            fontInfo.italic_angle, std::numeric_limits<int32_t>::min(), std::numeric_limits<int32_t>::max()));
        result.fixedPitch = fontInfo.is_fixed_pitch;
        result.underlinePosition = fontInfo.underline_position;
        result.underlineThickness = signed16(fontInfo.underline_thickness);
    }

    long totalWidth = 0;
    long measuredGlyphs = 0;
    result.advances.reserve(static_cast<size_t>(face->num_glyphs));
    result.leftSideBearings.reserve(static_cast<size_t>(face->num_glyphs));
    for (FT_UInt glyph = 0; glyph < static_cast<FT_UInt>(face->num_glyphs); ++glyph) {
        checkPDFProcessing();
        if (FT_Load_Glyph(face, glyph, FT_LOAD_NO_SCALE | FT_LOAD_NO_HINTING | FT_LOAD_NO_BITMAP | FT_LOAD_IGNORE_TRANSFORM))
            throw std::runtime_error("Embedded CFF glyph metrics could not be read");
        const auto& metric = face->glyph->metrics;
        const uint16_t advance = unsigned16(metric.horiAdvance);
        const int16_t left = signed16(metric.horiBearingX);
        const int16_t right = signed16(static_cast<long>(advance) - left - metric.width);
        const int16_t extent = signed16(static_cast<long>(left) + metric.width);
        result.advances.push_back(advance);
        result.leftSideBearings.push_back(left);
        result.advanceWidthMax = std::max(result.advanceWidthMax, advance);
        result.minLeftSideBearing = std::min(result.minLeftSideBearing, left);
        result.minRightSideBearing = std::min(result.minRightSideBearing, right);
        result.xMaxExtent = std::max(result.xMaxExtent, extent);
        if (glyph != 0) { totalWidth += advance; ++measuredGlyphs; }
    }
    result.averageWidth = signed16(measuredGlyphs
        ? std::lround(static_cast<double>(totalWidth) / static_cast<double>(measuredGlyphs)) : 0);
    result.mappings = mappings(face);
    result.xHeight = glyphHeight(face, 'x');
    result.capHeight = glyphHeight(face, 'H');
    return result;
}

Bytes headTable(const FontMetrics& font) {
    Bytes result;
    append32(result, 0x00010000);
    append32(result, 0x00010000);
    append32(result, 0); // Filled after the complete sfnt has been assembled.
    append32(result, 0x5f0f3cf5);
    append16(result, 0);
    append16(result, font.unitsPerEm);
    for (int index = 0; index < 4; ++index) append32(result, 0); // Created and modified dates.
    appendSigned16(result, font.xMin);
    appendSigned16(result, font.yMin);
    appendSigned16(result, font.xMax);
    appendSigned16(result, font.yMax);
    append16(result, static_cast<uint16_t>((font.bold ? 1 : 0) | (font.italic ? 2 : 0)));
    append16(result, 3);
    appendSigned16(result, 2);
    appendSigned16(result, 0);
    appendSigned16(result, 0);
    return result;
}

Bytes horizontalHeaderTable(const FontMetrics& font) {
    Bytes result;
    append32(result, 0x00010000);
    appendSigned16(result, font.ascender);
    appendSigned16(result, font.descender);
    appendSigned16(result, font.lineGap);
    append16(result, font.advanceWidthMax);
    appendSigned16(result, font.minLeftSideBearing);
    appendSigned16(result, font.minRightSideBearing);
    appendSigned16(result, font.xMaxExtent);
    appendSigned16(result, 1);
    appendSigned16(result, 0);
    appendSigned16(result, 0);
    for (int index = 0; index < 4; ++index) appendSigned16(result, 0);
    appendSigned16(result, 0);
    append16(result, static_cast<uint16_t>(font.advances.size()));
    return result;
}

Bytes horizontalMetricsTable(const FontMetrics& font) {
    Bytes result;
    result.reserve(font.advances.size() * 4);
    for (size_t index = 0; index < font.advances.size(); ++index) {
        append16(result, font.advances[index]);
        appendSigned16(result, font.leftSideBearings[index]);
    }
    return result;
}

Bytes maximumProfileTable(size_t glyphCount) {
    Bytes result;
    append32(result, 0x00005000);
    append16(result, static_cast<uint16_t>(glyphCount));
    return result;
}

Bytes postTable(const FontMetrics& font) {
    Bytes result;
    append32(result, 0x00030000);
    append32(result, static_cast<uint32_t>(font.italicAngle));
    appendSigned16(result, font.underlinePosition);
    appendSigned16(result, font.underlineThickness);
    append32(result, font.fixedPitch ? 1 : 0);
    for (int index = 0; index < 4; ++index) append32(result, 0);
    return result;
}

Bytes namingTable(const FontMetrics& font) {
    const std::array<std::pair<uint16_t, std::string_view>, 4> names{{
        {1, font.familyName}, {2, font.styleName}, {4, font.fullName}, {6, font.postScriptName}
    }};
    Bytes strings;
    struct Record { uint16_t identifier; uint16_t length; uint16_t offset; };
    std::vector<Record> records;
    for (const auto& [identifier, value] : names) {
        const auto encoded = utf16(value);
        if (strings.size() + encoded.size() * 2 > std::numeric_limits<uint16_t>::max())
            throw std::runtime_error("Embedded CFF names are too large for OpenType");
        const uint16_t offset = static_cast<uint16_t>(strings.size());
        for (uint16_t codeUnit : encoded) append16(strings, codeUnit);
        records.push_back({identifier, static_cast<uint16_t>(encoded.size() * 2), offset});
    }
    Bytes result;
    append16(result, 0);
    append16(result, static_cast<uint16_t>(records.size()));
    append16(result, static_cast<uint16_t>(6 + records.size() * 12));
    for (const auto& record : records) {
        append16(result, 3);
        append16(result, 1);
        append16(result, 0x0409);
        append16(result, record.identifier);
        append16(result, record.length);
        append16(result, record.offset);
    }
    result.insert(result.end(), strings.begin(), strings.end());
    return result;
}

Bytes format12(const std::vector<CharacterMapping>& mappings) {
    struct Group { uint32_t first; uint32_t last; uint32_t glyph; };
    std::vector<Group> groups;
    for (const auto& mapping : mappings) {
        if (!groups.empty() && mapping.character == groups.back().last + 1 &&
            mapping.glyph == groups.back().glyph + (groups.back().last - groups.back().first) + 1) {
            groups.back().last = mapping.character;
        } else {
            groups.push_back({mapping.character, mapping.character, mapping.glyph});
        }
    }
    if (groups.size() > (std::numeric_limits<uint32_t>::max() - 16) / 12)
        throw std::runtime_error("Embedded CFF character map is too large for OpenType");
    Bytes result;
    append16(result, 12);
    append16(result, 0);
    append32(result, static_cast<uint32_t>(16 + groups.size() * 12));
    append32(result, 0);
    append32(result, static_cast<uint32_t>(groups.size()));
    for (const auto& group : groups) {
        append32(result, group.first);
        append32(result, group.last);
        append32(result, group.glyph);
    }
    return result;
}

Bytes format4(const std::vector<CharacterMapping>& mappings) {
    struct Segment { uint16_t first; uint16_t last; uint16_t delta; };
    std::vector<Segment> segments;
    for (const auto& mapping : mappings) {
        if (mapping.character >= 0xffff) continue;
        const uint16_t character = static_cast<uint16_t>(mapping.character);
        const uint16_t delta = static_cast<uint16_t>(mapping.glyph - character);
        if (!segments.empty() && character == static_cast<uint16_t>(segments.back().last + 1) &&
            delta == segments.back().delta) {
            segments.back().last = character;
        } else {
            segments.push_back({character, character, delta});
        }
    }
    segments.push_back({0xffff, 0xffff, 1});
    const size_t length = 16 + segments.size() * 8;
    if (length > std::numeric_limits<uint16_t>::max()) return {};
    uint16_t power = 1;
    uint16_t selector = 0;
    while (power * 2 <= segments.size()) { power *= 2; ++selector; }
    Bytes result;
    append16(result, 4);
    append16(result, static_cast<uint16_t>(length));
    append16(result, 0);
    append16(result, static_cast<uint16_t>(segments.size() * 2));
    append16(result, static_cast<uint16_t>(power * 2));
    append16(result, selector);
    append16(result, static_cast<uint16_t>(segments.size() * 2 - power * 2));
    for (const auto& segment : segments) append16(result, segment.last);
    append16(result, 0);
    for (const auto& segment : segments) append16(result, segment.first);
    for (const auto& segment : segments) append16(result, segment.delta);
    for (size_t index = 0; index < segments.size(); ++index) append16(result, 0);
    return result;
}

Bytes characterMapTable(const std::vector<CharacterMapping>& mappings) {
    const Bytes bmp = format4(mappings);
    const Bytes full = format12(mappings);
    const uint16_t recordCount = bmp.empty() ? 2 : 4;
    const uint32_t headerSize = 4 + recordCount * 8;
    const uint32_t bmpOffset = headerSize;
    const uint32_t fullOffset = headerSize + static_cast<uint32_t>(bmp.size());
    Bytes result;
    append16(result, 0);
    append16(result, recordCount);
    if (!bmp.empty()) {
        append16(result, 0); append16(result, 3); append32(result, bmpOffset);
    }
    append16(result, 0); append16(result, 4); append32(result, fullOffset);
    if (!bmp.empty()) {
        append16(result, 3); append16(result, 1); append32(result, bmpOffset);
    }
    append16(result, 3); append16(result, 10); append32(result, fullOffset);
    result.insert(result.end(), bmp.begin(), bmp.end());
    result.insert(result.end(), full.begin(), full.end());
    return result;
}

Bytes os2Table(const FontMetrics& font) {
    uint16_t firstCharacter = 0xffff;
    uint16_t lastCharacter = 0;
    for (const auto& mapping : font.mappings) {
        if (mapping.character > 0xffff) continue;
        firstCharacter = std::min(firstCharacter, static_cast<uint16_t>(mapping.character));
        lastCharacter = std::max(lastCharacter, static_cast<uint16_t>(mapping.character));
    }
    if (firstCharacter == 0xffff && lastCharacter == 0) lastCharacter = 0xffff;
    const uint16_t selection = static_cast<uint16_t>((font.italic ? 1 : 0) | (font.bold ? 0x20 : 0) |
                                                      (!font.italic && !font.bold ? 0x40 : 0));
    Bytes result;
    append16(result, 4);
    appendSigned16(result, font.averageWidth);
    append16(result, font.bold ? 700 : 400);
    append16(result, 5);
    append16(result, font.fsType);
    for (int index = 0; index < 10; ++index) appendSigned16(result, 0);
    appendSigned16(result, 0);
    for (int index = 0; index < 10; ++index) result.push_back(0);
    for (int index = 0; index < 4; ++index) append32(result, 0);
    result.insert(result.end(), {'i', 'P', 'S', '2'});
    append16(result, selection);
    append16(result, firstCharacter);
    append16(result, lastCharacter);
    appendSigned16(result, font.ascender);
    appendSigned16(result, font.descender);
    appendSigned16(result, font.lineGap);
    append16(result, unsigned16(std::max<int16_t>(0, font.yMax)));
    append16(result, unsigned16(std::max<int>(0, -font.yMin)));
    append32(result, 0);
    append32(result, 0);
    appendSigned16(result, font.xHeight);
    appendSigned16(result, font.capHeight);
    append16(result, 0);
    append16(result, std::any_of(font.mappings.begin(), font.mappings.end(), [](const auto& item) { return item.character == 0x20; }) ? 0x20 : 0);
    append16(result, 0);
    return result;
}

Bytes assemble(std::span<const uint8_t> cff, const FontMetrics& font) {
    std::vector<Table> tables{
        {{'C', 'F', 'F', ' '}, Bytes(cff.begin(), cff.end())},
        {{'O', 'S', '/', '2'}, os2Table(font)},
        {{'c', 'm', 'a', 'p'}, characterMapTable(font.mappings)},
        {{'h', 'e', 'a', 'd'}, headTable(font)},
        {{'h', 'h', 'e', 'a'}, horizontalHeaderTable(font)},
        {{'h', 'm', 't', 'x'}, horizontalMetricsTable(font)},
        {{'m', 'a', 'x', 'p'}, maximumProfileTable(font.advances.size())},
        {{'n', 'a', 'm', 'e'}, namingTable(font)},
        {{'p', 'o', 's', 't'}, postTable(font)}
    };
    std::sort(tables.begin(), tables.end(), [](const auto& left, const auto& right) { return left.tag < right.tag; });
    const uint16_t count = static_cast<uint16_t>(tables.size());
    uint16_t power = 1;
    uint16_t selector = 0;
    while (power * 2 <= count) { power *= 2; ++selector; }
    uint64_t nextOffset = 12 + tables.size() * 16;
    for (auto& table : tables) {
        nextOffset = (nextOffset + 3) & ~uint64_t(3);
        if (nextOffset + table.data.size() > std::numeric_limits<uint32_t>::max())
            throw std::runtime_error("Embedded CFF is too large for an OpenType container");
        table.offset = static_cast<uint32_t>(nextOffset);
        table.checksum = checksum(table.data);
        nextOffset += table.data.size();
    }
    Bytes result;
    result.reserve(static_cast<size_t>((nextOffset + 3) & ~uint64_t(3)));
    result.insert(result.end(), {'O', 'T', 'T', 'O'});
    append16(result, count);
    append16(result, static_cast<uint16_t>(power * 16));
    append16(result, selector);
    append16(result, static_cast<uint16_t>(count * 16 - power * 16));
    for (const auto& table : tables) {
        result.insert(result.end(), table.tag.begin(), table.tag.end());
        append32(result, table.checksum);
        append32(result, table.offset);
        append32(result, static_cast<uint32_t>(table.data.size()));
    }
    size_t headOffset = 0;
    for (const auto& table : tables) {
        while (result.size() < table.offset) result.push_back(0);
        result.insert(result.end(), table.data.begin(), table.data.end());
        if (table.tag == std::array<char, 4>{'h', 'e', 'a', 'd'}) headOffset = table.offset;
    }
    while (result.size() % 4) result.push_back(0);
    if (!headOffset) throw std::runtime_error("OpenType head table is missing");
    replace32(result, headOffset + 8, 0xb1b0afba - checksum(result));
    return result;
}

void validateWithApple(const Bytes& font, size_t glyphCount) {
    CFDataRef data = CFDataCreateWithBytesNoCopy(kCFAllocatorDefault, font.data(),
                                                 static_cast<CFIndex>(font.size()), kCFAllocatorNull);
    if (!data) throw std::runtime_error("Could not allocate the OpenType validation data");
    CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
    CGFontRef appleFont = provider ? CGFontCreateWithDataProvider(provider) : nullptr;
    const bool valid = appleFont && CGFontGetNumberOfGlyphs(appleFont) == glyphCount;
    if (appleFont) CGFontRelease(appleFont);
    if (provider) CGDataProviderRelease(provider);
    CFRelease(data);
    if (!valid) throw std::runtime_error("Apple font services rejected the generated OpenType font");
}

void validateWithFreeType(FT_Library library, const Bytes& font, const FontMetrics& expected) {
    FT_Face face = nullptr;
    if (FT_New_Memory_Face(library, font.data(), static_cast<FT_Long>(font.size()), 0, &face))
        throw std::runtime_error("The generated OpenType font could not be reopened");
    try {
        if (face->num_glyphs != static_cast<FT_Long>(expected.advances.size()) ||
            face->units_per_EM != expected.unitsPerEm || mappings(face) != expected.mappings)
            throw std::runtime_error("The generated OpenType font changed the embedded CFF glyph mapping");
        FT_Done_Face(face);
    } catch (...) {
        FT_Done_Face(face);
        throw;
    }
}

} // namespace

std::vector<uint8_t> openTypeContainerForCFF(std::span<const uint8_t> cff) {
    if (cff.size() < 4 || cff[0] != 1 || cff[2] < 4 || cff[2] > cff.size() || cff[3] < 1 || cff[3] > 4)
        throw std::runtime_error("Embedded font is not a supported CFF 1 font program");
    FT_Library library = nullptr;
    if (FT_Init_FreeType(&library)) throw std::runtime_error("Could not initialize the embedded font reader");
    FT_Face face = nullptr;
    try {
        if (FT_New_Memory_Face(library, cff.data(), static_cast<FT_Long>(cff.size()), 0, &face))
            throw std::runtime_error("Embedded CFF font could not be read");
        if (face->num_faces != 1)
            throw std::runtime_error("A multi-font CFF FontSet cannot be represented by one OpenType font");
        const FontMetrics metrics = readMetrics(face);
        Bytes result = assemble(cff, metrics);
        validateWithFreeType(library, result, metrics);
        validateWithApple(result, metrics.advances.size());
        FT_Done_Face(face);
        FT_Done_FreeType(library);
        return result;
    } catch (...) {
        if (face) FT_Done_Face(face);
        FT_Done_FreeType(library);
        throw;
    }
}

} // namespace ips2pdf
