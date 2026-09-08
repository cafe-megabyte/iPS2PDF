#pragma once
#include "PDFCompressionPolicy.h"
#include <qpdf/QPDF.hh>
#include <cstdint>
#include <array>
#include <memory>
#include <vector>

namespace ips2pdf {
struct PDFDecodedImage {
    int width = 0;
    int height = 0;
    // Opaque BGRA samples in the PDF decoder's RGB output color space.
    // PDF soft masks are independent resources and are not baked into pixels.
    std::vector<uint8_t> pixels;
};

PDFDecodedImage decodePDFImage(QPDFObjectHandle image, QPDFObjectHandle colorSpace, bool preserveAlpha = false);

// Decode, resample and encode one image through a bounded row pipeline. The
// replacement stream is file-backed until QPDF writes the final document.
void recompressPDFImage(QPDFObjectHandle image, QPDFObjectHandle colorSpace,
                        int targetWidth, int targetHeight,
                        const PDFCompressionPolicy& policy);

// Color cleanup can retain a lower-resolution color layer while keeping the
// neutral one-bit selector at an independently capped resolution.
void recompressPDFImage(QPDFObjectHandle image, QPDFObjectHandle colorSpace,
                        int targetWidth, int targetHeight,
                        int selectorWidth, int selectorHeight,
                        const PDFCompressionPolicy& policy);

// Reuse PDFium's PDF color-space/tint-function implementation for vectors and
// images. Keeping a converter per resolved color space avoids reparsing ICC
// data for every color-setting operation in a content stream.
class PDFColorConverter {
public:
    PDFColorConverter(QPDF& owner, QPDFObjectHandle colorSpace);
    ~PDFColorConverter();
    PDFColorConverter(const PDFColorConverter&) = delete;
    PDFColorConverter& operator=(const PDFColorConverter&) = delete;
    size_t components() const;
    std::vector<double> defaultValues() const;
    std::array<double, 3> rgb(const std::vector<double>& values) const;
private:
    class Impl;
    std::unique_ptr<Impl> impl;
};
} // namespace ips2pdf
