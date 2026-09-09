#include "PDFImageCodecSmoke.h"
#include "PDFImageCodec.h"
#include "PDFImageResampler.h"
#include "PDFContentProgram.h"
#include <qpdf/QPDFPageDocumentHelper.hh>
#include <qpdf/QPDFWriter.hh>
#include <algorithm>
#include <array>
#include <cmath>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
using Object = QPDFObjectHandle;
void require(bool good, const char* message) { if (!good) throw std::runtime_error(message); }
void save(QPDF& pdf, Object image, const std::filesystem::path& file) {
    auto page = pdf.makeIndirectObject(Object::parse("<< /Type /Page /MediaBox [0 0 330 170] >>"));
    page.replaceKey("/Resources", Object::newDictionary({{"/XObject", Object::newDictionary({{"/Image", image}})}}));
    page.replaceKey("/Contents", pdf.newStream("330 0 0 170 0 0 cm /Image Do\n"));
    QPDFPageDocumentHelper(pdf).addPage(QPDFPageObjectHelper(page), false);
    QPDFWriter writer(pdf, file.c_str()); writer.write();
}
} // namespace

void runImageCodecSmoke(const std::filesystem::path& output) {
    QPDF pdf;
    pdf.emptyPDF();
    {
        ips2pdf::PDFColorConverter color(pdf, Object::newName("/DeviceRGB"));
        const auto rgb = color.rgb({0.125, 0.5, 1});
        require(rgb[0] == 0.125 && rgb[1] == 0.5 && rgb[2] == 1, "Vector RGB precision changed");
        ips2pdf::PDFColorConverter gray(pdf, Object::newName("/DeviceGray"));
        require(gray.rgb({0.5}) == std::array<double, 3>{0.5, 0.5, 0.5}, "Gray color conversion changed");
        ips2pdf::PDFColorConverter spot(pdf, Object::parse("[/Separation /ExampleSpot /DeviceRGB << /FunctionType 2 /Domain [0 1] /C0 [1 1 1] /C1 [1 0 0] /N 1 >>]"));
        const auto red = spot.rgb({1});
        require(red[0] == 1 && red[1] == 0 && red[2] == 0, "PDF tint transformation was ignored");
        std::cout << "PASS vector color conversion: floating-point RGB/gray and PDF spot-color tint function\n";
    }
    std::string rgb;
    for (int y = 0; y < 17; ++y) for (int x = 0; x < 33; ++x) {
        const uint8_t value = x < 11 ? 0 : x < 22 ? 120 : 255;
        rgb += char(value); rgb += char(value); rgb += char(value);
    }
    auto image = pdf.newStream(rgb);
    auto dictionary = Object::parse("<< /Type /XObject /Subtype /Image /Width 33 /Height 17 /BitsPerComponent 8 /ColorSpace /DeviceRGB >>");
    image.replaceDict(dictionary);
    const auto decoded = ips2pdf::decodePDFImage(image, dictionary.getKey("/ColorSpace"));
    {
        auto form = pdf.newStream("q 33 0 0 17 0 0 cm /Image Do Q\n");
        form.replaceDict(Object::parse("<< /Type /XObject /Subtype /Form /BBox [0 0 33 17] /Matrix [0 2 -3 0 0 0] >>"));
        form.getDict().replaceKey("/Resources", Object::newDictionary({{"/XObject", Object::newDictionary({{"/Image", image}})}}));
        auto page = pdf.makeIndirectObject(Object::parse("<< /Type /Page /MediaBox [0 0 600 600] /UserUnit 2 >>"));
        page.replaceKey("/Resources", Object::newDictionary({{"/XObject", Object::newDictionary({{"/Image", image}, {"/Nested", form}})}}));
        page.replaceKey("/Contents", pdf.newStream("q 16.5 0 0 8.5 0 0 cm /Image Do Q\n/Nested Do\n"));
        QPDFPageDocumentHelper(pdf).addPage(QPDFPageObjectHelper(page), false);
        const auto placements = ips2pdf::pdfImagePlacements(pdf);
        require(placements.at(image.getObjGen()).placements == 2, "Shared/nested image census missed a placement");
        require(std::abs(placements.at(image.getObjGen()).minimumPPI - 12) < 0.001,
                "Image census ignored UserUnit, rotation or the minimum-resolution axis");
        std::cout << "PASS image placement census: shared images, nested form matrices, both axes and UserUnit\n";
    }
    require(decoded.width == 33 && decoded.height == 17, "Image-only decode dimensions changed");
    require(image.getStreamData()->getSize() == rgb.size(), "Image-only decode mutated its source stream");
    for (int threshold : {0, 50, 100}) {
        QPDF result;
        result.emptyPDF();
        auto encoded = result.newStream(rgb);
        encoded.replaceDict(Object::parse("<< /Type /XObject /Subtype /Image /Width 33 /Height 17 /BitsPerComponent 8 /ColorSpace /DeviceRGB >>"));
        ips2pdf::PDFCompressionPolicy policy;
        policy.monochrome = true;
        policy.threshold = threshold;
        ips2pdf::recompressPDFImage(encoded, encoded.getDict().getKey("/ColorSpace"), 33, 17, policy);
        require(encoded.getDict().getKey("/Filter").isNameAndEquals("/CCITTFaxDecode"),
                "Streaming monochrome image did not use CCITT Group 4");
        const auto roundTrip = ips2pdf::decodePDFImage(encoded, Object::newNull());
        for (int y = 0; y < 17; ++y) for (int x = 0; x < 33; ++x) {
            const int expected = threshold == 0 || x >= 22 ? 255 : 0;
            require(roundTrip.pixels[(y * 33 + x) * 4] == expected, "CCITT threshold, polarity or row alignment changed");
        }
        save(result, encoded, output / ("CodecGroup4-" + std::to_string(threshold) + ".pdf"));
    }
    {
        constexpr int width = 257, height = 65;
        std::string patternedRGB(size_t(width) * height * 3, '\0');
        std::vector<bool> expected(size_t(width) * height);
        for (int y = 0; y < height; ++y) for (int x = 0; x < width; ++x) {
            const bool black = (((x / 5 + y / 3) & 1) == 0) != ((x + y * 7) % 19 == 0);
            expected[size_t(y) * width + x] = black;
            std::fill_n(patternedRGB.begin() + (size_t(y) * width + x) * 3, 3,
                        static_cast<char>(black ? 0 : 255));
        }
        QPDF result;
        result.emptyPDF();
        auto encoded = result.newStream(patternedRGB);
        encoded.replaceDict(Object::parse(
            "<< /Type /XObject /Subtype /Image /Width 257 /Height 65 /BitsPerComponent 8 /ColorSpace /DeviceRGB >>"));
        ips2pdf::PDFCompressionPolicy policy;
        policy.monochrome = true;
        policy.threshold = 50;
        ips2pdf::recompressPDFImage(encoded, encoded.getDict().getKey("/ColorSpace"), width, height, policy);
        const auto roundTrip = ips2pdf::decodePDFImage(encoded, Object::newNull());
        for (size_t pixel = 0; pixel < expected.size(); ++pixel) {
            const int wanted = expected[pixel] ? 0 : 255;
            if (roundTrip.pixels[pixel * 4] != wanted)
                throw std::runtime_error(
                    "Streaming CCITT Group 4 changed patterned pixel " +
                    std::to_string(pixel) + " from " + std::to_string(wanted) +
                    " to " + std::to_string(roundTrip.pixels[pixel * 4]));
        }
    }

    {
        const std::array<uint8_t, 16> samples = {
            0, 10, 20, 30, 40, 50, 60, 70,
            80, 90, 100, 110, 120, 130, 140, 150
        };
        std::array<uint8_t, 12> averaged{};
        std::vector<int> requestedRows;
        ips2pdf::resamplePDFRGB(4, 4, 2, 2, 0,
            [&](int row, std::span<uint8_t> values) {
                requestedRows.push_back(row);
                for (int x = 0; x < 4; ++x)
                    std::fill_n(values.begin() + size_t(x) * 3, 3, samples[size_t(row) * 4 + x]);
            },
            [&](int row, std::span<const uint8_t> values) {
                std::copy(values.begin(), values.end(), averaged.begin() + size_t(row) * 6);
            });
        require(averaged == std::array<uint8_t, 12>{25, 25, 25, 45, 45, 45,
                                                    105, 105, 105, 125, 125, 125},
                "Streaming area resampling changed exact pixel averages");
        require(requestedRows == std::vector<int>{0, 1, 2, 3},
                "Streaming area resampling reread or reordered source rows");
    }

    std::vector<uint8_t> resized(16 * 8 * 3), contrasted(33 * 17 * 3);
    const auto sourceRow = [&](int row, std::span<uint8_t> target) {
        for (int x = 0; x < 33; ++x) {
            const auto* source = decoded.pixels.data() + (size_t(row) * 33 + x) * 4;
            target[size_t(x) * 3] = source[2];
            target[size_t(x) * 3 + 1] = source[1];
            target[size_t(x) * 3 + 2] = source[0];
        }
    };
    ips2pdf::resamplePDFRGB(33, 17, 16, 8, 0, sourceRow,
        [&](int row, std::span<const uint8_t> values) {
            std::copy(values.begin(), values.end(), resized.begin() + size_t(row) * 16 * 3);
        });
    require(resized.front() == 0 && resized.back() == 255,
            "Streaming area resampling changed constant image regions");
    ips2pdf::resamplePDFRGB(33, 17, 33, 17, 50, sourceRow,
        [&](int row, std::span<const uint8_t> values) {
            std::copy(values.begin(), values.end(), contrasted.begin() + size_t(row) * 33 * 3);
        });
    require(contrasted[0] == 0 && contrasted[16 * 3] < decoded.pixels[16 * 4 + 2] &&
            contrasted[32 * 3] == 255, "Positive scan contrast did not preserve endpoints and expand luminance");

    QPDF result;
    result.emptyPDF();
    std::string noisyRGB(128 * 128 * 3, '\0');
    uint32_t noise = 123456789;
    for (auto& sample : noisyRGB) {
        noise = noise * 1664525u + 1013904223u;
        sample = static_cast<char>(noise >> 24);
    }
    auto encoded = result.newStream(noisyRGB);
    encoded.replaceDict(Object::parse("<< /Type /XObject /Subtype /Image /Width 128 /Height 128 /BitsPerComponent 8 /ColorSpace /DeviceRGB >>"));
    ips2pdf::PDFCompressionPolicy jpegPolicy;
    jpegPolicy.contrast = 0;
    ips2pdf::recompressPDFImage(encoded, encoded.getDict().getKey("/ColorSpace"), 128, 128, jpegPolicy);
    require(encoded.getDict().getKey("/Filter").isNameAndEquals("/DCTDecode"),
            "Streaming jpegli image did not use sequential JPEG");
    const auto jpeg = encoded.getRawStreamData();
    bool baseline = false, progressive = false;
    for (size_t index = 0; index + 1 < jpeg->getSize(); ++index) {
        baseline |= jpeg->getBuffer()[index] == 0xff && jpeg->getBuffer()[index + 1] == 0xc0;
        progressive |= jpeg->getBuffer()[index] == 0xff && jpeg->getBuffer()[index + 1] == 0xc2;
    }
    require(baseline && !progressive, "jpegli output is not a sequential baseline JPEG");
    const auto reopened = ips2pdf::decodePDFImage(encoded, Object::newNull());
    require(reopened.width == 128 && reopened.height == 128, "jpegli output did not reopen");
    save(result, encoded, output / "CodecJPEG.pdf");
    std::cout << "PASS image codecs: native-size decode, high-quality downsampling, jpegli, true one-bit CCITT Group 4, odd rows and threshold endpoints\n";
}
