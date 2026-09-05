#pragma once

#include <algorithm>
#include <cmath>
#include <stdexcept>

namespace ips2pdf {

enum class PDFCompressionLevel { gentle, balanced, strong };

struct PDFCompressionPolicy {
    PDFCompressionLevel level = PDFCompressionLevel::balanced;
    bool monochrome = false;
    int threshold = 50;

    void validate() const {
        if (static_cast<int>(level) < 0 || static_cast<int>(level) > 2 || threshold < 0 || threshold > 100)
            throw std::runtime_error("Invalid PDF compression options");
    }

    int maximumPPI(bool documentLike) const {
        // Strong compression keeps document scans at 300 ppi. Small scanned
        // text must not receive both heavy downsampling and heavy JPEG loss.
        constexpr int photos[] = {300, 225, 150};
        constexpr int documents[] = {450, 300, 300};
        constexpr int bitmap[] = {600, 450, 300};
        validate();
        const auto index = static_cast<int>(level);
        return monochrome ? bitmap[index] : documentLike ? documents[index] : photos[index];
    }

    double resizeScale(double minimumPlacementPPI, bool documentLike) const {
        // The caller takes the minimum ppi over both axes and every placement
        // of a shared image, including nested forms. Never upscale an image.
        const auto maximum = maximumPPI(documentLike);
        if (!std::isfinite(minimumPlacementPPI) || minimumPlacementPPI <= maximum * 1.25) return 1;
        return std::min(1.0, maximum / minimumPlacementPPI);
    }

    int jpegQuality(double finalMinimumPPI, bool documentLike) const {
        validate();
        constexpr int high[] = {88, 80, 72};
        constexpr int medium[] = {90, 86, 84};
        constexpr int low[] = {94, 92, 90};
        const int index = static_cast<int>(level);
        if (!std::isfinite(finalMinimumPPI) || finalMinimumPPI <= 0) return 94;
        double quality;
        if (finalMinimumPPI <= 150) quality = low[index];
        else if (finalMinimumPPI < 225)
            quality = low[index] + (medium[index] - low[index]) * (finalMinimumPPI - 150) / 75;
        else if (finalMinimumPPI < 300)
            quality = medium[index] + (high[index] - medium[index]) * (finalMinimumPPI - 225) / 75;
        else quality = high[index];
        if (documentLike) quality = std::max(quality, finalMinimumPPI < 300 ? 94.0 : 85.0);
        return static_cast<int>(std::ceil(quality));
    }

    bool blackPixel(unsigned red, unsigned green, unsigned blue) const {
        // Rec. 709 luminance, a user threshold, and no dithering. White remains
        // white even at the upper endpoint so paper and knockouts stay clear.
        const auto luminance = 2126u * red + 7152u * green + 722u * blue;
        return luminance < static_cast<unsigned>(threshold) * 25500u;
    }
};
} // namespace ips2pdf
