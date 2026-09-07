#include "PDFProcessingUnsupported.h"
#include "PDFImageCodec.h"
#include "PDFProcessingControl.h"
#include "PDFImageMetadata.h"
#include <qpdf/QPDFPageDocumentHelper.hh>
#include <qpdf/QPDFWriter.hh>
#include <public/fpdf_edit.h>
#include <public/fpdfview.h>
#include <core/fxcodec/fax/faxmodule.h>
#include <core/fxge/dib/cfx_dibitmap.h>
#include <core/fpdfapi/page/cpdf_colorspace.h>
#include <core/fpdfapi/parser/cpdf_document.h>
#include <core/fpdfapi/parser/cpdf_dictionary.h>
#include <fpdfsdk/cpdfsdk_helpers.h>
#include <Accelerate/Accelerate.h>
#include <algorithm>
#include <cstring>
#include <memory>
#include <stdexcept>
#include <type_traits>

// This is the pinned Hyper Compress jpegli shim, built from source. It accepts
// interleaved samples and has no font, page, document or metadata side effects.
extern "C" bool HyperJpegliEncode(const uint8_t*, int, int, int, int, int, int, int, int, uint8_t**, size_t*);
extern "C" void HyperJpegliFree(void*);

namespace ips2pdf {
namespace {
using Object = QPDFObjectHandle;
constexpr uint64_t maximumPixels = 64 * 1024 * 1024;
void dimensions(int width, int height) {
    checkPDFProcessing();
    if (width <= 0 || height <= 0 || uint64_t(width) * uint64_t(height) > maximumPixels)
        throw PDFProcessingStopped(false);
}
void ensureLibrary() {
        FPDF_LIBRARY_CONFIG config{};
        config.version = 6;
        config.m_BrotliEnabled = 1;
        const char* noSystemFontPaths[] = {nullptr};
        config.m_pUserFontPaths = noSystemFontPaths;
        FPDF_InitLibraryWithConfig(&config);
        // PDFium initialization is idempotent. The helper owns its global
        // caches until process exit; closing one image must not destroy them
        // while another decoder or a native verification client uses PDFium.
}
} // namespace

PDFDecodedImage decodePDFImage(Object image, Object colorSpace, bool preserveAlpha) {
    if (!image.isStream()) throw std::runtime_error("Invalid PDF image");
    auto source = image.getDict();
    auto embeddedAlpha = source.getKey("/SMaskInData");
    if (!embeddedAlpha.isNull() && (!embeddedAlpha.isInteger() || embeddedAlpha.getIntValue() != 0))
        throw PDFProcessingUnsupported("Embedded JPEG 2000 alpha requires a separate alpha conversion");
    const int width = source.getKey("/Width").getIntValueAsInt();
    const int height = source.getKey("/Height").getIntValueAsInt();
    dimensions(width, height);
    // A tiny, private image-only PDF lets PDFium apply the original Decode,
    // palette and ICC interpretation without regenerating any document page.
    // The real PDF's content streams and embedded font programs stay in qpdf.
    QPDF wrapper;
    wrapper.emptyPDF();
    auto copied = wrapper.copyForeignObject(image);
    if (!colorSpace.isNull()) {
        if (!colorSpace.isIndirect()) colorSpace = image.getOwningQPDF()->makeIndirectObject(colorSpace);
        copied.getDict().replaceKey("/ColorSpace", wrapper.copyForeignObject(colorSpace));
    }
    if (!preserveAlpha) {
        copied.getDict().removeKey("/SMask");
        copied.getDict().removeKey("/Mask");
    }
    auto page = wrapper.makeIndirectObject(Object::parse("<< /Type /Page /MediaBox [0 0 1 1] >>"));
    page.replaceKey("/Resources", Object::newDictionary({{"/XObject", Object::newDictionary({{"/Image", copied}})}}));
    page.replaceKey("/Contents", wrapper.newStream("/Image Do\n"));
    QPDFPageDocumentHelper(wrapper).addPage(QPDFPageObjectHelper(page), false);
    QPDFWriter writer(wrapper);
    writer.setOutputMemory();
    writer.setPreserveEncryption(false);
    writer.write();
    auto bytes = writer.getBufferSharedPointer();
    ensureLibrary();
    std::unique_ptr<std::remove_pointer_t<FPDF_DOCUMENT>, decltype(&FPDF_CloseDocument)> document(
        FPDF_LoadMemDocument64(bytes->getBuffer(), bytes->getSize(), nullptr), FPDF_CloseDocument);
    if (!document) throw std::runtime_error("The PDF image could not be decoded");
    std::unique_ptr<std::remove_pointer_t<FPDF_PAGE>, decltype(&FPDF_ClosePage)> loadedPage(FPDF_LoadPage(document.get(), 0), FPDF_ClosePage);
    if (!loadedPage || FPDFPage_CountObjects(loadedPage.get()) != 1)
        throw std::runtime_error("The PDF image could not be decoded");
    std::unique_ptr<std::remove_pointer_t<FPDF_BITMAP>, decltype(&FPDFBitmap_Destroy)> bitmap(
        FPDFImageObj_GetBitmap(FPDFPage_GetObject(loadedPage.get(), 0)), FPDFBitmap_Destroy);
    if (!bitmap || FPDFBitmap_GetWidth(bitmap.get()) != width || FPDFBitmap_GetHeight(bitmap.get()) != height)
        throw std::runtime_error("The decoded PDF image has unexpected dimensions");
    const int format = FPDFBitmap_GetFormat(bitmap.get());
    const int stride = FPDFBitmap_GetStride(bitmap.get());
    const int channels = format == FPDFBitmap_Gray ? 1 : format == FPDFBitmap_BGR ? 3 :
                         format == FPDFBitmap_BGRx || format == FPDFBitmap_BGRA ? 4 : 0;
    const auto* samples = static_cast<const uint8_t*>(FPDFBitmap_GetBuffer(bitmap.get()));
    if (!channels || !samples || stride < width * channels)
        throw std::runtime_error("The PDF image uses an unsupported sample format");
    PDFDecodedImage result{width, height, std::vector<uint8_t>(size_t(width) * height * 4)};
    for (int y = 0; y < height; ++y) {
        checkPDFProcessing();
        for (int x = 0; x < width; ++x) {
            const auto* pixel = samples + size_t(y) * stride + x * channels;
            auto* target = result.pixels.data() + (size_t(y) * width + x) * 4;
            target[0] = pixel[0];
            target[1] = pixel[channels == 1 ? 0 : 1];
            target[2] = pixel[channels == 1 ? 0 : 2];
            target[3] = preserveAlpha && format == FPDFBitmap_BGRA ? pixel[3] : 255;
        }
    }
    return result;
}

PDFDecodedImage resizePDFImage(const PDFDecodedImage& source, int width, int height) {
    dimensions(source.width, source.height);
    dimensions(width, height);
    if (width > source.width || height > source.height ||
        source.pixels.size() != size_t(source.width) * source.height * 4)
        throw std::runtime_error("Invalid PDF image resampling dimensions");
    PDFDecodedImage target{width, height, std::vector<uint8_t>(size_t(width) * height * 4)};
    vImage_Buffer input{const_cast<uint8_t*>(source.pixels.data()), vImagePixelCount(source.height),
                        vImagePixelCount(source.width), size_t(source.width) * 4};
    vImage_Buffer output{target.pixels.data(), vImagePixelCount(height), vImagePixelCount(width), size_t(width) * 4};
    if (vImageScale_ARGB8888(&input, &output, nullptr, kvImageHighQualityResampling) != kvImageNoError)
        throw std::runtime_error("The PDF image could not be resampled");
    checkPDFProcessing();
    return target;
}

std::vector<uint8_t> encodePDFJPEG(const PDFDecodedImage& image, int quality, bool subsampling) {
    dimensions(image.width, image.height);
    if (quality < 1 || quality > 100 || image.pixels.size() != size_t(image.width) * image.height * 4)
        throw std::runtime_error("Invalid PDF JPEG encoding parameters");
    uint8_t* buffer = nullptr;
    size_t count = 0;
    const bool success = HyperJpegliEncode(image.pixels.data(), image.width, image.height, image.width * 4,
                                          4, 1, quality, 1, subsampling ? 1 : 0, &buffer, &count);
    std::unique_ptr<void, decltype(&HyperJpegliFree)> storage(buffer, HyperJpegliFree);
    checkPDFProcessing();
    if (!success || !buffer || !count) throw std::runtime_error("The PDF image could not be JPEG encoded");
    // Remove any encoder comments/application metadata before publication.
    return removeJPEGMetadata(std::span(buffer, count), false);
}

std::vector<uint8_t> encodePDFGroup4(const PDFDecodedImage& image, const PDFCompressionPolicy& policy) {
    policy.validate();
    dimensions(image.width, image.height);
    if (image.pixels.size() != size_t(image.width) * image.height * 4)
        throw std::runtime_error("Invalid PDF bitmap samples");
    auto bitmap = pdfium::MakeRetain<CFX_DIBitmap>();
    if (!bitmap->Create(image.width, image.height, FXDIB_Format::k1bppRgb)) throw std::bad_alloc();
    for (int y = 0; y < image.height; ++y) {
        checkPDFProcessing();
        auto row = bitmap->GetWritableScanline(y);
        std::fill(row.begin(), row.end(), 0xff);
        for (int x = 0; x < image.width; ++x) {
            const auto* pixel = image.pixels.data() + (size_t(y) * image.width + x) * 4;
            if (policy.blackPixel(pixel[2], pixel[1], pixel[0])) row[x / 8] &= uint8_t(~(0x80 >> (x % 8)));
        }
    }
    // Use the same lossless Group 4 encoder as Hyper Compress's CCITT path.
    // No JBIG2 symbol substitution, dithering, or page rasterization occurs.
    auto encoded = fxcodec::FaxModule::FaxEncode(bitmap);
    checkPDFProcessing();
    if (encoded.empty()) throw std::runtime_error("The PDF bitmap could not be CCITT encoded");
    return {encoded.begin(), encoded.end()};
}

class PDFColorConverter::Impl {
public:
    explicit Impl(QPDF& owner, Object colorSpace) {
        checkPDFProcessing();
        QPDF wrapper;
        wrapper.emptyPDF();
        if (!colorSpace.isIndirect()) colorSpace = owner.makeIndirectObject(colorSpace);
        wrapper.getRoot().replaceKey("/iPS2PDFColorSpace", wrapper.copyForeignObject(colorSpace));
        QPDFWriter writer(wrapper);
        writer.setOutputMemory();
        writer.write();
        bytes = writer.getBufferSharedPointer();
        ensureLibrary();
        document.reset(FPDF_LoadMemDocument64(bytes->getBuffer(), bytes->getSize(), nullptr));
        if (!document) throw std::runtime_error("The PDF color space could not be loaded");
        auto* pdfium = CPDFDocumentFromFPDFDocument(document.get());
        auto definition = pdfium->GetRoot()->GetDirectObjectFor("iPS2PDFColorSpace");
        std::set<const CPDF_Object*> visited;
        color = CPDF_ColorSpace::Load(pdfium, definition.Get(), &visited);
        if (!color || color->GetFamily() == CPDF_ColorSpace::Family::kPattern || !color->ComponentCount())
            throw std::runtime_error("The PDF color space cannot be converted to RGB");
    }
    // Reverse destruction order releases the color object before its owning
    // PDFium document, and the document before its in-memory input buffer.
    std::shared_ptr<Buffer> bytes;
    std::unique_ptr<std::remove_pointer_t<FPDF_DOCUMENT>, decltype(&FPDF_CloseDocument)> document{nullptr, FPDF_CloseDocument};
    RetainPtr<CPDF_ColorSpace> color;
};
PDFColorConverter::PDFColorConverter(QPDF& owner, Object colorSpace) : impl(std::make_unique<Impl>(owner, colorSpace)) {}
PDFColorConverter::~PDFColorConverter() = default;
size_t PDFColorConverter::components() const { return impl->color->ComponentCount(); }
std::vector<double> PDFColorConverter::defaultValues() const {
    auto values = impl->color->CreateBufAndSetDefaultColor();
    return {values.begin(), values.end()};
}
std::array<double, 3> PDFColorConverter::rgb(const std::vector<double>& values) const {
    checkPDFProcessing();
    if (values.size() != components()) throw std::runtime_error("Invalid PDF color component count");
    std::vector<float> samples;
    for (double value : values) {
        if (!std::isfinite(value) || std::abs(value) > std::numeric_limits<float>::max())
            throw std::runtime_error("Invalid PDF color component");
        samples.push_back(static_cast<float>(value));
    }
    const auto converted = impl->color->GetRGB(pdfium::span<const float>(samples));
    if (!converted || !std::isfinite(converted->red) || !std::isfinite(converted->green) || !std::isfinite(converted->blue))
        throw std::runtime_error("The PDF color could not be converted to RGB");
    return {std::clamp<double>(converted->red, 0, 1), std::clamp<double>(converted->green, 0, 1),
            std::clamp<double>(converted->blue, 0, 1)};
}
} // namespace ips2pdf
