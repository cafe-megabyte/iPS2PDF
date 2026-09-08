#include "PDFProcessingUnsupported.h"
#include "PDFGroup4Encoder.h"
#include "PDFImageCodec.h"
#include "PDFImageResampler.h"
#include "PDFPaperCleanup.h"
#include "PDFProcessingControl.h"
#include <qpdf/Pipeline.hh>
#include <qpdf/QPDFPageDocumentHelper.hh>
#include <qpdf/QPDFWriter.hh>
#include <qpdf/QUtil.hh>
#include <public/fpdf_edit.h>
#include <public/fpdfview.h>
#include <core/fpdfapi/page/cpdf_colorspace.h>
#include <core/fpdfapi/page/cpdf_image.h>
#include <core/fpdfapi/page/cpdf_imageobject.h>
#include <core/fpdfapi/parser/cpdf_document.h>
#include <core/fpdfapi/parser/cpdf_dictionary.h>
#include <core/fxge/dib/cfx_dibbase.h>
#include <fpdfsdk/cpdfsdk_helpers.h>
#include <lib/jpegli/common.h>
#include <lib/jpegli/encode.h>
#include <zlib.h>
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <filesystem>
#include <memory>
#include <optional>
#include <set>
#include <setjmp.h>
#include <stdexcept>
#include <string>
#include <type_traits>
#include <unistd.h>
#include <vector>

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

struct FileCloser {
    void operator()(FILE* file) const { if (file) std::fclose(file); }
};
using FileHandle = std::unique_ptr<FILE, FileCloser>;

class TemporaryFile {
public:
    static std::shared_ptr<TemporaryFile> create() {
        const char* environment = std::getenv("TMPDIR");
        std::string directory = environment && *environment ? environment : "/tmp";
        if (directory.back() != '/') directory.push_back('/');
        std::string pattern = directory + "ips2pdf-image-XXXXXX";
        std::vector<char> name(pattern.begin(), pattern.end());
        name.push_back('\0');
        const int descriptor = ::mkstemp(name.data());
        if (descriptor < 0) throw std::runtime_error("Could not create private image storage");
        ::close(descriptor);
        return std::shared_ptr<TemporaryFile>(new TemporaryFile(name.data()));
    }

    ~TemporaryFile() {
        std::error_code ignored;
        std::filesystem::remove(path_, ignored);
    }

    FileHandle openForWriting() const {
        const int descriptor = ::open(path_.c_str(), O_WRONLY | O_TRUNC | O_CLOEXEC | O_NOFOLLOW);
        if (descriptor < 0) throw std::runtime_error("Could not open private image storage");
        FILE* file = ::fdopen(descriptor, "wb");
        if (!file) {
            ::close(descriptor);
            throw std::runtime_error("Could not open private image storage");
        }
        return FileHandle(file);
    }

