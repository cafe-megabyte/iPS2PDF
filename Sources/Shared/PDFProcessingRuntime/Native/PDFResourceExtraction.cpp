#include "PDFResourceExtraction.h"
#include "PDFColorProgram.h"
#include "PDFContentProgram.h"
#include "PDFImageCodec.h"
#include "PDFOpenTypeFont.h"
#include "PDFProcessingControl.h"
#include "PDFStructuralWriter.h"

#include <qpdf/Pl_SHA2.hh>
#include <qpdf/QPDFPageDocumentHelper.hh>
#include <ImageIO/ImageIO.h>
#include <CoreGraphics/CoreGraphics.h>
#include <algorithm>
#include <array>
#include <cstdio>
#include <cstring>
#include <fcntl.h>
#include <functional>
#include <set>
#include <stdexcept>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>

namespace ips2pdf {
namespace {
using Object = QPDFObjectHandle;

std::string fingerprint(const std::shared_ptr<Buffer>& data) {
    Pl_SHA2 digest(256);
    digest.write(data->getBuffer(), data->getSize());
    digest.finish();
    return digest.getHexDigest();
}

void writeBytes(const std::filesystem::path& output, const unsigned char* bytes, size_t count) {
    checkPDFOutputSize(count);
    const int descriptor = ::open(output.c_str(), O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
    if (descriptor < 0) throw std::runtime_error("Could not create the private resource result");
    FILE* file = fdopen(descriptor, "wb");
    if (!file) { close(descriptor); std::filesystem::remove(output); throw std::runtime_error("Could not open the private resource result"); }
    try {
        size_t offset = 0;
        while (offset < count) {
            checkPDFProcessing();
            const size_t amount = std::min<size_t>(count - offset, 1024 * 1024);
            if (fwrite(bytes + offset, 1, amount, file) != amount) throw std::runtime_error("Could not write the resource result");
            offset += amount;
        }
        if (fflush(file) || ferror(file)) throw std::runtime_error("Could not finish the resource result");
        const int closeStatus = fclose(file);
        file = nullptr;
        if (closeStatus) throw std::runtime_error("Could not finish the resource result");
    } catch (...) {
        if (file) fclose(file);
        std::error_code ignored;
        std::filesystem::remove(output, ignored);
        throw;
    }
}

void writeBytes(const std::filesystem::path& output, const std::vector<uint8_t>& bytes) {
    writeBytes(output, bytes.data(), bytes.size());
}

std::vector<uint8_t> type1Container(Object stream, const std::shared_ptr<Buffer>& data) {
    const auto* bytes = data->getBuffer();
    const size_t size = data->getSize();
    if (size >= 2 && bytes[0] == 0x80) return {bytes, bytes + size};
    auto dictionary = stream.getDict();
    std::array<size_t, 3> lengths{};
    for (size_t i = 0; i < lengths.size(); ++i) {
        auto value = dictionary.getKey("/Length" + std::to_string(i + 1));
        if (!value.isInteger() || value.getIntValue() < 0) throw std::runtime_error("Invalid embedded Type 1 font lengths");
        lengths[i] = static_cast<size_t>(value.getIntValue());
    }
    if (lengths[0] > size || lengths[1] > size - lengths[0] || lengths[2] > size - lengths[0] - lengths[1] ||
        lengths[0] + lengths[1] + lengths[2] != size)
        throw std::runtime_error("Invalid embedded Type 1 font lengths");
    std::vector<uint8_t> result;
    result.reserve(size + 20);
    size_t offset = 0;
    auto segment = [&](uint8_t type, size_t length) {
        if (!length) return;
        if (length > UINT32_MAX) throw PDFProcessingStopped(false);
        result.push_back(0x80); result.push_back(type);
        const uint32_t n = static_cast<uint32_t>(length);
        for (unsigned shift : {0u, 8u, 16u, 24u}) result.push_back(static_cast<uint8_t>(n >> shift));
        result.insert(result.end(), bytes + offset, bytes + offset + length);
        offset += length;
    };
    segment(1, lengths[0]); segment(2, lengths[1]); segment(1, lengths[2]);
    result.push_back(0x80); result.push_back(0x03);
    return result;
}

void writePNG(const std::filesystem::path& output, const PDFDecodedImage& image) {
    if (image.width <= 0 || image.height <= 0 || image.pixels.size() != size_t(image.width) * image.height * 4)
        throw std::runtime_error("Invalid decoded image result");
    std::vector<uint8_t> rgba(image.pixels.size());
    for (size_t i = 0; i < image.pixels.size(); i += 4) {
        rgba[i] = image.pixels[i + 2]; rgba[i + 1] = image.pixels[i + 1];
        rgba[i + 2] = image.pixels[i]; rgba[i + 3] = image.pixels[i + 3];
    }
    auto releaseData = [](void*, const void*, size_t) {};
    CGDataProviderRef provider = CGDataProviderCreateWithData(nullptr, rgba.data(), rgba.size(), releaseData);
    CGColorSpaceRef color = CGColorSpaceCreateDeviceRGB();
    const CGBitmapInfo bitmapInfo = CGBitmapInfo(static_cast<uint32_t>(kCGImageAlphaLast) |
                                                 static_cast<uint32_t>(kCGBitmapByteOrder32Big));
    CGImageRef cgImage = provider && color ? CGImageCreate(image.width, image.height, 8, 32, size_t(image.width) * 4,
        color, bitmapInfo, provider, nullptr, false, kCGRenderingIntentDefault) : nullptr;
    if (provider) CGDataProviderRelease(provider);
    if (color) CGColorSpaceRelease(color);
    if (!cgImage) throw std::runtime_error("Could not create the exported image");
    const int descriptor = ::open(output.c_str(), O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
    if (descriptor < 0) { CGImageRelease(cgImage); throw std::runtime_error("Could not create the private image result"); }
    close(descriptor);
    CFURLRef url = CFURLCreateFromFileSystemRepresentation(nullptr,
        reinterpret_cast<const UInt8*>(output.c_str()), output.string().size(), false);
    CGImageDestinationRef destination = url ? CGImageDestinationCreateWithURL(url, CFSTR("public.png"), 1, nullptr) : nullptr;
    if (destination) CGImageDestinationAddImage(destination, cgImage, nullptr);
    const bool success = destination && CGImageDestinationFinalize(destination);
    if (destination) CFRelease(destination);
    if (url) CFRelease(url);
    CGImageRelease(cgImage);
    checkPDFProcessing();
    if (!success) { std::filesystem::remove(output); throw std::runtime_error("Could not encode the exported image"); }
    checkPDFOutputSize(std::filesystem::file_size(output));
}

template <typename Callback>
void visit(QPDF& pdf, const Callback& callback) {
    std::set<QPDFObjGen> seen;
    bool stopped = false;
    std::function<void(Object, unsigned)> walk = [&](Object object, unsigned depth) {
        if (stopped) return;
        checkPDFProcessing();
        if (depth > 256) throw std::runtime_error("PDF resource hierarchy exceeds the processing limit");
        if (object.isIndirect() && !seen.insert(object.getObjGen()).second) return;
        if (callback(object)) { stopped = true; return; }
        if (object.isArray()) for (auto child : object.getArrayAsVector()) walk(child, depth + 1);
        auto dictionary = object.isStream() ? object.getDict() : object;
        if (dictionary.isDictionary()) for (const auto& key : dictionary.getKeys()) {
            if (key == "/Parent" || key == "/P" || key == "/Pages") continue;
            walk(dictionary.getKey(key), depth + 1);
        }
    };
    walk(pdf.getRoot(), 0);
    for (auto page : QPDFPageDocumentHelper(pdf).getAllPages()) walk(page.getObjectHandle(), 0);
}

struct ImageMatch { Object image, colorSpace; };
std::vector<ImageMatch> matchingImages(QPDF& pdf, const std::string& wanted, int width, int height, int bits) {
    std::vector<ImageMatch> matches;
    std::set<std::pair<QPDFObjGen, std::string>> seen;
    std::function<void(Object, Object, unsigned)> walk = [&](Object object, Object resources, unsigned depth) {
        checkPDFProcessing();
        if (depth > 256) throw std::runtime_error("PDF image hierarchy exceeds the processing limit");
        auto dictionary = object.isStream() ? object.getDict() : object;
        if (dictionary.isDictionary() && dictionary.getKey("/Resources").isDictionary()) resources = dictionary.getKey("/Resources");
        if (object.isIndirect() && !seen.emplace(object.getObjGen(), resources.unparse()).second) return;
        if (object.isStream() && dictionary.getKey("/Subtype").isNameAndEquals("/Image")) {
            auto data = object.getStreamData(qpdf_dl_generalized);
            auto integerMatches = [&](const char* key, int wantedValue) {
                auto value = dictionary.getKey(key);
                return wantedValue <= 0 || value.isInteger() && value.getIntValueAsInt() == wantedValue;
            };
            if (fingerprint(data) == wanted && integerMatches("/Width", width) && integerMatches("/Height", height) && integerMatches("/BitsPerComponent", bits)) {
                auto space = dictionary.getKey("/ColorSpace");
                if (!space.isNull()) space = resolvePDFColorSpace(space, resources);
                matches.push_back({object, space});
            }
        }
        if (object.isArray()) for (auto child : object.getArrayAsVector()) walk(child, resources, depth + 1);
        if (dictionary.isDictionary()) for (const auto& key : dictionary.getKeys()) {
            if (key == "/Parent" || key == "/P" || key == "/Pages") continue;
            walk(dictionary.getKey(key), resources, depth + 1);
        }
    };
    for (auto page : QPDFPageDocumentHelper(pdf).getAllPages()) walk(page.getObjectHandle(), page.getAttribute("/Resources", false), 0);
    walk(pdf.getRoot(), Object::newNull(), 0);
    return matches;
}
} // namespace

std::uintmax_t extractPDFResource(const std::filesystem::path& input,
                                  const std::filesystem::path& output,
                                  const std::string& password,
                                  const std::string& format,
                                  const std::string& wanted,
                                  int width, int height, int bitsPerComponent) {
    auto pdf = openPDFDocument(input, password);
    if (format == "jpeg" || format == "jpeg2000" || format == "png") {
        externalizePDFInlineImages(*pdf);
        auto matches = matchingImages(*pdf, wanted, width, height, bitsPerComponent);
        if (matches.empty()) throw std::runtime_error("The PDF image resource was not found");
        const auto interpretation = matches.front().colorSpace.unparse();
        if (std::any_of(matches.begin() + 1, matches.end(), [&](const auto& item) { return item.colorSpace.unparse() != interpretation; }))
            throw std::runtime_error("The PDF image resource has ambiguous color interpretations");
        if (format == "jpeg" || format == "jpeg2000") {
            auto data = matches.front().image.getStreamData(qpdf_dl_generalized);
            writeBytes(output, data->getBuffer(), data->getSize());
        } else {
            writePNG(output, decodePDFImage(matches.front().image, matches.front().colorSpace, true));
        }
    } else {
        Object found = Object::newNull();
        visit(*pdf, [&](Object object) {
            std::vector<Object> candidates;
            auto dictionary = object.isStream() ? object.getDict() : object;
            if (format == "embeddedFile") {
                if (object.isStream() && dictionary.getKey("/Type").isNameAndEquals("/EmbeddedFile")) candidates.push_back(object);
                // Some producers, including Microsoft Word, omit /Type from the
                // embedded-file stream. The enclosing file specification's /EF
                // dictionary remains the authoritative attachment reference.
                if (dictionary.isDictionary()) {
                    auto embeddedFiles = dictionary.getKey("/EF");
                    if (embeddedFiles.isDictionary()) {
                        for (const char* key : {"/UF", "/F", "/Unix", "/Mac", "/DOS"}) {
                            auto stream = embeddedFiles.getKey(key);
                            if (stream.isStream()) candidates.push_back(stream);
                        }
                    }
                }
            } else if (format == "xml") {
                if (object.isStream() && dictionary.getKey("/Subtype").isNameAndEquals("/XML")) candidates.push_back(object);
            } else if (format == "icc") {
                if (object.isStream()) {
                    auto components = dictionary.getKey("/N");
                    if (components.isInteger() && components.getIntValue() >= 1 && components.getIntValue() <= 15) candidates.push_back(object);
                }
            } else if (dictionary.isDictionary()) {
                for (const char* key : {"/FontFile", "/FontFile2", "/FontFile3"}) {
                    auto stream = dictionary.getKey(key);
                    if (stream.isStream()) candidates.push_back(stream);
                }
            }
            for (auto candidate : candidates) {
                auto data = candidate.getStreamData(qpdf_dl_all);
                if (fingerprint(data) == wanted) { found = candidate; break; }
            }
            return !found.isNull();
        });
        if (found.isNull()) throw std::runtime_error("The PDF resource was not found");
        auto data = found.getStreamData(qpdf_dl_all);
        if (format == "type1") writeBytes(output, type1Container(found, data));
        else if (format == "openType" && data->getSize() >= 4 && data->getBuffer()[0] == 1) {
            const auto font = openTypeContainerForCFF(
                std::span<const uint8_t>(data->getBuffer(), data->getSize()));
            writeBytes(output, font);
        } else writeBytes(output, data->getBuffer(), data->getSize());
    }
    checkPDFProcessing();
    if (pdf->anyWarnings()) { std::filesystem::remove(output); throw std::runtime_error("The PDF resource could not be read safely"); }
    return std::filesystem::file_size(output);
}

} // namespace ips2pdf
