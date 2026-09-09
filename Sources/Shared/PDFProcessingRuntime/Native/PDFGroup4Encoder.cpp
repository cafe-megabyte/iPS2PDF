// The CCITT code tables and two-dimensional encoding procedure in this file
// are based on PDFium's fax encoder.
// Copyright 2014 The PDFium Authors
// Copyright 2014 Foxit Software Inc. http://www.foxitsoftware.com
// Use is governed by the BSD-style license in PDFium's LICENSE file.

#include "PDFGroup4Encoder.h"

#include <algorithm>
#include <array>
#include <stdexcept>

namespace ips2pdf {
namespace {

constexpr std::array<uint8_t, 128> blackRunTerminator = {{
    0x37, 10, 0x02, 3,  0x03, 2,  0x02, 2,  0x03, 3,  0x03, 4,  0x02, 4,
    0x03, 5,  0x05, 6,  0x04, 6,  0x04, 7,  0x05, 7,  0x07, 7,  0x04, 8,
    0x07, 8,  0x18, 9,  0x17, 10, 0x18, 10, 0x08, 10, 0x67, 11, 0x68, 11,
    0x6c, 11, 0x37, 11, 0x28, 11, 0x17, 11, 0x18, 11, 0xca, 12, 0xcb, 12,
    0xcc, 12, 0xcd, 12, 0x68, 12, 0x69, 12, 0x6a, 12, 0x6b, 12, 0xd2, 12,
    0xd3, 12, 0xd4, 12, 0xd5, 12, 0xd6, 12, 0xd7, 12, 0x6c, 12, 0x6d, 12,
    0xda, 12, 0xdb, 12, 0x54, 12, 0x55, 12, 0x56, 12, 0x57, 12, 0x64, 12,
    0x65, 12, 0x52, 12, 0x53, 12, 0x24, 12, 0x37, 12, 0x38, 12, 0x27, 12,
    0x28, 12, 0x58, 12, 0x59, 12, 0x2b, 12, 0x2c, 12, 0x5a, 12, 0x66, 12,
    0x67, 12,
}};

constexpr std::array<uint8_t, 80> blackRunMarkup = {{
    0x0f, 10, 0xc8, 12, 0xc9, 12, 0x5b, 12, 0x33, 12, 0x34, 12, 0x35, 12,
    0x6c, 13, 0x6d, 13, 0x4a, 13, 0x4b, 13, 0x4c, 13, 0x4d, 13, 0x72, 13,
    0x73, 13, 0x74, 13, 0x75, 13, 0x76, 13, 0x77, 13, 0x52, 13, 0x53, 13,
    0x54, 13, 0x55, 13, 0x5a, 13, 0x5b, 13, 0x64, 13, 0x65, 13, 0x08, 11,
    0x0c, 11, 0x0d, 11, 0x12, 12, 0x13, 12, 0x14, 12, 0x15, 12, 0x16, 12,
    0x17, 12, 0x1c, 12, 0x1d, 12, 0x1e, 12, 0x1f, 12,
}};

constexpr std::array<uint8_t, 128> whiteRunTerminator = {{
    0x35, 8, 0x07, 6, 0x07, 4, 0x08, 4, 0x0b, 4, 0x0c, 4, 0x0e, 4, 0x0f, 4,
    0x13, 5, 0x14, 5, 0x07, 5, 0x08, 5, 0x08, 6, 0x03, 6, 0x34, 6, 0x35, 6,
    0x2a, 6, 0x2b, 6, 0x27, 7, 0x0c, 7, 0x08, 7, 0x17, 7, 0x03, 7, 0x04, 7,
    0x28, 7, 0x2b, 7, 0x13, 7, 0x24, 7, 0x18, 7, 0x02, 8, 0x03, 8, 0x1a, 8,
    0x1b, 8, 0x12, 8, 0x13, 8, 0x14, 8, 0x15, 8, 0x16, 8, 0x17, 8, 0x28, 8,
    0x29, 8, 0x2a, 8, 0x2b, 8, 0x2c, 8, 0x2d, 8, 0x04, 8, 0x05, 8, 0x0a, 8,
    0x0b, 8, 0x52, 8, 0x53, 8, 0x54, 8, 0x55, 8, 0x24, 8, 0x25, 8, 0x58, 8,
    0x59, 8, 0x5a, 8, 0x5b, 8, 0x4a, 8, 0x4b, 8, 0x32, 8, 0x33, 8, 0x34, 8,
}};

constexpr std::array<uint8_t, 80> whiteRunMarkup = {{
    0x1b, 5,  0x12, 5,  0x17, 6,  0x37, 7,  0x36, 8,  0x37, 8,  0x64, 8,
    0x65, 8,  0x68, 8,  0x67, 8,  0xcc, 9,  0xcd, 9,  0xd2, 9, 0xd3, 9,
    0xd4, 9,  0xd5, 9,  0xd6, 9,  0xd7, 9,  0xd8, 9,  0xd9, 9, 0xda, 9,
    0xdb, 9,  0x98, 9,  0x99, 9,  0x9a, 9,  0x18, 6,  0x9b, 9, 0x08, 11,
    0x0c, 11, 0x0d, 11, 0x12, 12, 0x13, 12, 0x14, 12, 0x15, 12, 0x16, 12,
    0x17, 12, 0x1c, 12, 0x1d, 12, 0x1e, 12, 0x1f, 12,
}};

} // namespace

PDFGroup4Encoder::PDFGroup4Encoder(FILE* file, int width)
    : file_(file), width_(width), rowBytes_((size_t(width) + 7) / 8),
      reference_(rowBytes_, 0xff) {
    if (!file_ || width_ <= 0) throw std::runtime_error("Invalid CCITT image");
}

bool PDFGroup4Encoder::bit(std::span<const uint8_t> row, int position) const {
    return (row[size_t(position) / 8] & (0x80 >> (position % 8))) != 0;
}

int PDFGroup4Encoder::findBit(std::span<const uint8_t> row, int start, bool value) const {
    for (int position = std::max(start, 0); position < width_; ++position)
        if (bit(row, position) == value) return position;
    return width_;
}

void PDFGroup4Encoder::findReferenceChanges(int a0, bool a0Color, int& b1, int& b2) const {
    bool first = a0 < 0 || bit(reference_, a0);
    b1 = findBit(reference_, a0 + 1, !first);
    if (b1 >= width_) { b1 = b2 = width_; return; }
    if (first == !a0Color) {
        b1 = findBit(reference_, b1 + 1, first);
        first = !first;
    }
    if (b1 >= width_) { b1 = b2 = width_; return; }
    b2 = findBit(reference_, b1 + 1, first);
}

void PDFGroup4Encoder::writeByte(uint8_t value) {
    if (std::fputc(value, file_) == EOF)
        throw std::runtime_error("Could not write compressed PDF bitmap");
}

void PDFGroup4Encoder::writeBits(uint32_t value, int length) {
    for (int index = length - 1; index >= 0; --index) {
        outputByte_ |= uint8_t(((value >> index) & 1) << (7 - outputBits_));
        if (++outputBits_ == 8) {
            writeByte(outputByte_);
            outputByte_ = 0;
            outputBits_ = 0;
        }
    }
}

void PDFGroup4Encoder::writeRun(int length, bool white) {
    while (length >= 2560) {
        writeBits(0x1f, 12);
        length -= 2560;
    }
    if (length >= 64) {
        const int markup = length - length % 64;
        const size_t index = size_t(markup / 64 - 1) * 2;
        const auto& table = white ? whiteRunMarkup : blackRunMarkup;
        writeBits(table[index], table[index + 1]);
    }
    length %= 64;
    const size_t index = size_t(length) * 2;
    const auto& table = white ? whiteRunTerminator : blackRunTerminator;
    writeBits(table[index], table[index + 1]);
}

void PDFGroup4Encoder::write(std::span<const uint8_t> row) {
    if (finished_ || row.size() != rowBytes_)
        throw std::runtime_error("Invalid CCITT image row");

    int a0 = -1;
    bool a0Color = true;
    while (a0 < width_) {
        const int a1 = findBit(row, a0 + 1, !a0Color);
        int b1 = width_, b2 = width_;
        findReferenceChanges(a0, a0Color, b1, b2);
        if (b2 < a1) {
            writeBits(0x1, 4); // Pass mode: 0001.
            a0 = b2;
        } else if (std::abs(a1 - b1) <= 3) {
            switch (a1 - b1) {
            case 0:  writeBits(0x1, 1); break;
            case 1:  writeBits(0x3, 3); break;
            case -1: writeBits(0x2, 3); break;
            case 2:  writeBits(0x3, 6); break;
            case -2: writeBits(0x2, 6); break;
            case 3:  writeBits(0x3, 7); break;
            case -3: writeBits(0x2, 7); break;
            }
            a0 = a1;
            a0Color = !a0Color;
        } else {
            const int a2 = findBit(row, a1 + 1, a0Color);
            writeBits(0x1, 3); // Horizontal mode: 001.
            if (a0 < 0) a0 = 0;
            writeRun(a1 - a0, a0Color);
            writeRun(a2 - a1, !a0Color);
            a0 = a2;
        }
    }
    std::copy(row.begin(), row.end(), reference_.begin());
}

void PDFGroup4Encoder::finish() {
    if (finished_) throw std::runtime_error("CCITT image was already finished");
    if (outputBits_) writeByte(outputByte_);
    finished_ = true;
}

} // namespace ips2pdf
