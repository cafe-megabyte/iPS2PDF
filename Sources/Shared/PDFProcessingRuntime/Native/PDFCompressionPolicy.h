#pragma once

#include <algorithm>
#include <cstddef>
#include <cmath>
#include <map>
#include <stdexcept>

namespace ips2pdf {

enum class PDFCompressionLevel { gentle, balanced, strong };

struct PDFCompressionPolicy {
    PDFCompressionLevel level = PDFCompressionLevel::balanced;
    bool monochrome = false;
    int threshold = 75;
    // Keep direct native callers aligned with the fresh-session UI default.
    int contrast = 25;

    void validate() const {
        if (static_cast<int>(level) < 0 || static_cast<int>(level) > 2 || threshold < 0 || threshold > 100 ||
            contrast < 0 || contrast > 100)
            throw std::runtime_error("Invalid PDF compression options");
    }

    double maximumPPI() const {
        // Treat every color image as scan/document content. Higher-resolution
        // presets receive stronger JPEG quantization while smaller bitmaps keep
        // more sample quality, avoiding both losses at the same time.
        constexpr double color[] = {225, 140, 110};
        constexpr double bitmap[] = {600, 450, 300};
        validate();
        const auto index = static_cast<int>(level);
        return monochrome ? bitmap[index] : color[index];
    }

    double resizeScale(double minimumPlacementPPI) const {
        // The caller takes the minimum ppi over both axes and every placement
        // of a shared image, including nested forms. Color targets are strict;
        // monochrome keeps its scan-safe 25 percent resampling margin.
        const auto maximum = maximumPPI();
        const auto thresholdPPI = monochrome ? maximum * 1.25 : maximum;
        if (!std::isfinite(minimumPlacementPPI) || minimumPlacementPPI <= thresholdPPI) return 1;
        return std::min(1.0, maximum / minimumPlacementPPI);
    }

    int jpegQuality() const {
        validate();
        constexpr int quality[] = {20, 40, 60};
        return quality[static_cast<int>(level)];
    }

    bool blackPixel(unsigned red, unsigned green, unsigned blue) const {
        // Rec. 709 luminance, a user threshold, and no dithering. White remains
        // white even at the upper endpoint so paper and knockouts stay clear.
        const auto luminance = 2126u * red + 7152u * green + 722u * blue;
        return luminance < static_cast<unsigned>(threshold) * 25500u;
    }
};

struct PDFCompressionPlan {
    PDFCompressionPolicy document;
    std::map<int, PDFCompressionPolicy> pages;

    void validate() const {
        document.validate();
        for (const auto& [page, policy] : pages) {
            if (page < 0) throw std::runtime_error("Invalid PDF page compression override");
            policy.validate();
        }
    }

    void validatePageCount(std::size_t count) const {
        validate();
        if (!pages.empty() && static_cast<std::size_t>(pages.rbegin()->first) >= count)
            throw std::runtime_error("PDF page compression override is out of range");
    }

    const PDFCompressionPolicy& policyForPage(std::size_t page) const {
        auto found = pages.find(static_cast<int>(page));
        return found == pages.end() ? document : found->second;
    }
};
} // namespace ips2pdf
