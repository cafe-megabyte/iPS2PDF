#include "PDFCompressionSmoke.h"
#include "PDFStructuralWriter.h"
#include "PDFContentProgram.h"
#include "PDFColorProgram.h"
#include "PDFImageCodec.h"
#include <qpdf/QPDFPageDocumentHelper.hh>
#include <qpdf/QPDFWriter.hh>
#include <third_party/lcms/include/lcms2.h>
#include <algorithm>
#include <iostream>
#include <stdexcept>

namespace {
using Object = QPDFObjectHandle;
namespace fs = std::filesystem;
void require(bool good, const char* message) { if (!good) throw std::runtime_error(message); }
std::string data(Object stream) {
    auto bytes = stream.getStreamData();
    return {reinterpret_cast<const char*>(bytes->getBuffer()), bytes->getSize()};
}
void save(QPDF& pdf, const fs::path& file) { QPDFWriter writer(pdf, file.c_str()); writer.write(); }
std::vector<std::string> fonts(QPDF& pdf) {
    std::vector<std::string> result;
    for (auto object : pdf.getAllObjects()) if (object.isDictionary())
        for (const char* key : {"/FontFile", "/FontFile2", "/FontFile3"}) {
            auto font = object.getKey(key);
            if (font.isStream()) result.push_back(data(font));
        }
    std::sort(result.begin(), result.end());
    return result;
}
std::vector<Object> images(QPDF& pdf) {
    std::vector<Object> result;
    for (auto object : pdf.getAllObjects())
        if (object.isStream() && object.getDict().getKey("/Subtype").isNameAndEquals("/Image")) result.push_back(object);
    return result;
}
void noMetadata(QPDF& pdf) {
    require(pdf.getTrailer().getKey("/Info").isNull(), "Compression retained Info metadata");
    require(pdf.getRoot().getKey("/OutputIntents").isNull(), "Compression retained an output intent");
    for (auto object : pdf.getAllObjects()) {
        auto dictionary = object.isStream() ? object.getDict() : object;
        if (!dictionary.isDictionary()) continue;
        require(!dictionary.hasKey("/Metadata") && !dictionary.hasKey("/PieceInfo"), "Compression retained object metadata");
        require(!dictionary.hasKey("/EF") && !dictionary.hasKey("/AF"), "Compression retained an attachment");
    }
}
Object page(QPDF& pdf, Object image, int points) {
    auto page = pdf.makeIndirectObject(Object::parse("<< /Type /Page /MediaBox [0 0 600 600] >>"));
    page.replaceKey("/Resources", Object::newDictionary({{"/XObject", Object::newDictionary({{"/Image", image}})}}));
    page.replaceKey("/Contents", pdf.newStream("q " + std::to_string(points) + " 0 0 " + std::to_string(points) + " 0 0 cm /Image Do Q\n"));
    QPDFPageDocumentHelper(pdf).addPage(QPDFPageObjectHelper(page), false);
    return page;
}
} // namespace

