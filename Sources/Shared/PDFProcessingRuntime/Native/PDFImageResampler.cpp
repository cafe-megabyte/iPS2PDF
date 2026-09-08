#include "PDFImageResampler.h"

#include <algorithm>
#include <cmath>
#include <limits>
#include <stdexcept>
#include <vector>

namespace ips2pdf {
namespace {

void validateDimensions(int sourceWidth, int sourceHeight,
                        int targetWidth, int targetHeight) {
    if (sourceWidth <= 0 || sourceHeight <= 0 || targetWidth <= 0 || targetHeight <= 0 ||
        targetWidth > sourceWidth || targetHeight > sourceHeight)
        throw std::runtime_error("Invalid PDF image resampling dimensions");
    constexpr uint64_t maximumPixels = 64ull * 1024 * 1024;
    if (uint64_t(sourceWidth) * uint64_t(sourceHeight) > maximumPixels ||
        uint64_t(targetWidth) * uint64_t(targetHeight) > maximumPixels)
        throw std::runtime_error("PDF image dimensions exceed the processing limit");
}

void applyContrast(std::span<uint8_t> row, int contrast) {
    if (contrast == 0) return;
    const double factor = std::exp2(double(contrast) / 50.0);
    for (size_t offset = 0; offset < row.size(); offset += 3) {
        const double red = row[offset], green = row[offset + 1], blue = row[offset + 2];
        const double luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue;
        const double adjusted = (luminance - 127.5) * factor + 127.5;
        const double delta = adjusted - luminance;
        row[offset] = static_cast<uint8_t>(std::clamp(std::round(red + delta), 0.0, 255.0));
        row[offset + 1] = static_cast<uint8_t>(std::clamp(std::round(green + delta), 0.0, 255.0));
        row[offset + 2] = static_cast<uint8_t>(std::clamp(std::round(blue + delta), 0.0, 255.0));
    }
}

void horizontalAreaRow(std::span<const uint8_t> source, int sourceWidth,
                       int targetWidth, std::span<uint64_t> target) {
    for (int targetX = 0; targetX < targetWidth; ++targetX) {
        const int64_t targetStart = int64_t(targetX) * sourceWidth;
        const int64_t targetEnd = int64_t(targetX + 1) * sourceWidth;
        const int firstSourceX = static_cast<int>(targetStart / targetWidth);
        const int lastSourceX = static_cast<int>((targetEnd - 1) / targetWidth);
        uint64_t channels[3]{};
        for (int sourceX = firstSourceX; sourceX <= lastSourceX; ++sourceX) {
            const int64_t sourceStart = int64_t(sourceX) * targetWidth;
            const int64_t sourceEnd = int64_t(sourceX + 1) * targetWidth;
            const auto weight = static_cast<uint64_t>(
                std::min(targetEnd, sourceEnd) - std::max(targetStart, sourceStart));
            for (int channel = 0; channel < 3; ++channel)
                channels[channel] += uint64_t(source[size_t(sourceX) * 3 + channel]) * weight;
        }
        for (int channel = 0; channel < 3; ++channel)
            target[size_t(targetX) * 3 + channel] = channels[channel];
    }
}

} // namespace

void resamplePDFRGB(int sourceWidth, int sourceHeight,
                    int targetWidth, int targetHeight, int contrast,
                    const PDFRGBRowSource& source,
                    const PDFRGBRowSink& sink,
                    const PDFImageCheckpoint& checkpoint) {
    validateDimensions(sourceWidth, sourceHeight, targetWidth, targetHeight);
    if (contrast < 0 || contrast > 100 || !source || !sink)
        throw std::runtime_error("Invalid PDF image resampling parameters");

    std::vector<uint8_t> sourceRow(size_t(sourceWidth) * 3);
    std::vector<uint8_t> targetRow(size_t(targetWidth) * 3);
    std::vector<uint64_t> horizontal(size_t(targetWidth) * 3);
    std::vector<uint64_t> accumulated(size_t(targetWidth) * 3);
    int cachedSourceY = -1;

    const uint64_t divisor = uint64_t(sourceWidth) * uint64_t(sourceHeight);
    for (int targetY = 0; targetY < targetHeight; ++targetY) {
        if (checkpoint) checkpoint();
        std::fill(accumulated.begin(), accumulated.end(), 0);
        const int64_t targetStart = int64_t(targetY) * sourceHeight;
        const int64_t targetEnd = int64_t(targetY + 1) * sourceHeight;
        const int firstSourceY = static_cast<int>(targetStart / targetHeight);
        const int lastSourceY = static_cast<int>((targetEnd - 1) / targetHeight);
        for (int sourceY = firstSourceY; sourceY <= lastSourceY; ++sourceY) {
            if (sourceY != cachedSourceY) {
                source(sourceY, sourceRow);
                applyContrast(sourceRow, contrast);
                horizontalAreaRow(sourceRow, sourceWidth, targetWidth, horizontal);
                cachedSourceY = sourceY;
            }
            const int64_t sourceStart = int64_t(sourceY) * targetHeight;
            const int64_t sourceEnd = int64_t(sourceY + 1) * targetHeight;
            const auto weight = static_cast<uint64_t>(
                std::min(targetEnd, sourceEnd) - std::max(targetStart, sourceStart));
            for (size_t index = 0; index < accumulated.size(); ++index)
                accumulated[index] += horizontal[index] * weight;
        }
        for (size_t index = 0; index < targetRow.size(); ++index)
            targetRow[index] = static_cast<uint8_t>((accumulated[index] + divisor / 2) / divisor);
        sink(targetY, targetRow);
    }
}

} // namespace ips2pdf
