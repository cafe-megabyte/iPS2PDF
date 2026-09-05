#include "PDFProcessingSmoke.h"
#include "PDFImageCodecSmoke.h"
#include "PDFCompressionSmoke.h"
#include "PDFBinaryImageMetadataSmoke.h"
#include "PDFImageMetadata.h"
#include "PDFStreamMetadata.h"
#include "PDFStructuralSmoke.h"

#include <qpdf/QPDF.hh>
#include <qpdf/QPDFPageDocumentHelper.hh>
#include <qpdf/QPDFWriter.hh>
#include <public/fpdf_compress.h>
#include <public/fpdf_save.h>
#include <public/fpdf_text.h>
#include <public/fpdfview.h>

#include <algorithm>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>
#include <zlib.h>

namespace {
using Object = QPDFObjectHandle;
namespace fs = std::filesystem;

void require(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
}

struct Document {
    FPDF_DOCUMENT handle;
    explicit Document(const fs::path& path) : handle(FPDF_LoadDocument(path.c_str(), nullptr)) {
        require(handle != nullptr, "PDFium could not open a synthetic fixture");
    }
    ~Document() { FPDF_CloseDocument(handle); }
    Document(const Document&) = delete;
    Document& operator=(const Document&) = delete;
};

struct Writer : FPDF_FILEWRITE {
    std::ofstream stream;
    explicit Writer(const fs::path& path) : stream(path, std::ios::binary | std::ios::trunc) {
        require(stream.good(), "Could not open the smoke output");
        version = 1;
        WriteBlock = [](FPDF_FILEWRITE* base, const void* data, unsigned long length) -> int {
            auto& writer = *static_cast<Writer*>(base);
            writer.stream.write(static_cast<const char*>(data), static_cast<std::streamsize>(length));
            return writer.stream.good() ? 1 : 0;
        };
    }
};

std::string decoded(Object stream) {
    auto data = stream.getStreamData();
    return {reinterpret_cast<const char*>(data->getBuffer()), data->getSize()};
}

std::vector<std::string> fonts(QPDF& pdf) {
    std::vector<std::string> values;
    for (auto object : pdf.getAllObjects()) {
        if (!object.isDictionary()) continue;
        for (const auto* key : {"/FontFile", "/FontFile2", "/FontFile3"}) {
            auto program = object.getKey(key);
            if (program.isStream()) values.push_back(decoded(program));
        }
    }
    std::sort(values.begin(), values.end());
    return values;
}

std::vector<std::string> fields(QPDF& pdf) {
    std::vector<std::string> values;
    for (auto object : pdf.getAllObjects()) {
        if (!object.isDictionary() || !object.getKey("/T").isString()) continue;
        values.push_back(object.getKey("/T").getUTF8Value() + "\n" +
                         object.getKey("/V").unparseResolved());
    }
    std::sort(values.begin(), values.end());
    return values;
}

std::u16string text(FPDF_DOCUMENT pdf) {
    std::u16string result;
    for (int index = 0; index < FPDF_GetPageCount(pdf); ++index) {
        auto page = FPDF_LoadPage(pdf, index);
        require(page != nullptr, "Page loading failed");
        auto text_page = FPDFText_LoadPage(page);
        require(text_page != nullptr, "Text extraction failed");
        int count = FPDFText_CountChars(text_page);
        std::vector<unsigned short> buffer(static_cast<size_t>(count) + 1);
        int written = FPDFText_GetText(text_page, 0, count, buffer.data());
        for (int i = 0; i + 1 < written; ++i) result.push_back(static_cast<char16_t>(buffer[i]));
        result.push_back(u'\f');
        FPDFText_ClosePage(text_page);
        FPDF_ClosePage(page);
    }
    return result;
}

void render(FPDF_DOCUMENT document) {
    auto page = FPDF_LoadPage(document, 0);
    require(page != nullptr, "Rendering could not open page zero");
    auto bitmap = FPDFBitmap_Create(320, 400, 0);
    require(bitmap != nullptr, "Rendering could not allocate a bitmap");
    FPDFBitmap_FillRect(bitmap, 0, 0, 320, 400, 0xffffffff);
    FPDF_RenderPageBitmap(bitmap, page, 0, 0, 320, 400, 0, FPDF_ANNOT);
    const auto* bytes = static_cast<const unsigned char*>(FPDFBitmap_GetBuffer(bitmap));
    size_t length = static_cast<size_t>(FPDFBitmap_GetStride(bitmap)) * 400;
    bool has_ink = false;
    for (size_t i = 0; i + 3 < length; i += 4)
        has_ink |= bytes[i] < 240 || bytes[i + 1] < 240 || bytes[i + 2] < 240;
    FPDFBitmap_Destroy(bitmap);
    FPDF_ClosePage(page);
    require(has_ink, "Rendered fixture was unexpectedly blank");
}

void compress(const fs::path& input, const fs::path& output) {
    Document pdf(input);
    auto options = HyperCompress_CreateOptions();
    require(options != nullptr, "Could not allocate compression options");
    // These are feasibility-test settings, not the final product's presets.
    // In particular, disable every font transformation before testing retention.
    for (int option : {HYPERC_OPT_FONT_SUBSET, HYPERC_OPT_FONT_REMOVE_STANDARD,
                       HYPERC_OPT_UNEMBED_ALIASED_FONTS, HYPERC_OPT_FONT_MERGE,
                       HYPERC_OPT_FONT_DEDUP_DICTS, HYPERC_OPT_DISCARD_MASK,
                       HYPERC_OPT_FLATTEN_ICC, HYPERC_OPT_MRC_MODE,
                       HYPERC_OPT_CONVERT_TO_BITMAP, HYPERC_OPT_OPTIMIZE_RESOURCES,
                       HYPERC_OPT_DEDUP_OBJECTS, HYPERC_OPT_STREAM_CODEC,
                       HYPERC_OPT_IMAGE_PREFER_JPX, HYPERC_OPT_IMAGE_LOSSY_INDEX,
                       HYPERC_OPT_REDUCE_COLOR_COMPLEXITY, HYPERC_OPT_CLIP_IMAGES}) {
        HyperCompress_SetOption(options, option, 0);
    }
    HyperCompress_SetOption(options, HYPERC_OPT_IMAGE_MAX_DPI, 300);
    HyperCompress_SetOption(options, HYPERC_OPT_IMAGE_QUALITY, 90);
    HyperCompress_SetOption(options, HYPERC_OPT_IMAGE_ENCODING, HYPERC_IMAGE_ENCODING_JPEG);
    HyperCompress_SetOption(options, HYPERC_OPT_JPEG_SUBSAMPLE, HYPERC_JPEG_SUBSAMPLE_444);
    HyperCompress_SetOption(options, HYPERC_OPT_JPEG_PROGRESSIVE, 1);
    int status = HyperCompress_Execute(pdf.handle, options);
    HyperCompress_CloseOptions(options);
    require(status == 1, "Hyper Compress did not process the unsigned fixture");
    Writer writer(output);
    require(FPDF_SaveAsCopy(pdf.handle, &writer, FPDF_NO_INCREMENTAL), "Full PDF rewrite failed");
    writer.stream.flush();
    require(writer.stream.good(), "Could not finish the smoke output");
}

void generate(const fs::path& path) {
    QPDF pdf;
    pdf.emptyPDF();
    auto page = pdf.makeIndirectObject(Object::parse("<< /Type /Page /MediaBox [0 0 600 800] >>"));
    auto font = pdf.makeIndirectObject(Object::parse("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"));
    auto resources = Object::newDictionary();
    auto font_resources = Object::newDictionary();
    font_resources.replaceKey("/F1", font);
    resources.replaceKey("/Font", font_resources);
    std::string pixels(800 * 600 * 3, '\0');
    unsigned int state = 42;
    for (size_t i = 0; i < pixels.size(); ++i) {
        state = state * 1664525u + 1013904223u;
        pixels[i] = static_cast<char>((state >> 24) / 4 + (i / 2400) % 192);
    }
    auto image = pdf.newStream(pixels);
    for (auto item : {std::pair{"/Type", "/XObject"}, {"/Subtype", "/Image"}, {"/ColorSpace", "/DeviceRGB"}})
        image.getDict().replaceKey(item.first, Object::newName(item.second));
    image.getDict().replaceKey("/Width", Object::newInteger(800));
    image.getDict().replaceKey("/Height", Object::newInteger(600));
    image.getDict().replaceKey("/BitsPerComponent", Object::newInteger(8));
    auto images = Object::newDictionary();
    images.replaceKey("/Im0", image);
    resources.replaceKey("/XObject", images);
    page.replaceKey("/Resources", resources);
    page.replaceKey("/Contents", pdf.newStream(
        "/P << /MCID 0 >> BDC BT /F1 18 Tf 40 750 Td (Native PDF smoke 0123456789) Tj ET EMC\n"
        "q 120 0 0 90 40 400 cm /Im0 Do Q\n"));
    page.replaceKey("/StructParents", Object::newInteger(0));
    QPDFPageDocumentHelper(pdf).addPage(QPDFPageObjectHelper(page), false);
    auto structure = pdf.makeIndirectObject(Object::parse("<< /Type /StructTreeRoot /ParentTreeNextKey 1 >>"));
    auto paragraph = pdf.makeIndirectObject(Object::parse("<< /Type /StructElem /S /P /K 0 >>"));
    paragraph.replaceKey("/P", structure);
    paragraph.replaceKey("/Pg", page);
    structure.replaceKey("/K", Object::newArray({paragraph}));
    auto parents = pdf.makeIndirectObject(Object::newDictionary());
    parents.replaceKey("/Nums", Object::newArray({Object::newInteger(0), Object::newArray({paragraph})}));
    structure.replaceKey("/ParentTree", parents);
    pdf.getRoot().replaceKey("/StructTreeRoot", structure);
    pdf.getRoot().replaceKey("/MarkInfo", Object::parse("<< /Marked true >>"));
    pdf.getRoot().replaceKey("/Lang", Object::newString("en-US"));
    auto field = pdf.makeIndirectObject(Object::parse(
        "<< /Type /Annot /Subtype /Widget /FT /Tx /T (SmokeField) /V (Editable value) "
        "/Rect [40 340 300 375] /F 4 /DA (/F1 12 Tf 0 g) >>"));
    field.replaceKey("/P", page);
    auto appearance = pdf.newStream("BT /F1 12 Tf 0 12 Td (Editable value) Tj ET");
    appearance.getDict().replaceKey("/Type", Object::newName("/XObject"));
    appearance.getDict().replaceKey("/Subtype", Object::newName("/Form"));
    appearance.getDict().replaceKey("/BBox", Object::parse("[0 0 260 35]"));
    appearance.getDict().replaceKey("/Resources", resources);
    auto appearances = Object::newDictionary();
    appearances.replaceKey("/N", appearance);
    field.replaceKey("/AP", appearances);
    page.replaceKey("/Annots", Object::newArray({field}));
    auto form = Object::newDictionary();
    form.replaceKey("/Fields", Object::newArray({field}));
    form.replaceKey("/DR", resources);
    pdf.getRoot().replaceKey("/AcroForm", form);
    QPDFWriter writer(pdf, path.c_str());
    writer.write();
}

void checkJPEGMetadata(Object image) {
    auto raw = image.getRawStreamData();
    require(raw->getSize() > 4, "JPEG test data is empty");
    const char* sentinel = "IPS2PDF_PRIVATE_IMAGE_METADATA_872cf9a";
    std::vector<uint8_t> marked = {0xff, 0xd8};
    auto marker = [&](uint8_t code, const std::string& payload) {
        size_t size = payload.size() + 2;
        marked.insert(marked.end(), {0xff, code, static_cast<uint8_t>(size >> 8), static_cast<uint8_t>(size)});
        marked.insert(marked.end(), payload.begin(), payload.end());
    };
    marker(0xe1, std::string("http://ns.adobe.com/xap/1.0/\0", 29) + sentinel);
    marker(0xfe, sentinel);
    const std::string profile_chunk = std::string("ICC_PROFILE\0\1\1", 14) + "synthetic-profile-payload";
    marker(0xe2, profile_chunk);
    require(raw->getBuffer()[raw->getSize() - 2] == 0xff && raw->getBuffer()[raw->getSize() - 1] == 0xd9,
            "The generated JPEG does not end in EOI");
    marked.insert(marked.end(), raw->getBuffer() + 2, raw->getBuffer() + raw->getSize() - 2);
    marker(0xfe, sentinel);
    marked.insert(marked.end(), {0xff, 0xd9});
    marked.insert(marked.end(), sentinel, sentinel + std::char_traits<char>::length(sentinel));
    auto cleaned = ips2pdf::removeJPEGMetadata(marked, true);
    std::string clean_bytes(cleaned.begin(), cleaned.end());
    require(clean_bytes.find(sentinel) == std::string::npos, "JPEG metadata or trailing bytes survived");
    require(clean_bytes.find(profile_chunk) != std::string::npos, "JPEG ICC chunk changed in metadata-only mode");
    require(cleaned == ips2pdf::removeJPEGMetadata(cleaned, true), "JPEG metadata cleanup is not idempotent");
    QPDF decoder;
    decoder.emptyPDF();
    auto pixels = [&](const std::vector<uint8_t>& bytes) {
        auto stream = decoder.newStream(std::string(bytes.begin(), bytes.end()));
        stream.getDict().replaceKey("/Filter", Object::newName("/DCTDecode"));
        auto buffer = stream.getStreamData(qpdf_dl_all);
        return std::string(reinterpret_cast<const char*>(buffer->getBuffer()), buffer->getSize());
    };
    auto before = pixels(marked);
    require(!before.empty() && before == pixels(cleaned), "JPEG metadata cleanup changed decoded samples");
    uLongf wrapped_size = compressBound(static_cast<uLong>(marked.size()));
    std::string wrapped(wrapped_size, '\0');
    require(compress2(reinterpret_cast<Bytef*>(wrapped.data()), &wrapped_size, marked.data(),
                      static_cast<uLong>(marked.size()), Z_BEST_COMPRESSION) == Z_OK, "Test wrapping failed");
    wrapped.resize(wrapped_size);
    auto transport = decoder.newStream(wrapped);
    transport.getDict().replaceKey("/Filter", Object::parse("[/FlateDecode /DCTDecode]"));
    transport.getDict().replaceKey("/DecodeParms", Object::parse("[null null]"));
    require(ips2pdf::isJPEGStream(transport), "Wrapped JPEG was not recognized");
    auto original_samples = transport.getStreamData(qpdf_dl_all);
    // qpdf's optional DCT decoder accepts no ColorTransform parameter. Check
    // preservation of that parameter separately from the sample-byte check.
    transport.getDict().replaceKey("/DecodeParms", Object::parse("[null << /ColorTransform 1 >>]"));
    require(ips2pdf::cleanJPEGStream(decoder, transport, true), "Wrapped JPEG was not cleaned");
    auto cleaned_raw = transport.getRawStreamData();
    auto cleaned_samples = pixels(std::vector<uint8_t>(cleaned_raw->getBuffer(),
                                                      cleaned_raw->getBuffer() + cleaned_raw->getSize()));
    require(original_samples->getSize() == cleaned_samples.size() &&
            std::equal(original_samples->getBuffer(), original_samples->getBuffer() + original_samples->getSize(),
                       reinterpret_cast<const unsigned char*>(cleaned_samples.data())),
            "Transport removal changed JPEG samples");
    require(transport.getDict().getKey("/DecodeParms").getKey("/ColorTransform").getIntValue() == 1,
            "The image's explicit color transform changed");
    require(!ips2pdf::cleanJPEGStream(decoder, transport, true), "Stream cleanup changed an already cleaned JPEG");
    auto without_profile = ips2pdf::removeJPEGMetadata(marked, false);
    require(std::string(without_profile.begin(), without_profile.end()).find("ICC_PROFILE") == std::string::npos,
            "JPEG ICC chunk was not removed after color conversion");
    bool rejected = false;
    try {
        ips2pdf::removeJPEGMetadata(std::span(cleaned).first(cleaned.size() - 2), true);
    } catch (const std::runtime_error&) { rejected = true; }
    require(rejected, "Truncated JPEG was accepted as fully cleaned");
    std::printf("PASS JPEG metadata: XMP/comments/tail removed, ICC preserved, transport filters decoded, samples unchanged\n");
}

void check(const fs::path& input, const fs::path& output, bool expect_jpeg = false) {
    QPDF before;
    before.processFile(input.c_str());
    auto font_programs = fonts(before);
    auto form_values = fields(before);
    Document original(input);
    auto original_text = text(original.handle);
    compress(input, output);
    QPDF after;
    after.processFile(output.c_str());
    require(before.getAllPages().size() == after.getAllPages().size(), "Page count changed");
    require(font_programs == fonts(after), "Embedded font programs changed");
    require(form_values == fields(after), "Form field names or values changed");
    require(before.getRoot().hasKey("/StructTreeRoot") == after.getRoot().hasKey("/StructTreeRoot"),
            "Structure tree was removed");
    Document result(output);
    require(original_text == text(result.handle), "Extracted text changed");
    render(result.handle);
    if (expect_jpeg) {
        bool found = false;
        for (auto object : after.getAllObjects()) {
            if (object.isStream() && object.getDict().getKey("/Filter").isNameAndEquals("/DCTDecode")) {
                found = true;
                checkJPEGMetadata(object);
            }
        }
        require(found, "Image encoding did not exercise the JPEG path");
    }
    std::printf("PASS %s: %zu font programs, %zu fields, %llu -> %llu bytes\n",
                input.filename().c_str(), font_programs.size(), form_values.size(),
                static_cast<unsigned long long>(fs::file_size(input)),
                static_cast<unsigned long long>(fs::file_size(output)));
    std::fflush(stdout);
}
} // namespace