    int openForReading() const {
        const int descriptor = ::open(path_.c_str(), O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
        if (descriptor < 0) throw std::runtime_error("Could not read private image storage");
        return descriptor;
    }

    uint64_t size() const {
        return std::filesystem::file_size(path_);
    }

    void pipe(Pipeline* pipeline) const {
        checkPDFProcessing();
        QUtil::pipe_file(path_.c_str(), pipeline);
        checkPDFProcessing();
    }

    const std::string& path() const { return path_; }

private:
    explicit TemporaryFile(std::string path) : path_(std::move(path)) {}
    std::string path_;
};

class TemporaryFilePipeline final : public Pipeline {
public:
    explicit TemporaryFilePipeline(FILE* file) : Pipeline("private image PDF", nullptr), file_(file) {}
    void write(const unsigned char* data, size_t count) override {
        checkPDFProcessing();
        if (std::fwrite(data, 1, count, file_) != count)
            throw std::runtime_error("Could not write private image storage");
    }
    void finish() override { checkPDFProcessing(); }
private:
    FILE* file_;
};

class PDFImageRows {
public:
    PDFImageRows(Object image, Object colorSpace, bool preserveAlpha)
        : preserveAlpha_(preserveAlpha) {
        if (!image.isStream()) throw std::runtime_error("Invalid PDF image");
        auto source = image.getDict();
        auto embeddedAlpha = source.getKey("/SMaskInData");
        if (!embeddedAlpha.isNull() && (!embeddedAlpha.isInteger() || embeddedAlpha.getIntValue() != 0))
            throw PDFProcessingUnsupported("Embedded JPEG 2000 alpha requires a separate alpha conversion");
        width_ = source.getKey("/Width").getIntValueAsInt();
        height_ = source.getKey("/Height").getIntValueAsInt();
        dimensions(width_, height_);

        // A private image-only PDF lets PDFium apply Decode arrays, palettes,
        // ICC profiles and tint functions without rasterizing a document page.
        QPDF wrapper;
        wrapper.emptyPDF();
        auto copied = wrapper.copyForeignObject(image);
        if (!colorSpace.isNull()) {
            if (!colorSpace.isIndirect()) colorSpace = image.getOwningQPDF()->makeIndirectObject(colorSpace);
            copied.getDict().replaceKey("/ColorSpace", wrapper.copyForeignObject(colorSpace));
        }
        if (!preserveAlpha_) {
            copied.getDict().removeKey("/SMask");
            copied.getDict().removeKey("/Mask");
        }
        auto pageObject = wrapper.makeIndirectObject(Object::parse("<< /Type /Page /MediaBox [0 0 1 1] >>"));
        pageObject.replaceKey("/Resources", Object::newDictionary({{"/XObject", Object::newDictionary({{"/Image", copied}})}}));
        pageObject.replaceKey("/Contents", wrapper.newStream("/Image Do\n"));
        QPDFPageDocumentHelper(wrapper).addPage(QPDFPageObjectHelper(pageObject), false);

        storage_ = TemporaryFile::create();
        auto file = storage_->openForWriting();
        TemporaryFilePipeline pipeline(file.get());
        QPDFWriter writer(wrapper);
        writer.setOutputPipeline(&pipeline);
        writer.setPreserveEncryption(false);
        writer.write();
        if (std::fflush(file.get()) || std::ferror(file.get()))
            throw std::runtime_error("Could not finish private image storage");
        file.reset();

        ensureLibrary();
        document_.reset(FPDF_LoadDocument(storage_->path().c_str(), nullptr));
        if (!document_) throw std::runtime_error("The PDF image could not be decoded");
        page_.reset(FPDF_LoadPage(document_.get(), 0));
        if (!page_ || FPDFPage_CountObjects(page_.get()) != 1)
            throw std::runtime_error("The PDF image could not be decoded");
        auto* pageObjectHandle = CPDFPageObjectFromFPDFPageObject(FPDFPage_GetObject(page_.get(), 0));
        auto* imageObject = pageObjectHandle ? pageObjectHandle->AsImage() : nullptr;
        if (!imageObject || !imageObject->GetImage())
            throw std::runtime_error("The PDF image could not be decoded");
        dib_ = imageObject->GetImage()->LoadDIBBase();
        if (!dib_ || dib_->GetWidth() != width_ || dib_->GetHeight() != height_)
            throw std::runtime_error("The decoded PDF image has unexpected dimensions");
    }

    int width() const { return width_; }
    int height() const { return height_; }

