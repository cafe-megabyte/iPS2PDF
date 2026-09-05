#include "PDFImageCodecSmoke.h"
#include "PDFImageCodec.h"
#include "PDFContentProgram.h"
#include <qpdf/QPDFPageDocumentHelper.hh>
#include <qpdf/QPDFWriter.hh>
#include <iostream>
#include <stdexcept>

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
        ips2pdf::PDFCompressionPolicy policy;
        policy.threshold = threshold;
        auto ccitt = ips2pdf::encodePDFGroup4(decoded, policy);
        QPDF result;
        result.emptyPDF();
        auto encoded = result.newStream(std::string(ccitt.begin(), ccitt.end()));
        encoded.replaceDict(Object::parse("<< /Type /XObject /Subtype /Image /Width 33 /Height 17 /BitsPerComponent 1 /ColorSpace /DeviceGray /Filter /CCITTFaxDecode /DecodeParms << /K -1 /Columns 33 /Rows 17 >> >>"));
        const auto roundTrip = ips2pdf::decodePDFImage(encoded, Object::newNull());
        for (int y = 0; y < 17; ++y) for (int x = 0; x < 33; ++x) {
            const int expected = threshold == 0 || x >= 22 ? 255 : 0;
            require(roundTrip.pixels[(y * 33 + x) * 4] == expected, "CCITT threshold, polarity or row alignment changed");
        }
        save(result, encoded, output / ("CodecGroup4-" + std::to_string(threshold) + ".pdf"));
    }
    const auto resized = ips2pdf::resizePDFImage(decoded, 16, 8);
    require(resized.width == 16 && resized.height == 8 && decoded.width == 33, "Resampling changed its input");
    auto jpeg = ips2pdf::encodePDFJPEG(resized, 94, false);
    QPDF result;
    result.emptyPDF();
    auto encoded = result.newStream(std::string(jpeg.begin(), jpeg.end()));
    encoded.replaceDict(Object::parse("<< /Type /XObject /Subtype /Image /Width 16 /Height 8 /BitsPerComponent 8 /ColorSpace /DeviceRGB /Filter /DCTDecode >>"));
    const auto reopened = ips2pdf::decodePDFImage(encoded, Object::newNull());
    require(reopened.width == 16 && reopened.height == 8, "jpegli output did not reopen");
    save(result, encoded, output / "CodecJPEG.pdf");
    std::cout << "PASS image codecs: native-size decode, high-quality downsampling, jpegli, true one-bit CCITT Group 4, odd rows and threshold endpoints\n";
}
