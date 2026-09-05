#include "PDFProcessingUnsupported.h"
#include "PDFBinaryImageMetadata.h"
#include "PDFProcessingControl.h"
#include <algorithm>
#include <limits>
#include <set>
#include <stdexcept>
#include <string>

namespace ips2pdf {
namespace {
using Bytes = std::span<const uint8_t>;
using Output = std::vector<uint8_t>;
void require(bool condition) { if (!condition) throw std::runtime_error("Invalid or unsupported image metadata container"); }
uint64_t integer(Bytes input, size_t offset, size_t count) {
    require(offset <= input.size() && count <= input.size() - offset && count <= 8);
    uint64_t value = 0;
    for (size_t i = 0; i < count; ++i) value = (value << 8) | input[offset + i];
    return value;
}
void put(Output& output, size_t offset, uint64_t value, size_t count) {
    require(offset <= output.size() && count <= output.size() - offset);
    for (size_t i = 0; i < count; ++i) { output[offset + count - i - 1] = value & 255; value >>= 8; }
    require(value == 0);
}
void append(Output& output, Bytes bytes) { output.insert(output.end(), bytes.begin(), bytes.end()); }

Output codestream(Bytes input) {
    require(integer(input, 0, 2) == 0xff4f);
    Output result{0xff, 0x4f};
    size_t position = 2;
    while (position < input.size()) {
        checkPDFProcessing();
        const auto marker = integer(input, position, 2);
        if (marker == 0xffd9) { append(result, input.subspan(position, 2)); return result; }
        require((marker & 0xff00) == 0xff00 && marker != 0xff93);
        if (marker == 0xff90) {
            const size_t tileStart = position, outStart = result.size();
            require(integer(input, position + 2, 2) == 10);
            const auto tileLength = integer(input, position + 6, 4);
            require(tileLength == 0 || (tileLength >= 14 && tileLength <= input.size() - position));
            const size_t tileEnd = tileLength ? position + tileLength : input.size();
            append(result, input.subspan(position, 12)); position += 12;
            while (true) {
                const auto tileMarker = integer(input, position, 2);
                if (tileMarker == 0xff93) { append(result, input.subspan(position, 2)); position += 2; break; }
                const auto length = integer(input, position + 2, 2);
                require((tileMarker & 0xff00) == 0xff00 && length >= 2 && position + 2 <= tileEnd && length <= tileEnd - position - 2);
                // COM is descriptive; packet data and packet-length markers
                // are untouched. Psot must follow any tile-header shortening.
                if (tileMarker != 0xff64) append(result, input.subspan(position, length + 2));
                position += length + 2;
            }
            if (tileLength) {
                require(position <= tileEnd);
                append(result, input.subspan(position, tileEnd - position));
                position = tileEnd;
                put(result, outStart + 6, result.size() - outStart, 4);
            } else {
                // A zero Psot denotes the final tile part. Skip complete SOP
                // markers so their arbitrary sequence numbers cannot masquerade
                // as EOC bytes while locating the codestream terminator.
                const size_t entropy = position;
                while (position + 1 < input.size()) {
                    if (input[position] != 0xff) { ++position; continue; }
                    const auto code = input[position + 1];
                    if (code == 0xd9) break;
                    if (code == 0x91) {
                        require(integer(input, position + 2, 2) == 4 && input.size() - position >= 6);
                        position += 6;
                    } else if (code == 0x92) position += 2;
                    else { require(code < 0x90); position += 2; }
                }
                require(position + 1 < input.size());
                append(result, input.subspan(entropy, position - entropy));
            }
            require(position > tileStart);
        } else {
            const auto length = integer(input, position + 2, 2);
            require(length >= 2 && length <= input.size() - position - 2);
            // TLM is an optional tile-part length index. Omitting it avoids
            // retaining stale lengths after removing comments inside tiles.
            if (marker != 0xff64 && marker != 0xff55) append(result, input.subspan(position, length + 2));
            position += length + 2;
        }
    }
    throw std::runtime_error("JPEG 2000 codestream has no end marker");
}

Output boxes(Bytes input, unsigned depth) {
    require(depth <= 32);
    Output result;
    size_t position = 0;
    const std::set<std::string> metadata{"xml ", "uuid", "uinf", "jp2i", "lbl ", "res "};
    const std::set<std::string> containers{"jp2h", "asoc", "jpch", "jplh", "cgrp"};
    const std::set<std::string> preserved{"jP  ", "ftyp", "bpcc", "colr", "pclr", "cmap", "cdef", "nlst", "rreq", "opct", "creg"};
    while (position < input.size()) {
        checkPDFProcessing();
        const auto shortLength = integer(input, position, 4);
        require(input.size() - position >= 8);
        const std::string type(reinterpret_cast<const char*>(input.data() + position + 4), 4);
        const size_t header = shortLength == 1 ? 16 : 8;
        const auto length = shortLength == 1 ? integer(input, position + 8, 8) : shortLength == 0 ? input.size() - position : shortLength;
        require(length >= header && length <= input.size() - position);
        auto payload = input.subspan(position + header, length - header);
        if (!metadata.contains(type)) {
            Output content;
            if (containers.contains(type)) content = boxes(payload, depth + 1);
            else if (type == "jp2c") content = codestream(payload);
            else if (type == "ihdr") {
                require(payload.size() == 14);
                content.assign(payload.begin(), payload.end());
                content[13] = 0; // No IPR box remains; dimensions/color flags stay unchanged.
            } else {
                // Unknown JPX composition/fragment boxes can contain offsets or
                // rendering dependencies. Never guess that they are metadata.
                if (!preserved.contains(type)) throw PDFProcessingUnsupported("This JPEG 2000 container has an unsupported box structure.");
                content.assign(payload.begin(), payload.end());
            }
            require(content.size() <= UINT32_MAX - 8);
            const auto start = result.size();
            result.resize(start + 8);
            put(result, start, content.size() + 8, 4);
            std::copy(type.begin(), type.end(), result.begin() + start + 4);
            append(result, content);
        }
        position += length;
    }
    return result;
}
} // namespace

std::vector<uint8_t> removeJPEG2000Metadata(Bytes input) {
    if (input.size() >= 2 && integer(input, 0, 2) == 0xff4f) return codestream(input);
    require(input.size() >= 12 && integer(input, 0, 4) == 12 && integer(input, 4, 4) == 0x6a502020 &&
            integer(input, 8, 4) == 0x0d0a870a);
    return boxes(input, 0);
}

std::vector<uint8_t> removeJBIG2Metadata(Bytes input) {
    Output result;
    size_t position = 0;
    while (position < input.size()) {
        checkPDFProcessing();
        const size_t start = position;
        const auto segment = integer(input, position, 4); position += 4;
        const auto flags = integer(input, position++, 1);
        const auto type = flags & 63;
        const auto first = integer(input, position, 1);
        uint64_t references = first >> 5;
        if (references == 7) {
            references = integer(input, position, 4) & 0x1fffffff;
            position += 4;
            require(references <= 1'000'000);
            position += (references + 8) / 8;
        } else { require(references <= 4); ++position; }
        const auto referenceBytes = segment > 65536 ? 4 : segment > 256 ? 2 : 1;
        position += references * referenceBytes;
        position += flags & 64 ? 4 : 1;
        const size_t lengthOffset = position - start;
        const auto length = integer(input, position, 4); position += 4;
        // Indefinite generic-region lengths need arithmetic-decoder boundary
        // analysis. Reject them instead of searching compressed data for tags.
        if (length == UINT32_MAX) throw PDFProcessingUnsupported("JBIG2 segments with an indefinite length require decoder-assisted metadata cleanup.");
        require(length <= input.size() - position);
        auto payload = input.subspan(position, length);
        Output content(payload.begin(), payload.end());
        if (type == 62) {
            const auto extension = integer(payload, 0, 4);
            if (extension == 0x20000000 || extension == 0x20000002) {
                // Retain the segment number and reference topology. Empty the
                // ASCII/UCS-2 comment list, including every original comment.
                content.resize(extension == 0x20000000 ? 5 : 6);
                std::fill(content.begin() + 4, content.end(), 0);
            } else {
                // Unknown necessary extensions can affect pixels. Unknown
                // optional extensions cannot safely be classified as private
                // metadata either, so this operation requires explicit support.
                throw PDFProcessingUnsupported("Unsupported JBIG2 extension metadata");
            }
        } else if (type == 48) {
            require(content.size() == 19);
            std::fill(content.begin() + 8, content.begin() + 16, 0);
        }
        const auto outputStart = result.size();
        append(result, input.subspan(start, position - start));
        put(result, outputStart + lengthOffset, content.size(), 4);
        append(result, content);
        position += length;
        if (type == 51) { require(length == 0); return result; }
    }
    return result;
}
} // namespace ips2pdf