    void readRGB(int rowNumber, std::span<uint8_t> target) const {
        if (rowNumber < 0 || rowNumber >= height_ || target.size() != size_t(width_) * 3)
            throw std::runtime_error("Invalid decoded PDF image row");
        const auto source = dib_->GetScanline(rowNumber);
        const auto palette = [&](unsigned index) {
            if (dib_->HasPalette()) return dib_->GetPaletteArgb(static_cast<int>(index));
            const unsigned sample = dib_->GetBPP() == 1 ? (index ? 255u : 0u) : index;
            return 0xff000000u | sample << 16 | sample << 8 | sample;
        };
        for (int x = 0; x < width_; ++x) {
            uint8_t red = 0, green = 0, blue = 0;
            switch (dib_->GetFormat()) {
            case FXDIB_Format::k1bppRgb:
            case FXDIB_Format::k1bppMask: {
                if (source.size() <= size_t(x / 8)) throw std::runtime_error("Invalid decoded PDF image samples");
                const auto argb = palette((source[x / 8] >> (7 - x % 8)) & 1);
                red = uint8_t(argb >> 16); green = uint8_t(argb >> 8); blue = uint8_t(argb);
                break;
            }
            case FXDIB_Format::k8bppRgb:
            case FXDIB_Format::k8bppMask: {
                if (source.size() <= size_t(x)) throw std::runtime_error("Invalid decoded PDF image samples");
                const auto argb = palette(source[x]);
                red = uint8_t(argb >> 16); green = uint8_t(argb >> 8); blue = uint8_t(argb);
                break;
            }
            case FXDIB_Format::kBgr:
                if (source.size() < size_t(width_) * 3) throw std::runtime_error("Invalid decoded PDF image samples");
                blue = source[size_t(x) * 3]; green = source[size_t(x) * 3 + 1]; red = source[size_t(x) * 3 + 2];
                break;
            case FXDIB_Format::kBgrx:
            case FXDIB_Format::kBgra:
                if (source.size() < size_t(width_) * 4) throw std::runtime_error("Invalid decoded PDF image samples");
                blue = source[size_t(x) * 4]; green = source[size_t(x) * 4 + 1]; red = source[size_t(x) * 4 + 2];
                break;
            default:
                throw std::runtime_error("The PDF image uses an unsupported sample format");
            }
            target[size_t(x) * 3] = red;
            target[size_t(x) * 3 + 1] = green;
            target[size_t(x) * 3 + 2] = blue;
        }
    }

    void readBGRA(int rowNumber, std::span<uint8_t> target) const {
        if (target.size() != size_t(width_) * 4) throw std::runtime_error("Invalid decoded PDF image row");
        std::vector<uint8_t> rgb(size_t(width_) * 3);
        readRGB(rowNumber, rgb);
        const auto source = dib_->GetScanline(rowNumber);
        for (int x = 0; x < width_; ++x) {
            target[size_t(x) * 4] = rgb[size_t(x) * 3 + 2];
            target[size_t(x) * 4 + 1] = rgb[size_t(x) * 3 + 1];
            target[size_t(x) * 4 + 2] = rgb[size_t(x) * 3];
            target[size_t(x) * 4 + 3] = preserveAlpha_ && dib_->GetFormat() == FXDIB_Format::kBgra
                ? source[size_t(x) * 4 + 3] : 255;
        }
    }

private:
    bool preserveAlpha_;
    int width_ = 0;
    int height_ = 0;
    std::shared_ptr<TemporaryFile> storage_;
    std::unique_ptr<std::remove_pointer_t<FPDF_DOCUMENT>, decltype(&FPDF_CloseDocument)>
        document_{nullptr, FPDF_CloseDocument};
    std::unique_ptr<std::remove_pointer_t<FPDF_PAGE>, decltype(&FPDF_ClosePage)>
        page_{nullptr, FPDF_ClosePage};
    RetainPtr<CFX_DIBBase> dib_;
};

struct JpegliError {
    jpeg_error_mgr manager{};
    jmp_buf jump{};
};

void jpegliErrorExit(j_common_ptr common) {
    auto* error = reinterpret_cast<JpegliError*>(common->err);
    longjmp(error->jump, 1);
}

class JpegliEncoder {
public:
    JpegliEncoder(FILE* file, int width, int height, int quality, bool subsampling)
        : width_(width), height_(height) {
        std::memset(&compression_, 0, sizeof(compression_));
        compression_.err = jpegli_std_error(&error_.manager);
        error_.manager.error_exit = jpegliErrorExit;
        if (setjmp(error_.jump)) fail();
        jpegli_CreateCompress(&compression_, JPEG_LIB_VERSION, sizeof(jpeg_compress_struct));
        created_ = true;
        jpegli_stdio_dest(&compression_, file);
        compression_.image_width = static_cast<JDIMENSION>(width);
        compression_.image_height = static_cast<JDIMENSION>(height);
        compression_.input_components = 3;
        compression_.in_color_space = JCS_RGB;
        jpegli_set_defaults(&compression_);
        jpegli_set_quality(&compression_, quality, TRUE);
        if (subsampling) {
            compression_.comp_info[0].h_samp_factor = 2;
            compression_.comp_info[0].v_samp_factor = 2;
            compression_.comp_info[1].h_samp_factor = compression_.comp_info[1].v_samp_factor = 1;
            compression_.comp_info[2].h_samp_factor = compression_.comp_info[2].v_samp_factor = 1;
        }
        // PDF readers receive the complete image stream. A sequential JPEG
        // avoids jpegli's full-image progressive coefficient allocation.
        jpegli_set_progressive_level(&compression_, 0);
        compression_.optimize_coding = FALSE;
        compression_.write_JFIF_header = FALSE;
        compression_.write_Adobe_marker = FALSE;
        jpegli_start_compress(&compression_, TRUE);
    }

