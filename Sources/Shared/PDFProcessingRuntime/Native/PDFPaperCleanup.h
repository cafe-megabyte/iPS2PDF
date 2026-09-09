#pragma once

#include "PDFCompressionPolicy.h"
#include "PDFImageResampler.h"
#include <cstdint>
#include <span>
#include <vector>

namespace ips2pdf {

// A bounded thumbnail describes slow paper illumination changes and regions
// whose chroma must remain in the color layer. Full-resolution samples remain
// in the row pipeline and are never retained here.
class PDFPaperCleanup {
public:
    static PDFPaperCleanup analyze(int sourceWidth, int sourceHeight,
                                   const PDFRGBRowSource& source,
                                   const PDFCompressionPolicy& policy);

    void normalizeRow(int row, int width, int height,
                      std::span<uint8_t> samples) const;
    bool retainsColor(int x, int y, int width, int height) const;
    bool isForeground(int x, int y, int width, int height,
                      unsigned red, unsigned green, unsigned blue) const;
    double colorCoverage() const { return colorCoverage_; }
    double neutralBlackCoverage() const { return neutralBlackCoverage_; }

private:
    int width_ = 0;
    int height_ = 0;
    int strength_ = 0;
    std::vector<int16_t> correction_;
    std::vector<uint8_t> colorMap_;
    std::vector<uint8_t> foregroundThresholdMap_;
    double colorCoverage_ = 0;
    double neutralBlackCoverage_ = 0;
    int foregroundThreshold_ = 191;
};

} // namespace ips2pdf
