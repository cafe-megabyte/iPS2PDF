#pragma once

#include <functional>
#include <span>
#include <cstdint>

namespace ips2pdf {

using PDFRGBRowSource = std::function<void(int, std::span<uint8_t>)>;
using PDFRGBRowSink = std::function<void(int, std::span<const uint8_t>)>;
using PDFImageCheckpoint = std::function<void()>;

// Downsample an RGB image without retaining a complete source or destination
// bitmap. Source rows are requested in ascending order. The area filter is
// separable, so its result has no boundaries between the internal row bands.
void resamplePDFRGB(int sourceWidth, int sourceHeight,
                    int targetWidth, int targetHeight, int contrast,
                    const PDFRGBRowSource& source,
                    const PDFRGBRowSink& sink,
                    const PDFImageCheckpoint& checkpoint = {});

} // namespace ips2pdf
