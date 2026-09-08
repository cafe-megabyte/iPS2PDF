#pragma once

#include <cstdint>
#include <cstdio>
#include <span>
#include <vector>

namespace ips2pdf {

// Write CCITT Group 4 rows without retaining the image or encoded stream.
// Input rows use PDF's default polarity: one is white and zero is black.
class PDFGroup4Encoder {
public:
    PDFGroup4Encoder(FILE* file, int width);
    ~PDFGroup4Encoder() = default;

    PDFGroup4Encoder(const PDFGroup4Encoder&) = delete;
    PDFGroup4Encoder& operator=(const PDFGroup4Encoder&) = delete;

    void write(std::span<const uint8_t> row);
    void finish();

private:
    bool bit(std::span<const uint8_t> row, int position) const;
    int findBit(std::span<const uint8_t> row, int start, bool value) const;
    void findReferenceChanges(int a0, bool a0Color, int& b1, int& b2) const;
    void writeRun(int length, bool white);
    void writeBits(uint32_t value, int length);
    void writeByte(uint8_t value);

    FILE* file_;
    int width_;
    size_t rowBytes_;
    std::vector<uint8_t> reference_;
    uint8_t outputByte_ = 0;
    int outputBits_ = 0;
    bool finished_ = false;
};

} // namespace ips2pdf
