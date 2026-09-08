#include "PDFPaperCleanup.h"
#include "PDFProcessingControl.h"
#include <allheaders.h>
#include <algorithm>
#include <cmath>
#include <memory>
#include <stdexcept>

namespace ips2pdf {
namespace {

struct PixDestroyer {
    void operator()(PIX* pix) const {
        if (pix) pixDestroy(&pix);
    }
};
using Pix = std::unique_ptr<PIX, PixDestroyer>;

uint8_t luminance(const uint8_t* pixel) {
    return static_cast<uint8_t>((2126u * pixel[0] + 7152u * pixel[1] +
                                 722u * pixel[2] + 5000u) / 10000u);
}

uint8_t corrected(uint8_t value, int correction, int strength) {
    // The control scales a per-channel illumination correction. Leptonica's
    // multiplicative map naturally changes dark ink only slightly while broad
    // paper shadows and color casts receive the full correction at 100.
    const double amount = double(strength) / 100.0;
    return static_cast<uint8_t>(std::clamp(std::lround(value + correction * amount), 0l, 255l));
}

std::array<double, 3> chromaticity(unsigned red, unsigned green, unsigned blue) {
    const double sum = std::max(1u, red + green + blue);
    return {red / sum, green / sum, blue / sum};
}

double chromaticityDistance(const uint8_t* pixel, const PDFPaperColor& color) {
    const auto left = chromaticity(pixel[0], pixel[1], pixel[2]);
    const auto right = chromaticity(color.red, color.green, color.blue);
    double distance = 0;
    for (int channel = 0; channel < 3; ++channel) {
        const double difference = left[channel] - right[channel];
        distance += difference * difference;
    }
    return std::sqrt(distance) * 255;
}

double neutralDistance(const uint8_t* pixel) {
    const auto value = chromaticity(pixel[0], pixel[1], pixel[2]);
    double distance = 0;
    for (double channel : value) {
        const double difference = channel - 1.0 / 3.0;
        distance += difference * difference;
    }
    return std::sqrt(distance) * 255;
}

bool matchesPaper(const uint8_t* pixel, const PDFCompressionPolicy& policy) {
    if (policy.paperColorCount == 0) return false;
    // Luminance is deliberately absent: the selected color family must still
    // identify the same paper inside a photograph's broad shadow.
    const double tolerance = 7 + policy.paperCleanup * 0.13;
    for (std::size_t index = 0; index < policy.paperColorCount; ++index)
        if (chromaticityDistance(pixel, policy.paperColors[index]) <= tolerance) return true;
    return false;
}

int otsuThreshold(const std::array<uint64_t, 256>& histogram) {
    uint64_t total = 0;
    long double totalSum = 0;
    for (int value = 0; value < 256; ++value) {
        total += histogram[value];
        totalSum += static_cast<long double>(value) * histogram[value];
    }
    if (total == 0) return 191;
    uint64_t lowerCount = 0;
    long double lowerSum = 0;
    long double bestVariance = -1;
    int best = 191;
    for (int value = 0; value < 255; ++value) {
        lowerCount += histogram[value];
        lowerSum += static_cast<long double>(value) * histogram[value];
        const uint64_t upperCount = total - lowerCount;
        if (lowerCount == 0 || upperCount == 0) continue;
        const long double lowerMean = lowerSum / lowerCount;
        const long double upperMean = (totalSum - lowerSum) / upperCount;
        const long double difference = lowerMean - upperMean;
        const long double variance = static_cast<long double>(lowerCount) *
                                     upperCount * difference * difference;
        if (variance > bestVariance) {
            bestVariance = variance;
            best = value;
        }
    }
    return std::clamp(best, 80, 210);
}

} // namespace

PDFPaperCleanup PDFPaperCleanup::analyze(int sourceWidth, int sourceHeight,
                                         const PDFRGBRowSource& source,
                                         const PDFCompressionPolicy& policy) {
    policy.validate();
    if (sourceWidth <= 0 || sourceHeight <= 0 || !source ||
        policy.paperCleanup <= 0)
        throw std::runtime_error("Invalid PDF paper-cleanup parameters");

    PDFPaperCleanup result;
    result.strength_ = policy.paperCleanup;
    constexpr int maximumAnalysisDimension = 512;
    const double scale = std::min(1.0, double(maximumAnalysisDimension) /
        std::max(sourceWidth, sourceHeight));
    result.width_ = std::max(1, static_cast<int>(std::ceil(sourceWidth * scale)));
    result.height_ = std::max(1, static_cast<int>(std::ceil(sourceHeight * scale)));
    std::vector<uint8_t> rgb(size_t(result.width_) * result.height_ * 3);
    resamplePDFRGB(sourceWidth, sourceHeight, result.width_, result.height_, 0, source,
        [&](int row, std::span<const uint8_t> samples) {
            std::copy(samples.begin(), samples.end(),
                      rgb.begin() + size_t(row) * result.width_ * 3);
        }, [] { checkPDFProcessing(); });

    result.correction_.assign(size_t(result.width_) * result.height_ * 3, 0);
    Pix colorSource(pixCreate(result.width_, result.height_, 32));
    Pix foreground(pixCreate(result.width_, result.height_, 1));
    if (!colorSource || !foreground) throw std::runtime_error("Could not allocate paper analysis");
    uint64_t foregroundPixels = 0;
    for (int y = 0; y < result.height_; ++y) {
        for (int x = 0; x < result.width_; ++x) {
            const auto* pixel = rgb.data() + (size_t(y) * result.width_ + x) * 3;
            const auto value = luminance(pixel);
            if (pixSetRGBPixel(colorSource.get(), x, y, pixel[0], pixel[1], pixel[2]))
                throw std::runtime_error("Could not prepare paper analysis");
            const bool sampledPaper = matchesPaper(pixel, policy);
            const double colorDistance = neutralDistance(pixel);
            // Morphological closing removes ordinary text. The mask is only
            // for very dark or strongly chromatic content too large to be
            // mistaken for a text stroke. Moderate colored illumination stays
            // available to the RGB background model.
            const double protectionThreshold = 18 + policy.paperCleanup * 0.12;
            const bool protect = !sampledPaper &&
                                 (value < 48 || colorDistance > protectionThreshold);
            if (protect && pixSetPixel(foreground.get(), x, y, 1))
                throw std::runtime_error("Could not prepare paper foreground analysis");
            if (protect) ++foregroundPixels;
        }
    }

    // Morphological background estimation ignores ordinary text strokes and
    // follows only broad illumination changes. Small images cannot provide a
    // useful background field and keep a zero correction.
    Pix normalized;
    if (result.width_ >= 32 && result.height_ >= 32) {
        const uint64_t pixels = uint64_t(result.width_) * result.height_;
        // Dark text and chromatic marks are not samples of the paper. Masking
        // them prevents a large logo from being normalized into white.
        auto* mask = foregroundPixels > 0 && foregroundPixels * 20 < pixels * 19
            ? foreground.get() : nullptr;
        normalized.reset(pixBackgroundNormMorph(colorSource.get(), mask, 4, 7, 250));
    }
    if (normalized) {
        for (int y = 0; y < result.height_; ++y) {
            for (int x = 0; x < result.width_; ++x) {
                l_int32 sourceRed = 0, sourceGreen = 0, sourceBlue = 0;
                l_int32 normalizedRed = 0, normalizedGreen = 0, normalizedBlue = 0;
                if (pixGetRGBPixel(colorSource.get(), x, y, &sourceRed, &sourceGreen, &sourceBlue) ||
                    pixGetRGBPixel(normalized.get(), x, y, &normalizedRed, &normalizedGreen, &normalizedBlue))
                    throw std::runtime_error("Could not read paper analysis");
                const int source[] = {sourceRed, sourceGreen, sourceBlue};
                const int adjusted[] = {normalizedRed, normalizedGreen, normalizedBlue};
                for (int channel = 0; channel < 3; ++channel) {
                    // Only brighten. A channel already above the target must
                    // not acquire a dark rim at a page or mask boundary.
                    result.correction_[(size_t(y) * result.width_ + x) * 3 + channel] =
                        static_cast<int16_t>(std::max(0, adjusted[channel] - source[channel]));
                }
            }
        }
    }

    Pix color(pixCreate(result.width_, result.height_, 1));
    Pix neutralLuminance(pixCreate(result.width_, result.height_, 8));
    if (!color || !neutralLuminance)
        throw std::runtime_error("Could not allocate color analysis");
    // Stronger cleanup accepts more nearly neutral pixels in the one-bit
    // layer. Saturated marks and photographs remain color at every setting.
    const int chromaTolerance = 4 + (36 * policy.paperCleanup + 50) / 100;
    std::array<uint64_t, 256> neutralHistogram{};
    for (int y = 0; y < result.height_; ++y) {
        for (int x = 0; x < result.width_; ++x) {
            const auto index = size_t(y) * result.width_ + x;
            const auto* pixel = rgb.data() + index * 3;
            const int red = corrected(pixel[0], result.correction_[index * 3], policy.paperCleanup);
            const int green = corrected(pixel[1], result.correction_[index * 3 + 1], policy.paperCleanup);
            const int blue = corrected(pixel[2], result.correction_[index * 3 + 2], policy.paperCleanup);
            const int chroma = std::max({red, green, blue}) - std::min({red, green, blue});
            const bool isColor = !matchesPaper(pixel, policy) && chroma > chromaTolerance;
            if (isColor) {
                if (pixSetPixel(color.get(), x, y, 1))
                    throw std::runtime_error("Could not prepare color analysis");
            }
            const uint8_t adjusted[] = {
                static_cast<uint8_t>(red), static_cast<uint8_t>(green),
                static_cast<uint8_t>(blue)
            };
            const uint8_t value = luminance(adjusted);
            if (!isColor) ++neutralHistogram[value];
            if (pixSetPixel(neutralLuminance.get(), x, y, value))
                throw std::runtime_error("Could not prepare foreground analysis");
        }
    }
    const int automaticThreshold = otsuThreshold(neutralHistogram);
    const int configuredThreshold = policy.threshold * 255 / 100;
    result.foregroundThreshold_ = static_cast<int>(std::lround(
        configuredThreshold * (100 - policy.paperCleanup) / 100.0 +
        automaticThreshold * policy.paperCleanup / 100.0
    ));

    // Text is distinguished from photographed paper by local contrast. A
    // bounded Sauvola threshold field removes broad folds and shadows without
    // retaining a second full-resolution raster. The cleanup control blends
    // from the explicit document threshold to the local field and reaches its
    // most aggressive paper separation at 100.
    const int shortestSide = std::min(result.width_, result.height_);
    if (shortestSide >= 7) {
        const int maximumHalfWindow = (shortestSide - 3) / 2;
        const int halfWindow = std::clamp(shortestSide / 24, 2, maximumHalfWindow);
        const float factor = 0.20f + 0.30f * policy.paperCleanup / 100.0f;
        PIX* rawThresholds = nullptr;
        if (pixSauvolaBinarize(neutralLuminance.get(), halfWindow, factor, 1,
                              nullptr, nullptr, &rawThresholds, nullptr) == 0 &&
            rawThresholds) {
            Pix thresholds(rawThresholds);
            result.foregroundThresholdMap_.resize(size_t(result.width_) * result.height_);
            for (int y = 0; y < result.height_; ++y) {
                for (int x = 0; x < result.width_; ++x) {
                    l_uint32 local = 0;
                    if (pixGetPixel(thresholds.get(), x, y, &local))
                        throw std::runtime_error("Could not read foreground analysis");
                    const int blended = static_cast<int>(std::lround(
                        configuredThreshold * (100 - policy.paperCleanup) / 100.0 +
                        int(local) * policy.paperCleanup / 100.0
                    ));
                    result.foregroundThresholdMap_[size_t(y) * result.width_ + x] =
                        static_cast<uint8_t>(std::clamp(blended, 0, 255));
                }
            }
        }
    }

    // Keep a small neutral halo around actual color so anti-aliased edges and
    // white details inside colored marks are not cut out of the color layer.
    const int radius = std::clamp(4 - (3 * policy.paperCleanup + 50) / 100, 1, 4);
    Pix dilated(pixDilateBrick(nullptr, color.get(), radius * 2 + 1, radius * 2 + 1));
    if (!dilated) throw std::runtime_error("Could not finish color analysis");
    result.colorMap_.resize(size_t(result.width_) * result.height_);
    uint64_t colorPixels = 0;
    uint64_t blackPixels = 0;
    for (int y = 0; y < result.height_; ++y) {
        for (int x = 0; x < result.width_; ++x) {
            const auto index = size_t(y) * result.width_ + x;
            l_uint32 isColor = 0;
            if (pixGetPixel(dilated.get(), x, y, &isColor))
                throw std::runtime_error("Could not read color analysis");
            result.colorMap_[index] = isColor != 0;
            if (isColor) {
                ++colorPixels;
                continue;
            }
            const auto* pixel = rgb.data() + index * 3;
            const uint8_t adjusted[] = {
                corrected(pixel[0], result.correction_[index * 3], policy.paperCleanup),
                corrected(pixel[1], result.correction_[index * 3 + 1], policy.paperCleanup),
                corrected(pixel[2], result.correction_[index * 3 + 2], policy.paperCleanup)
            };
            const int threshold = result.foregroundThresholdMap_.empty()
                ? result.foregroundThreshold_
                : result.foregroundThresholdMap_[index];
            if (luminance(adjusted) < threshold) ++blackPixels;
        }
    }
    const double pixels = double(result.width_) * result.height_;
    result.colorCoverage_ = colorPixels / pixels;
    result.neutralBlackCoverage_ = blackPixels / pixels;
    return result;
}

void PDFPaperCleanup::normalizeRow(int row, int width, int height,
                                   std::span<uint8_t> samples) const {
    if (row < 0 || row >= height || width <= 0 || height <= 0 ||
        samples.size() != size_t(width) * 3 || correction_.empty())
        throw std::runtime_error("Invalid PDF paper-cleanup row");
    const double sourceY = std::clamp((row + 0.5) * height_ / height - 0.5,
                                      0.0, double(height_ - 1));
    const int y0 = static_cast<int>(std::floor(sourceY));
    const int y1 = std::min(y0 + 1, height_ - 1);
    const double fy = sourceY - y0;
    for (int x = 0; x < width; ++x) {
        const double sourceX = std::clamp((x + 0.5) * width_ / width - 0.5,
                                          0.0, double(width_ - 1));
        const int x0 = static_cast<int>(std::floor(sourceX));
        const int x1 = std::min(x0 + 1, width_ - 1);
        const double fx = sourceX - x0;
        const auto at = [&](int sampleX, int sampleY, int channel) {
            return correction_[(size_t(sampleY) * width_ + sampleX) * 3 + channel];
        };
        for (int channel = 0; channel < 3; ++channel) {
            const double top = at(x0, y0, channel) * (1 - fx) +
                               at(x1, y0, channel) * fx;
            const double bottom = at(x0, y1, channel) * (1 - fx) +
                                  at(x1, y1, channel) * fx;
            const int correction = static_cast<int>(std::lround(top * (1 - fy) + bottom * fy));
            auto& value = samples[size_t(x) * 3 + channel];
            value = corrected(value, correction, strength_);
        }
    }
}

bool PDFPaperCleanup::retainsColor(int x, int y, int width, int height) const {
    if (x < 0 || x >= width || y < 0 || y >= height || width <= 0 || height <= 0 ||
        colorMap_.empty())
        throw std::runtime_error("Invalid PDF color-map lookup");
    const int sampleX = std::min(width_ - 1, x * width_ / width);
    const int sampleY = std::min(height_ - 1, y * height_ / height);
    return colorMap_[size_t(sampleY) * width_ + sampleX] != 0;
}

bool PDFPaperCleanup::isForeground(int x, int y, int width, int height,
                                   unsigned red, unsigned green, unsigned blue) const {
    if (x < 0 || x >= width || y < 0 || y >= height || width <= 0 || height <= 0)
        throw std::runtime_error("Invalid PDF foreground-map lookup");
    const uint8_t pixel[] = {
        static_cast<uint8_t>(red), static_cast<uint8_t>(green),
        static_cast<uint8_t>(blue)
    };
    int threshold = foregroundThreshold_;
    if (!foregroundThresholdMap_.empty()) {
        const int sampleX = std::min(width_ - 1, x * width_ / width);
        const int sampleY = std::min(height_ - 1, y * height_ / height);
        threshold = foregroundThresholdMap_[size_t(sampleY) * width_ + sampleX];
    }
    return luminance(pixel) < threshold;
}

} // namespace ips2pdf