    ~JpegliEncoder() { if (created_) jpegli_destroy_compress(&compression_); }

    void write(std::span<const uint8_t> row) {
        if (finished_ || row.size() != size_t(width_) * 3 || compression_.next_scanline >= compression_.image_height)
            throw std::runtime_error("Invalid PDF JPEG row");
        if (setjmp(error_.jump)) fail();
        JSAMPROW pointer = const_cast<JSAMPROW>(row.data());
        if (jpegli_write_scanlines(&compression_, &pointer, 1) != 1)
            throw std::runtime_error("The PDF image could not be JPEG encoded");
    }

    void finish() {
        if (finished_ || compression_.next_scanline != compression_.image_height)
            throw std::runtime_error("Incomplete PDF JPEG image");
        if (setjmp(error_.jump)) fail();
        jpegli_finish_compress(&compression_);
        finished_ = true;
    }

private:
    [[noreturn]] void fail() {
        if (created_ || compression_.mem) jpegli_destroy_compress(&compression_);
        created_ = false;
        throw std::runtime_error("The PDF image could not be JPEG encoded");
    }
    int width_;
    int height_;
    jpeg_compress_struct compression_{};
    JpegliError error_{};
    bool created_ = false;
    bool finished_ = false;
};

class FlateEncoder {
public:
    explicit FlateEncoder(FILE* file) : file_(file) {
        if (deflateInit(&stream_, Z_BEST_COMPRESSION) != Z_OK)
            throw std::runtime_error("Could not initialize PDF sample compression");
        initialized_ = true;
    }
    ~FlateEncoder() { if (initialized_) deflateEnd(&stream_); }

    void write(std::span<const uint8_t> bytes) {
        stream_.next_in = const_cast<Bytef*>(reinterpret_cast<const Bytef*>(bytes.data()));
        stream_.avail_in = static_cast<uInt>(bytes.size());
        while (stream_.avail_in) pump(Z_NO_FLUSH);
    }

    void finish() {
        int status;
        do { status = pump(Z_FINISH); } while (status == Z_OK);
        if (status != Z_STREAM_END) throw std::runtime_error("Could not finish PDF sample compression");
        deflateEnd(&stream_);
        initialized_ = false;
    }

private:
    int pump(int flush) {
        stream_.next_out = buffer_.data();
        stream_.avail_out = static_cast<uInt>(buffer_.size());
        const int status = deflate(&stream_, flush);
        const size_t produced = buffer_.size() - stream_.avail_out;
        if (produced && std::fwrite(buffer_.data(), 1, produced, file_) != produced)
            throw std::runtime_error("Could not write compressed PDF samples");
        if (status != Z_OK && status != Z_STREAM_END)
            throw std::runtime_error("Could not compress PDF samples");
        return status;
    }
    FILE* file_;
    z_stream stream_{};
    std::array<uint8_t, 16384> buffer_{};
    bool initialized_ = false;
};

class LosslessSampler {
public:
    LosslessSampler(int width, int height)
        : width_(width), always_(uint64_t(width) * height <= 65536),
          step_(std::max<uint64_t>(1, uint64_t(width) * height / 32768)) {}

