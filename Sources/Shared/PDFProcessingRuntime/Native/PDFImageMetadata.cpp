#include "PDFImageMetadata.h"

#include <algorithm>
#include <array>
#include <stdexcept>
#include <string_view>

namespace ips2pdf {
namespace {

[[noreturn]] void invalidJPEG() {
    // Do not include source bytes in diagnostics; these may contain private data.
    throw std::runtime_error("Malformed JPEG marker structure");
}

bool startsWith(std::span<const uint8_t> bytes, std::string_view prefix) {
    return bytes.size() >= prefix.size() &&
        std::equal(prefix.begin(), prefix.end(), bytes.begin());
}

void appendMarker(std::vector<uint8_t>& result, uint8_t marker, std::span<const uint8_t> payload) {
    size_t length = payload.size() + 2;
    if (length > 65535) invalidJPEG();
    result.insert(result.end(), {0xff, marker, static_cast<uint8_t>(length >> 8), static_cast<uint8_t>(length)});
    result.insert(result.end(), payload.begin(), payload.end());
}

} // namespace

std::vector<uint8_t> removeJPEGMetadata(std::span<const uint8_t> input, bool preserveICC) {
    if (input.size() < 4 || input[0] != 0xff || input[1] != 0xd8) invalidJPEG();
    std::vector<uint8_t> result = {0xff, 0xd8};
    result.reserve(input.size());
    size_t position = 2;
    bool saw_scan = false;
    while (position < input.size()) {
        size_t marker_start = position;
        if (input[position++] != 0xff) invalidJPEG();
        while (position < input.size() && input[position] == 0xff) ++position;
        if (position == input.size()) invalidJPEG();
        uint8_t marker = input[position++];
        if (marker == 0x00 || marker == 0xd8) invalidJPEG();
        if (marker == 0xd9) {
            if (!saw_scan) invalidJPEG();
            result.insert(result.end(), {0xff, 0xd9});
            // A PDF image uses one JPEG codestream. Trailing bytes have no
            // display function and can contain an old metadata payload.
            return result;
        }
        if (marker == 0x01 || (marker >= 0xd0 && marker <= 0xd7)) {
            result.insert(result.end(), input.begin() + marker_start, input.begin() + position);
            continue;
        }
        if (input.size() - position < 2) invalidJPEG();
        size_t length = (static_cast<size_t>(input[position]) << 8) | input[position + 1];
        if (length < 2 || length > input.size() - position) invalidJPEG();
        auto payload = input.subspan(position + 2, length - 2);
        size_t segment_end = position + length;
        if (marker == 0xe0 && startsWith(payload, std::string_view("JFIF\0", 5))) {
            if (payload.size() < 14) invalidJPEG();
            // JFIF identifies the color interpretation; retain that signal.
            // PDF placement, rather than JFIF density or its thumbnail, sets
            // the displayed dimensions. Reset density and remove the thumbnail.
            std::array<uint8_t, 14> jfif;
            std::copy_n(payload.begin(), jfif.size(), jfif.begin());
            jfif[7] = 0;
            jfif[8] = jfif[10] = 0;
            jfif[9] = jfif[11] = 1;
            jfif[12] = jfif[13] = 0;
            appendMarker(result, marker, jfif);
        } else if (marker == 0xee && startsWith(payload, "Adobe")) {
            // Adobe's transform byte distinguishes RGB/YCbCr and CMYK/YCCK.
            // Removing it can change visible colors, including CMYK polarity.
            if (payload.size() < 12) invalidJPEG();
            appendMarker(result, marker, payload.first(12));
        } else if (marker == 0xe2 && preserveICC &&
                   startsWith(payload, std::string_view("ICC_PROFILE\0", 12))) {
            if (payload.size() < 14) invalidJPEG();
            appendMarker(result, marker, payload);
        } else if ((marker >= 0xe0 && marker <= 0xef) || marker == 0xfe) {
            // APP1 includes EXIF and XMP; APP13 includes Photoshop/IPTC data.
            // Other application data and free-form comments are not needed by
            // the PDF JPEG decoder. This also removes alternate thumbnails.
        } else {
            result.insert(result.end(), input.begin() + marker_start, input.begin() + segment_end);
        }
        position = segment_end;
        if (marker != 0xda && !(marker == 0xdc && saw_scan)) continue;
        saw_scan = true;
        size_t entropy_start = position;
        // Preserve compressed samples verbatim. FF00 is an escaped data byte;
        // restart markers belong to the scan. Progressive JPEGs can have many
        // scans and metadata between them, so scanning continues after each SOS.
        while (position < input.size()) {
            if (input[position] != 0xff) { ++position; continue; }
            size_t candidate = position;
            while (position < input.size() && input[position] == 0xff) ++position;
            if (position == input.size()) invalidJPEG();
            uint8_t next = input[position];
            if (next == 0x00 || next == 0x01 || (next >= 0xd0 && next <= 0xd7)) { ++position; continue; }
            position = candidate;
            break;
        }
        result.insert(result.end(), input.begin() + entropy_start, input.begin() + position);
    }
    invalidJPEG();
}

} // namespace ips2pdf