int ips2pdf_run_native_smoke(const char* fixture_directory, const char* output_directory) {
    int status = 0;
    FPDF_LIBRARY_CONFIG config = {};
    config.version = 6;
    config.m_BrotliEnabled = 1;
    // Missing fonts may use PDFium's rendering fallback, but must never be
    // inserted into the saved PDF. No system font directory scan is needed.
    const char* font_paths[] = {nullptr};
    config.m_pUserFontPaths = font_paths;
    FPDF_InitLibraryWithConfig(&config);
    try {
        fs::path fixtures(fixture_directory), output(output_directory);
        fs::create_directories(output);
        runStructuralSmoke(fixtures, output);
        runImageCodecSmoke(output);
        runCompressionSmoke(fixtures, output);
        runBinaryImageMetadataSmoke(fixtures, output);
        auto generated = output / "GeneratedTaggedForm.pdf";
        generate(generated);
        check(generated, output / "GeneratedTaggedForm-compressed.pdf", true);
        for (const auto* name : {"InfoPlain", "InfoEmbeddedFull", "InfoEmbeddedSubset", "InfoICC", "InfoType3"})
            check(fixtures / (std::string(name) + ".pdf"), output / (std::string(name) + "-compressed.pdf"));
        check(fixtures / "Review/inherited-field-type.pdf", output / "InheritedField-compressed.pdf");
    } catch (std::exception const& error) {
        std::fprintf(stderr, "FAIL native smoke: %s\n", error.what());
        status = 1;
    }
    FPDF_DestroyLibrary();
    return status;
}