    bool consider(int rowNumber, std::span<const uint8_t> row) {
        if (always_ || !viable_) return viable_;
        const uint64_t first = uint64_t(rowNumber) * width_;
        const uint64_t end = first + width_;
        while (next_ < end) {
            if (next_ >= first) {
                const size_t offset = size_t(next_ - first) * 3;
                colors_.insert(uint32_t(row[offset]) << 16 |
                               uint32_t(row[offset + 1]) << 8 | row[offset + 2]);
                if (colors_.size() > 256) return viable_ = false;
            }
            next_ += step_;
        }
        return true;
    }

private:
    uint64_t width_;
    bool always_;
    uint64_t step_;
    uint64_t next_ = 0;
    bool viable_ = true;
    std::set<uint32_t> colors_;
};

struct EncodedColorImage {
    std::shared_ptr<TemporaryFile> storage;
    std::string filter;
};

std::shared_ptr<TemporaryFile> encodeCleanBitmap(
    const PDFImageRows& rows, int targetWidth, int targetHeight,
    const PDFCompressionPolicy& policy, const PDFPaperCleanup& cleanup,
    bool excludeColor) {
    auto storage = TemporaryFile::create();
    auto file = storage->openForWriting();
    const size_t rowBytes = (size_t(targetWidth) + 7) / 8;
    std::vector<uint8_t> bits(rowBytes);
    std::vector<uint8_t> adjusted(size_t(targetWidth) * 3);
    {
        PDFGroup4Encoder encoder(file.get(), targetWidth);
        resamplePDFRGB(rows.width(), rows.height(), targetWidth, targetHeight, 0,
            [&](int row, std::span<uint8_t> output) { rows.readRGB(row, output); },
            [&](int row, std::span<const uint8_t> input) {
                std::copy(input.begin(), input.end(), adjusted.begin());
                cleanup.normalizeRow(row, targetWidth, targetHeight, adjusted);
                std::fill(bits.begin(), bits.end(), 0xff);
                for (int x = 0; x < targetWidth; ++x) {
                    const auto* pixel = adjusted.data() + size_t(x) * 3;
                    const bool black = excludeColor
                        ? cleanup.isForeground(x, row, targetWidth, targetHeight,
                                               pixel[0], pixel[1], pixel[2])
                        : policy.blackPixel(pixel[0], pixel[1], pixel[2]);
                    if ((!excludeColor || !cleanup.retainsColor(x, row, targetWidth, targetHeight)) && black)
                        bits[x / 8] &= uint8_t(~(0x80 >> (x % 8)));
                }
                encoder.write(bits);
            }, [] { checkPDFProcessing(); });
        encoder.finish();
    }
    if (std::fflush(file.get()) || std::ferror(file.get()))
        throw std::runtime_error("Could not write compressed PDF bitmap");
    file.reset();
    return storage;
}

EncodedColorImage encodeCleanColor(
    const PDFImageRows& rows, int targetWidth, int targetHeight,
    const PDFCompressionPolicy& policy, const PDFPaperCleanup& cleanup,
    bool sparse) {
    auto jpegFile = TemporaryFile::create();
    auto jpegOutput = jpegFile->openForWriting();
    auto flateFile = TemporaryFile::create();
    auto flateOutput = flateFile->openForWriting();
    LosslessSampler sampler(targetWidth, targetHeight);
    std::vector<uint8_t> adjusted(size_t(targetWidth) * 3);
    {
        JpegliEncoder jpeg(jpegOutput.get(), targetWidth, targetHeight,
                           policy.jpegQuality(), false);
        auto flate = std::make_unique<FlateEncoder>(flateOutput.get());
        resamplePDFRGB(rows.width(), rows.height(), targetWidth, targetHeight, 0,
            [&](int row, std::span<uint8_t> output) { rows.readRGB(row, output); },
            [&](int row, std::span<const uint8_t> input) {
                std::copy(input.begin(), input.end(), adjusted.begin());
                cleanup.normalizeRow(row, targetWidth, targetHeight, adjusted);
                applyPDFRGBContrast(adjusted, policy.contrast);
                if (sparse) {
                    for (int x = 0; x < targetWidth; ++x) {
                        if (!cleanup.retainsColor(x, row, targetWidth, targetHeight))
                            std::fill_n(adjusted.begin() + size_t(x) * 3, 3, uint8_t(255));
                    }
                }
                jpeg.write(adjusted);
                if (flate) {
                    if (sampler.consider(row, adjusted)) flate->write(adjusted);
                    else {
                        flate.reset();
                        flateOutput.reset();
                        flateFile.reset();
                    }
                }
            }, [] { checkPDFProcessing(); });
        jpeg.finish();
        if (flate) flate->finish();
    }
    if (std::fflush(jpegOutput.get()) || std::ferror(jpegOutput.get()))
        throw std::runtime_error("Could not finish compressed PDF image");
    jpegOutput.reset();
    if (flateOutput) {
        if (std::fflush(flateOutput.get()) || std::ferror(flateOutput.get()))
            throw std::runtime_error("Could not finish compressed PDF samples");
        flateOutput.reset();
    }
    if (!jpegFile->size()) throw std::runtime_error("The PDF image could not be JPEG encoded");
    if (flateFile && flateFile->size() <= jpegFile->size())
        return {std::move(flateFile), "/FlateDecode"};
    return {std::move(jpegFile), "/DCTDecode"};
}

void installEncodedImage(Object image, const std::shared_ptr<TemporaryFile>& storage,
                         const std::string& filter, int width, int height,
                         bool monochrome, bool transparentWhite,
                         bool preserveDictionary) {
    auto dictionary = preserveDictionary ? image.getDict() : Object::newDictionary();
    dictionary.replaceKey("/Type", Object::newName("/XObject"));
    dictionary.replaceKey("/Subtype", Object::newName("/Image"));
    dictionary.replaceKey("/Width", Object::newInteger(width));
    dictionary.replaceKey("/Height", Object::newInteger(height));
    dictionary.replaceKey("/BitsPerComponent", Object::newInteger(monochrome ? 1 : 8));
    dictionary.replaceKey("/ColorSpace", Object::newName(monochrome ? "/DeviceGray" : "/DeviceRGB"));
    for (const char* key : {"/Decode", "/SMaskInData", "/Intent"}) dictionary.removeKey(key);
    if (transparentWhite)
        dictionary.replaceKey("/Mask", Object::newArray({Object::newInteger(1), Object::newInteger(1)}));
    Object parameters = Object::newNull();
    if (monochrome)
        parameters = Object::newDictionary({{"/K", Object::newInteger(-1)},
            {"/Columns", Object::newInteger(width)}, {"/Rows", Object::newInteger(height)}});
    image.replaceDict(dictionary);
    image.replaceStreamData([storage](Pipeline* pipeline) { storage->pipe(pipeline); },
                            Object::newName(filter), parameters);
    image.setFilterOnWrite(false);
}

void installHybridImage(Object image, const EncodedColorImage& color,
                        const std::shared_ptr<TemporaryFile>& black,
                        int colorWidth, int colorHeight,
                        int blackWidth, int blackHeight) {
    auto* owner = image.getOwningQPDF();
    if (!owner) throw std::runtime_error("PDF image has no owning document");
    auto colorImage = owner->newStream("");
    installEncodedImage(colorImage, color.storage, color.filter,
                        colorWidth, colorHeight, false, false, false);
    auto blackImage = owner->newStream("");
    installEncodedImage(blackImage, black, "/CCITTFaxDecode",
                        blackWidth, blackHeight, true, true, false);

    auto original = image.getDict();
    auto xObjects = Object::newDictionary({{"/Color", colorImage}, {"/Black", blackImage}});
    auto dictionary = Object::newDictionary({
        {"/Type", Object::newName("/XObject")},
        {"/Subtype", Object::newName("/Form")},
        {"/FormType", Object::newInteger(1)},
        {"/BBox", Object::newArray({Object::newInteger(0), Object::newInteger(0),
                                      Object::newInteger(1), Object::newInteger(1)})},
        {"/Resources", Object::newDictionary({{"/XObject", xObjects}})}
    });
    for (const char* key : {"/OC", "/StructParent", "/StructParents"})
        if (original.hasKey(key)) dictionary.replaceKey(key, original.getKey(key));
    image.replaceDict(dictionary);
    image.replaceStreamData("q /Color Do Q\nq /Black Do Q\n",
                            Object::newNull(), Object::newNull());
    image.setFilterOnWrite(true);
}

} // namespace