void runCompressionSmoke(const fs::path& fixtures, const fs::path& output) {
    for (const char* name : {"InfoEmbeddedFull.pdf", "InfoEmbeddedSubset.pdf", "InfoPlain.pdf", "InfoType0.pdf"}) {
        QPDF original; original.processFile((fixtures / name).c_str());
        const auto expected = fonts(original);
        for (int level = 0; level < 3; ++level) {
            ips2pdf::PDFCompressionPolicy policy{static_cast<ips2pdf::PDFCompressionLevel>(level)};
            auto target = output / (std::string("Compression-") + std::to_string(level) + "-" + name);
            fs::remove(target);
            ips2pdf::compressPDF(fixtures / name, target, "", policy);
            QPDF reopened; reopened.processFile(target.c_str());
            require(fonts(reopened) == expected, "Compression changed or removed an embedded font program");
            noMetadata(reopened);
        }
    }
    std::cout << "PASS compression: all three levels preserve decoded embedded font bytes and leave missing fonts unchanged\n";
    {
        auto target = output / "Compression-Inline-Monochrome.pdf";
        fs::remove(target);
        ips2pdf::compressPDF(fixtures / "InfoInlineImage.pdf", target, "", {.monochrome = true});
        QPDF reopened; reopened.processFile(target.c_str());
        auto pictures = images(reopened);
        require(!pictures.empty(), "Inline image was lost");
        for (auto image : pictures) {
            require(image.getDict().getKey("/BitsPerComponent").getIntValue() == 1 &&
                    image.getDict().getKey("/Filter").isNameAndEquals("/CCITTFaxDecode"), "S/W inline image is not true CCITT bitmap data");
        }
    }
    {
        QPDF pdf; pdf.emptyPDF();
        std::string samples;
        for (int y = 0; y < 600; ++y) for (int x = 0; x < 600; ++x) samples.append(3, x % 20 < 10 ? '\0' : '\xff');
        auto image = pdf.newStream(samples);
        image.replaceDict(Object::parse("<< /Type /XObject /Subtype /Image /Width 600 /Height 600 /BitsPerComponent 8 /ColorSpace /DeviceRGB >>"));
        page(pdf, image, 72); page(pdf, image, 288);
        auto source = output / "Compression-Shared-Source.pdf"; save(pdf, source);
        auto full = output / "Compression-Shared-Full.pdf", preview = output / "Compression-Shared-Preview.pdf";
        fs::remove(full); fs::remove(preview);
        ips2pdf::PDFCompressionPolicy policy{ips2pdf::PDFCompressionLevel::strong, true, 50};
        ips2pdf::compressPDF(source, full, "", policy);
        ips2pdf::compressPDF(source, preview, "", policy, 0);
        QPDF a, b; a.processFile(full.c_str()); b.processFile(preview.c_str());
        require(QPDFPageDocumentHelper(a).getAllPages().size() == 2 && QPDFPageDocumentHelper(b).getAllPages().size() == 1,
                "The page preview changed the full document's page count");
        auto left = images(a), right = images(b);
        require(left.size() == 1 && right.size() == 1, "Shared image unexpectedly duplicated");
        require(left[0].getDict().getKey("/Width").getIntValue() == 600 && right[0].getDict().getKey("/Width").getIntValue() == 600,
                "Preview ignored the largest placement elsewhere in the PDF");
        auto x = left[0].getRawStreamData(), y = right[0].getRawStreamData();
        require(x->getSize() == y->getSize() && std::equal(x->getBuffer(), x->getBuffer() + x->getSize(), y->getBuffer()),
                "Page preview and full compression produced different image data");
    }
    std::cout << "PASS compression: inline images, CCITT output and page previews using the full document's minimum image resolution\n";
    {
        QPDF pdf; pdf.emptyPDF();
        std::string samples;
        samples.reserve(900 * 900 * 3);
        for (int y = 0; y < 900; ++y) for (int x = 0; x < 900; ++x) {
            samples.push_back(static_cast<char>((x * 17 + y * 13) % 256));
            samples.push_back(static_cast<char>((x * 7 + y * 23) % 256));
            samples.push_back(static_cast<char>((x * 29 + y * 3) % 256));
        }
        auto image = pdf.newStream(samples);
        image.replaceDict(Object::parse("<< /Type /XObject /Subtype /Image /Width 900 /Height 900 /BitsPerComponent 8 /ColorSpace /DeviceRGB >>"));
        page(pdf, image, 288);
        auto source = output / "Compression-Color-Source.pdf";
        save(pdf, source);
        const int expectedWidths[] = {900, 560, 440};
        for (int level = 0; level < 3; ++level) {
            auto target = output / ("Compression-Color-" + std::to_string(level) + ".pdf");
            fs::remove(target);
            ips2pdf::PDFCompressionPolicy policy{static_cast<ips2pdf::PDFCompressionLevel>(level)};
            ips2pdf::compressPDF(source, target, "", policy);
            QPDF reopened; reopened.processFile(target.c_str());
            auto pictures = images(reopened);
            require(pictures.size() == 1, "Color compression changed the number of images");
            require(pictures[0].getDict().getKey("/Width").getIntValue() == expectedWidths[level],
                    "Color compression did not apply the selected target resolution");
            require(pictures[0].getDict().getKey("/Filter").isNameAndEquals("/DCTDecode"),
                    "Color scan was not stored as JPEG");
        }
    }
    std::cout << "PASS compression: color levels use 225, 140 and 110 ppi and store scans as JPEG\n";
    {
        QPDF pdf; pdf.emptyPDF();
        const auto makeImage = [&](int width, unsigned seed) {
            std::string samples;
            samples.reserve(size_t(width) * width * 3);
            for (int y = 0; y < width; ++y) for (int x = 0; x < width; ++x) {
                samples.push_back(static_cast<char>((x * 17 + y * 13 + seed) % 256));
                samples.push_back(static_cast<char>((x * 7 + y * 23 + seed) % 256));
                samples.push_back(static_cast<char>((x * 29 + y * 3 + seed) % 256));
            }
            auto image = pdf.newStream(samples);
            image.replaceDict(Object::parse("<< /Type /XObject /Subtype /Image /Width " + std::to_string(width) +
                                            " /Height " + std::to_string(width) +
                                            " /BitsPerComponent 8 /ColorSpace /DeviceRGB >>"));
            return image;
        };
        auto shared = makeImage(200, 1), local = makeImage(160, 2);
        auto sharedForm = pdf.newStream("0.7 0.2 0.1 rg 0 0 20 20 re f\n");
        sharedForm.getDict().replaceKey("/Type", Object::newName("/XObject"));
        sharedForm.getDict().replaceKey("/Subtype", Object::newName("/Form"));
        sharedForm.getDict().replaceKey("/BBox", Object::parse("[0 0 20 20]"));
        sharedForm.getDict().replaceKey("/Resources", Object::newDictionary());
        auto lateForm = pdf.newStream("0.1 0.3 0.8 rg 0 0 20 20 re f\n");
        lateForm.getDict().replaceKey("/Type", Object::newName("/XObject"));
        lateForm.getDict().replaceKey("/Subtype", Object::newName("/Form"));
        lateForm.getDict().replaceKey("/BBox", Object::parse("[0 0 20 20]"));
        lateForm.getDict().replaceKey("/Resources", Object::newDictionary());
        auto first = pdf.makeIndirectObject(Object::parse("<< /Type /Page /MediaBox [0 0 300 300] >>"));
        first.replaceKey("/Resources", Object::newDictionary({{"/XObject", Object::newDictionary({
            {"/Shared", shared}, {"/SharedForm", sharedForm}, {"/LateForm", lateForm}})}}));
        first.replaceKey("/Contents", pdf.newStream(
            "1 0 0 rg 0 0 30 30 re f q 100 0 0 100 0 0 cm /Shared Do Q /SharedForm Do\n"));
        QPDFPageDocumentHelper(pdf).addPage(QPDFPageObjectHelper(first), false);
        auto second = pdf.makeIndirectObject(Object::parse("<< /Type /Page /MediaBox [0 0 300 300] >>"));
        second.replaceKey("/Resources", Object::newDictionary({{"/XObject", Object::newDictionary({
            {"/Shared", shared}, {"/Local", local}, {"/SharedForm", sharedForm}, {"/LateForm", lateForm}})}}));
        second.replaceKey("/Contents", pdf.newStream(
            "0 0 1 rg 0 0 30 30 re f q 100 0 0 100 0 0 cm /Shared Do Q q 80 0 0 80 120 0 cm /Local Do Q /SharedForm Do /LateForm Do\n"));
        QPDFPageDocumentHelper(pdf).addPage(QPDFPageObjectHelper(second), false);
        auto source = output / "Compression-Page-Policies-Source.pdf";
        auto full = output / "Compression-Page-Policies-Full.pdf";
        auto preview = output / "Compression-Page-Policies-Preview.pdf";
        save(pdf, source); fs::remove(full); fs::remove(preview);
        ips2pdf::PDFCompressionPlan plan;
        plan.document = {ips2pdf::PDFCompressionLevel::strong, false, 75, 0};
        plan.pages.emplace(1, ips2pdf::PDFCompressionPolicy{ips2pdf::PDFCompressionLevel::strong, true, 75, 0});
        const auto fullResult = ips2pdf::compressPDF(source, full, "", plan);
        const auto previewResult = ips2pdf::compressPDF(source, preview, "", plan, 1);
        require(fullResult.compression.sharedResourcesFromEarlierPages == 0 &&
                previewResult.compression.sharedResourcesFromEarlierPages == 2,
                "Shared page resource ownership was not reported");
        QPDF reopened; reopened.processFile(full.c_str());
        auto pictures = images(reopened);
        require(pictures.size() == 2, "Page policies duplicated or removed a shared image");
        int colorImages = 0, monochromeImages = 0;
        for (auto image : pictures) {
            const auto bits = image.getDict().getKey("/BitsPerComponent").getIntValue();
            if (bits == 8) {
                require(image.getDict().getKey("/BitsPerComponent").getIntValue() == 8 &&
                        image.getDict().getKey("/Filter").isNameAndEquals("/DCTDecode"),
                        "A later page changed a shared image owned by page 1");
                ++colorImages;
            } else if (bits == 1) {
                require(image.getDict().getKey("/BitsPerComponent").getIntValue() == 1 &&
                        image.getDict().getKey("/Filter").isNameAndEquals("/CCITTFaxDecode"),
                        "A page-local image ignored its individual policy");
                ++monochromeImages;
            } else require(false, "Page policy image depth changed unexpectedly");
        }
        require(colorImages == 1 && monochromeImages == 1,
                "First-page ownership did not separate shared and page-local image policies");
        int colorForms = 0, monochromeForms = 0;
        for (auto object : reopened.getAllObjects()) {
            if (!object.isStream() || !object.getDict().getKey("/Subtype").isNameAndEquals("/Form")) continue;
            const auto program = ips2pdf::readPDFContent(reopened, object);
            if (!program.operations.empty() && program.operations[0].name == "rg") ++colorForms;
            if (!program.operations.empty() && program.operations[0].name == "g") ++monochromeForms;
        }
        require(colorForms == 1 && monochromeForms == 1,
                "Shared forms did not use their first actual page invocation without duplication");
        const auto pages = QPDFPageDocumentHelper(reopened).getAllPages();
        require(ips2pdf::readPDFContent(reopened, pages[0].getObjectHandle()).operations[0].name == "rg" &&
                ips2pdf::readPDFContent(reopened, pages[1].getObjectHandle()).operations[0].name == "g",
                "Page-specific vector color policies were not applied");
        QPDF onePage; onePage.processFile(preview.c_str());
        require(QPDFPageDocumentHelper(onePage).getAllPages().size() == 1 && images(onePage).size() == 2,
                "Page preview lost or duplicated shared resources");
    }
    std::cout << "PASS compression: complete per-page policies, first-page ownership, exact preview ownership and no shared-image duplication\n";
    {
        QPDF pdf; pdf.emptyPDF();
        auto p = pdf.makeIndirectObject(Object::parse("<< /Type /Page /MediaBox [0 0 300 300] /Resources << /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> >> >>"));
        p.replaceKey("/Contents", pdf.newStream("0.8 0.5 0.4 rg 0 0 300 300 re f\nBT /F1 16 Tf 10 30 Td (Keep text) Tj ET\n1 g BT /F1 16 Tf 10 60 Td (White knockout) Tj ET\n"));
        pdf.getRoot().replaceKey("/AcroForm", Object::parse("<< /Fields [] /DA (0.8 0.5 0.4 rg /F1 9 Tf) /DR << /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> >> >>"));
        QPDFPageDocumentHelper(pdf).addPage(QPDFPageObjectHelper(p), false);
        auto widget = pdf.makeIndirectObject(Object::parse("<< /Type /Annot /Subtype /Widget /Rect [0 0 20 20] /MK << /BC [0.8 0.7 0.6] /BG [1 1 1] >> >>"));
        p.replaceKey("/Annots", Object::newArray({widget}));
        ips2pdf::rewritePDFColors(pdf, {.monochrome = true});
        auto program = ips2pdf::readPDFContent(pdf, p);
        double fill = -1;
        int text = 0;
        for (const auto& op : program.operations) {
            if (op.name == "g") fill = op.operands[0].getNumericValue();
            if (op.name == "Tj") { require(fill == (text++ == 0 ? 0 : 1), "Monochrome text or its white knockout changed"); }
        }
        require(text == 2, "Text content was lost during color conversion");
        require(pdf.getRoot().getKey("/AcroForm").getKey("/DA").getStringValue().starts_with("0 g"), "Default form text appearance was not made black");
        require(widget.getKey("/MK").getKey("/BC").unparse() == "[ 0 ]" &&
                widget.getKey("/MK").getKey("/BG").unparse() == "[ 1 ]", "Widget appearance colors were not converted");
        save(pdf, output / "Compression-Vector-Knockout.pdf");
    }
    {
        QPDF pdf; pdf.emptyPDF();
        auto profile = cmsCreate_sRGBProfile();
        cmsUInt32Number count = 0;
        require(profile && cmsSaveProfileToMem(profile, nullptr, &count), "Could not generate the ICC test profile");
        std::string bytes(count, '\0');
        require(cmsSaveProfileToMem(profile, bytes.data(), &count), "Could not save the ICC test profile");
        cmsCloseProfile(profile);
        auto icc = pdf.newStream(bytes); icc.getDict().replaceKey("/N", Object::newInteger(3));
        pdf.getRoot().replaceKey("/OutputIntents", Object::newArray({Object::newDictionary({{"/DestOutputProfile", icc}})}));
        auto p = pdf.makeIndirectObject(Object::parse("<< /Type /Page /MediaBox [0 0 300 300] /Resources << >> >>"));
        p.replaceKey("/Contents", pdf.newStream("0.2 0.4 0.6 rg 0 0 300 300 re f\n"));
        QPDFPageDocumentHelper(pdf).addPage(QPDFPageObjectHelper(p), false);
        auto attachment = pdf.newStream("Private invoice attachment payload");
        attachment.getDict().replaceKey("/Type", Object::newName("/EmbeddedFile"));
        auto file = pdf.makeIndirectObject(Object::parse("<< /Type /Filespec /UF (factur-x.xml) >>"));
        file.replaceKey("/EF", Object::newDictionary({{"/F", attachment}}));
        pdf.getRoot().replaceKey("/AF", Object::newArray({file}));
        auto link = pdf.makeIndirectObject(Object::parse("<< /Type /Annot /Subtype /Link /Rect [0 0 10 10] >>"));
        link.replaceKey("/A", Object::newDictionary({{"/S", Object::newName("/GoToE")}, {"/F", file}}));
        p.replaceKey("/Annots", Object::newArray({link}));
        auto source = output / "Compression-ICC-Source.pdf", target = output / "Compression-ICC-Result.pdf";
        save(pdf, source); fs::remove(target);
        const auto result = ips2pdf::compressPDF(source, target, "", ips2pdf::PDFCompressionPolicy{});
        require(result.compression.attachmentsRemoved && result.compression.invoiceAttachmentRemoved, "Invoice attachment warning missing");
        QPDF reopened; reopened.processFile(target.c_str()); noMetadata(reopened);
        auto page = QPDFPageDocumentHelper(reopened).getAllPages()[0].getObjectHandle();
        auto program = ips2pdf::readPDFContent(reopened, page);
        require(program.operations[0].name == "rg", "Output-intent colors were not converted");
        const auto& values = program.operations[0].operands;
        require(std::abs(values[0].getNumericValue() - .2) < .03 && std::abs(values[2].getNumericValue() - .6) < .03,
                "ICC output-intent conversion changed the color unexpectedly");
        require(page.getKey("/Annots").getArrayItem(0).getKey("/A").isNull(), "A link still targets the removed invoice attachment");
    }
    std::cout << "PASS compression: black text, white knockouts, actual ICC color conversion and invoice/attachment action cleanup\n";
}