PDFDecodedImage decodePDFImage(Object image, Object colorSpace, bool preserveAlpha) {
    PDFImageRows rows(image, colorSpace, preserveAlpha);
    PDFDecodedImage result{rows.width(), rows.height(),
                           std::vector<uint8_t>(size_t(rows.width()) * rows.height() * 4)};
    for (int y = 0; y < rows.height(); ++y) {
        checkPDFProcessing();
        rows.readBGRA(y, std::span(result.pixels).subspan(size_t(y) * rows.width() * 4,
                                                         size_t(rows.width()) * 4));
    }
    return result;
}

void recompressPDFImage(Object image, Object colorSpace, int targetWidth, int targetHeight,
                        const PDFCompressionPolicy& policy) {
    recompressPDFImage(image, colorSpace, targetWidth, targetHeight,
                       targetWidth, targetHeight, policy);
}

void recompressPDFImage(Object image, Object colorSpace,
                        int targetWidth, int targetHeight,
                        int selectorWidth, int selectorHeight,
                        const PDFCompressionPolicy& policy) {
    policy.validate();
    dimensions(targetWidth, targetHeight);
    dimensions(selectorWidth, selectorHeight);
    PDFImageRows rows(image, colorSpace, false);
    if (targetWidth > rows.width() || targetHeight > rows.height() ||
        selectorWidth > rows.width() || selectorHeight > rows.height())
        throw std::runtime_error("Invalid PDF image resampling dimensions");

    if (policy.paperCleanup > 0) {
        const auto cleanup = PDFPaperCleanup::analyze(
            rows.width(), rows.height(),
            [&](int row, std::span<uint8_t> output) { rows.readRGB(row, output); },
            policy);
        if (policy.monochrome) {
            auto encoded = encodeCleanBitmap(rows, targetWidth, targetHeight,
                                             policy, cleanup, false);
            installEncodedImage(image, encoded, "/CCITTFaxDecode", targetWidth,
                                targetHeight, true, false, true);
            return;
        }

        const bool hasIndependentMask = image.getDict().hasKey("/SMask") ||
                                        image.getDict().hasKey("/Mask");
        const bool separatesContent = cleanup.neutralBlackCoverage() >= 0.0005 &&
                                      cleanup.colorCoverage() < 0.98;
        if (!hasIndependentMask && separatesContent) {
            auto black = encodeCleanBitmap(rows, selectorWidth, selectorHeight,
                                           policy, cleanup, true);
            if (cleanup.colorCoverage() == 0) {
                installEncodedImage(image, black, "/CCITTFaxDecode", selectorWidth,
                                    selectorHeight, true, false, true);
            } else {
                auto color = encodeCleanColor(rows, targetWidth, targetHeight,
                                              policy, cleanup, true);
                installHybridImage(image, color, black, targetWidth, targetHeight,
                                   selectorWidth, selectorHeight);
            }
            return;
        }

        auto color = encodeCleanColor(rows, targetWidth, targetHeight,
                                      policy, cleanup, false);
        installEncodedImage(image, color.storage, color.filter, targetWidth,
                            targetHeight, false, false, true);
        return;
    }

    std::shared_ptr<TemporaryFile> selected;
    const char* encoding = nullptr;
    Object parameters = Object::newNull();
    if (policy.monochrome) {
        selected = TemporaryFile::create();
        auto file = selected->openForWriting();
        const size_t rowBytes = (size_t(targetWidth) + 7) / 8;
        std::vector<uint8_t> bits(rowBytes);
        {
            PDFGroup4Encoder encoder(file.get(), targetWidth);
            resamplePDFRGB(rows.width(), rows.height(), targetWidth, targetHeight, 0,
                [&](int row, std::span<uint8_t> output) { rows.readRGB(row, output); },
                [&](int, std::span<const uint8_t> input) {
                    std::fill(bits.begin(), bits.end(), 0xff);
                    for (int x = 0; x < targetWidth; ++x) {
                        const auto* pixel = input.data() + size_t(x) * 3;
                        if (policy.blackPixel(pixel[0], pixel[1], pixel[2]))
                            bits[x / 8] &= uint8_t(~(0x80 >> (x % 8)));
                    }
                    encoder.write(bits);
                }, [] { checkPDFProcessing(); });
            encoder.finish();
        }
        if (std::fflush(file.get()) || std::ferror(file.get()))
            throw std::runtime_error("Could not write compressed PDF bitmap");
        file.reset();
        encoding = "/CCITTFaxDecode";
        parameters = Object::newDictionary({{"/K", Object::newInteger(-1)},
            {"/Columns", Object::newInteger(targetWidth)}, {"/Rows", Object::newInteger(targetHeight)}});
    } else {
        auto jpegFile = TemporaryFile::create();
        auto jpegOutput = jpegFile->openForWriting();
        auto flateFile = TemporaryFile::create();
        auto flateOutput = flateFile->openForWriting();
        LosslessSampler sampler(targetWidth, targetHeight);
        {
            JpegliEncoder jpeg(jpegOutput.get(), targetWidth, targetHeight, policy.jpegQuality(), false);
            auto flate = std::make_unique<FlateEncoder>(flateOutput.get());
            resamplePDFRGB(rows.width(), rows.height(), targetWidth, targetHeight, policy.contrast,
                [&](int row, std::span<uint8_t> output) { rows.readRGB(row, output); },
                [&](int row, std::span<const uint8_t> output) {
                    jpeg.write(output);
                    if (flate) {
                        if (sampler.consider(row, output)) flate->write(output);
                        else {
                            flate.reset();
                            flateOutput.reset();
                            flateFile.reset();
                        }
                    }
                }, [] { checkPDFProcessing(); });
            jpeg.finish();
            if (flate) flate->finish();
        }
        if (std::fflush(jpegOutput.get()) || std::ferror(jpegOutput.get()))
            throw std::runtime_error("Could not finish compressed PDF image");
        jpegOutput.reset();
        if (flateOutput) {
            if (std::fflush(flateOutput.get()) || std::ferror(flateOutput.get()))
                throw std::runtime_error("Could not finish compressed PDF samples");
            flateOutput.reset();
        }
        if (!jpegFile->size()) throw std::runtime_error("The PDF image could not be JPEG encoded");
        if (flateFile && flateFile->size() <= jpegFile->size()) {
            selected = std::move(flateFile);
            encoding = "/FlateDecode";
        } else {
            selected = std::move(jpegFile);
            encoding = "/DCTDecode";
        }
    }

    auto dictionary = image.getDict();
    dictionary.replaceKey("/Width", Object::newInteger(targetWidth));
    dictionary.replaceKey("/Height", Object::newInteger(targetHeight));
    dictionary.replaceKey("/BitsPerComponent", Object::newInteger(policy.monochrome ? 1 : 8));
    dictionary.replaceKey("/ColorSpace", Object::newName(policy.monochrome ? "/DeviceGray" : "/DeviceRGB"));
    for (const char* key : {"/Decode", "/SMaskInData", "/Intent"}) dictionary.removeKey(key);
    image.replaceStreamData([selected](Pipeline* pipeline) { selected->pipe(pipeline); },
                            Object::newName(encoding), parameters);
    image.setFilterOnWrite(false);
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
