#include "PDFCompressionTransform.h"
#include "PDFColorProgram.h"
#include "PDFContentProgram.h"
#include "PDFImageCodec.h"
#include "PDFProcessingControl.h"
#include "PDFProcessingUnsupported.h"
#include <qpdf/Pl_SHA2.hh>
#include <qpdf/QPDFPageDocumentHelper.hh>
#include <algorithm>
#include <cstring>
#include <functional>
#include <map>
#include <set>

namespace ips2pdf {
namespace {
using Object = QPDFObjectHandle;
using Visitor = std::function<void(Object)>;
void visit(Object root, const Visitor& callback) {
    std::set<QPDFObjGen> seen;
    std::function<void(Object, unsigned)> walk = [&](Object object, unsigned depth) {
        checkPDFProcessing();
        if (depth > 256) throw std::runtime_error("PDF object hierarchy exceeds the processing limit");
        if (object.isIndirect() && !seen.insert(object.getObjGen()).second) return;
        callback(object);
        if (object.isArray()) for (auto child : object.getArrayAsVector()) walk(child, depth + 1);
        auto dictionary = object.isStream() ? object.getDict() : object;
        if (dictionary.isDictionary()) for (const auto& key : dictionary.getKeys()) walk(dictionary.getKey(key), depth + 1);
    };
    walk(root, 0);
}

struct FontProgram {
    QPDFObjGen stream;
    std::string fingerprint;
};
using FontPrograms = std::map<std::pair<QPDFObjGen, std::string>, FontProgram>;

std::string streamFingerprint(Object stream) {
    Pl_SHA2 digest(256);
    bool filteringAttempted = false;
    if (!stream.pipeStreamData(&digest, &filteringAttempted, 0, qpdf_dl_none, true, false))
        throw std::runtime_error("Could not read an embedded PDF font program");
    return digest.getHexDigest();
}

FontPrograms fontPrograms(QPDF& pdf) {
    FontPrograms programs;
    visit(pdf.getRoot(), [&](Object object) {
        if (!object.isDictionary()) return;
        for (const char* key : {"/FontFile", "/FontFile2", "/FontFile3"}) {
            auto stream = object.getKey(key);
            if (stream.isNull()) continue;
            if (!stream.isStream()) throw std::runtime_error("Invalid embedded PDF font program");
            programs[{object.isIndirect() ? object.getObjGen() : stream.getObjGen(), key}] =
                {stream.getObjGen(), streamFingerprint(stream)};
        }
    });
    return programs;
}
void verifyFonts(QPDF& pdf, const FontPrograms& original) {
    auto current = fontPrograms(pdf);
    if (current.size() != original.size()) throw std::runtime_error("PDF compression changed embedded fonts");
    for (const auto& [key, program] : original) {
        auto found = current.find(key);
        if (found == current.end() || found->second.stream != program.stream ||
            found->second.fingerprint != program.fingerprint)
            throw std::runtime_error("PDF compression changed an embedded font program");
    }
}
bool filter(Object image, const std::string& name) {
    auto value = image.getDict().getKey("/Filter");
    if (value.isNameAndEquals(name)) return true;
    if (value.isArray()) for (auto item : value.getArrayAsVector()) if (item.isNameAndEquals(name)) return true;
    return false;
}
// Output intents describe the intended interpretation of device samples.
// Materialize that interpretation before removing the profile. A PDF/X CMYK
// page must not change to an arbitrary generic CMYK conversion by accident.
void applyOutputIntent(QPDF& pdf) {
    std::map<int, Object> profiles;
    auto intents = pdf.getRoot().getKey("/OutputIntents");
    if (!intents.isNull() && !intents.isArray()) throw std::runtime_error("Invalid PDF output intents");
    if (intents.isArray()) for (auto intent : intents.getArrayAsVector()) {
        auto profile = intent.getKey("/DestOutputProfile");
        if (profile.isNull()) {
            if (intent.hasKey("/DestOutputProfileRef"))
                throw PDFProcessingUnsupported("An external output profile is unavailable for color conversion");
            continue;
        }
        if (!profile.isStream()) throw std::runtime_error("Invalid PDF output profile");
        auto n = profile.getDict().getKey("/N");
        if (!n.isInteger() || (n.getIntValue() != 1 && n.getIntValue() != 3 && n.getIntValue() != 4))
            throw std::runtime_error("Unsupported PDF output profile components");
        const int count = n.getIntValueAsInt();
        if (auto prior = profiles.find(count); prior != profiles.end() && !prior->second.isSameObjectAs(profile)) {
            auto a = prior->second.getStreamData(), b = profile.getStreamData();
            if (a->getSize() != b->getSize() || std::memcmp(a->getBuffer(), b->getBuffer(), a->getSize()))
                throw PDFProcessingUnsupported("Conflicting PDF output profiles require a selected output condition");
        }
        profiles[count] = profile;
    }
    if (profiles.empty()) return;
    auto install = [&](Object resources) {
        auto spaces = resources.getKey("/ColorSpace");
        if (spaces.isNull()) { spaces = Object::newDictionary(); resources.replaceKey("/ColorSpace", spaces); }
        if (!spaces.isDictionary()) throw std::runtime_error("Invalid PDF color resources");
        for (auto& [count, profile] : profiles) {
            const auto key = count == 1 ? "/DefaultGray" : count == 3 ? "/DefaultRGB" : "/DefaultCMYK";
            // An explicit default color space overrides the output condition.
            if (!spaces.hasKey(key)) spaces.replaceKey(key, Object::newArray({Object::newName("/ICCBased"), profile}));
        }
    };
    for (auto page : QPDFPageDocumentHelper(pdf).getAllPages()) {
        auto resources = page.getAttribute("/Resources", true);
        if (resources.isNull()) { resources = Object::newDictionary(); page.getObjectHandle().replaceKey("/Resources", resources); }
        install(resources);
    }
    visit(pdf.getRoot(), [&](Object object) {
        auto dictionary = object.isStream() ? object.getDict() : object;
        if (!dictionary.isDictionary()) return;
        for (const char* key : {"/Resources", "/DR"}) {
            auto resources = dictionary.getKey(key);
            if (resources.isDictionary()) install(resources);
        }
    });
}

PDFCompressionChanges removeAttachments(QPDF& pdf) {
    PDFCompressionChanges result;
    std::set<QPDFObjGen> files;
    std::set<std::string> fileNames;
    visit(pdf.getRoot(), [&](Object object) {
        if (!object.isDictionary() || !object.hasKey("/EF")) return;
        files.insert(object.getObjGen());
        for (const char* key : {"/F", "/UF"}) {
            auto name = object.getKey(key);
            if (!name.isString()) continue;
            auto text = name.getUTF8Value();
            fileNames.insert(text);
            std::transform(text.begin(), text.end(), text.begin(), [](unsigned char c) { return std::tolower(c); });
            if (text.find("factur-x") != std::string::npos || text.find("zugferd") != std::string::npos || text == "xrechnung.xml")
                result.invoiceAttachmentRemoved = true;
        }
        result.attachmentsRemoved = true;
    });
    auto attachmentAction = [&](Object action) {
        if (!action.isDictionary()) return false;
        if (action.getKey("/S").isNameAndEquals("/GoToE")) return true;
        auto file = action.getKey("/F");
        return (file.isIndirect() && files.contains(file.getObjGen())) ||
            (file.isString() && fileNames.contains(file.getUTF8Value()));
    };
    visit(pdf.getRoot(), [&](Object object) {
        auto dictionary = object.isStream() ? object.getDict() : object;
        if (!dictionary.isDictionary()) return;
        dictionary.removeKey("/AF");
        if (dictionary.hasKey("/EF")) {
            dictionary.removeKey("/EF"); dictionary.removeKey("/AFRelationship");
        }
        auto names = dictionary.getKey("/Names");
        if (names.isDictionary()) names.removeKey("/EmbeddedFiles");
        for (const char* key : {"/A", "/OpenAction"}) if (attachmentAction(dictionary.getKey(key))) dictionary.removeKey(key);
        auto additional = dictionary.getKey("/AA");
        if (additional.isDictionary()) for (const auto& key : additional.getKeys())
            if (attachmentAction(additional.getKey(key))) additional.removeKey(key);
        auto next = dictionary.getKey("/Next");
        if (attachmentAction(next)) dictionary.removeKey("/Next");
        else if (next.isArray()) {
            std::vector<Object> retained;
            for (auto action : next.getArrayAsVector()) if (!attachmentAction(action)) retained.push_back(action);
            dictionary.replaceKey("/Next", Object::newArray(retained));
        }
        auto annotations = dictionary.getKey("/Annots");
        if (annotations.isArray()) {
            std::vector<Object> retained;
            for (auto annotation : annotations.getArrayAsVector())
                if (!annotation.getKey("/Subtype").isNameAndEquals("/FileAttachment")) retained.push_back(annotation);
            dictionary.replaceKey("/Annots", Object::newArray(retained));
        }
    });
    return result;
}

struct Image { Object object, colorSpace; };

struct PageOwnership {
    std::map<QPDFObjGen, std::size_t> owners;
};

PageOwnership assignPageOwners(QPDF& pdf) {
    const auto pages = QPDFPageDocumentHelper(pdf).getAllPages();
    PageOwnership result;
    for (std::size_t pageIndex = 0; pageIndex < pages.size(); ++pageIndex) {
        std::set<QPDFObjGen> seen;
        std::function<void(Object, unsigned)> walk = [&](Object object, unsigned depth) {
            checkPDFProcessing();
            if (depth > 256) throw std::runtime_error("PDF page resource hierarchy exceeds the processing limit");
            auto dictionary = object.isStream() ? object.getDict() : object;
            if (depth > 0 && dictionary.isDictionary() && dictionary.getKey("/Type").isNameAndEquals("/Page")) return;
            if (object.isIndirect()) {
                const auto id = object.getObjGen();
                if (!seen.insert(id).second) return;
                result.owners.try_emplace(id, pageIndex);
            }
            if (object.isArray()) for (auto child : object.getArrayAsVector()) walk(child, depth + 1);
            if (!dictionary.isDictionary()) return;
            for (const auto& key : dictionary.getKeys()) {
                // Page-tree and annotation back-references must not make an
                // earlier page claim resources that it does not display.
                if (key == "/Parent" || key == "/P" || key == "/Pages") continue;
                walk(dictionary.getKey(key), depth + 1);
            }
        };
        walk(pages[pageIndex].getObjectHandle(), 0);
    }
    return result;
}

std::map<QPDFObjGen, Image> imageInventory(QPDF& pdf) {
    std::map<QPDFObjGen, Image> images;
    std::set<std::pair<QPDFObjGen, std::string>> seen;
    std::function<void(Object, Object, unsigned)> walk = [&](Object object, Object resources, unsigned depth) {
        checkPDFProcessing();
        if (depth > 256) throw std::runtime_error("PDF image hierarchy exceeds the processing limit");
        auto dictionary = object.isStream() ? object.getDict() : object;
        if (dictionary.isDictionary()) {
            auto local = dictionary.getKey("/Resources");
            if (local.isDictionary()) resources = local;
        }
        if (object.isIndirect() && !seen.emplace(object.getObjGen(), resources.unparse()).second) return;
        if (object.isStream() && dictionary.getKey("/Subtype").isNameAndEquals("/Image")) {
            auto space = dictionary.getKey("/ColorSpace");
            if (!space.isNull()) space = resolvePDFColorSpace(space, resources);
            auto id = object.getObjGen();
            if (auto prior = images.find(id); prior != images.end() && prior->second.colorSpace.unparse() != space.unparse())
                throw PDFProcessingUnsupported("A shared PDF image has conflicting color interpretations");
            images[id] = {object, space};
        }
        if (object.isArray()) for (auto child : object.getArrayAsVector()) walk(child, resources, depth + 1);
        if (dictionary.isDictionary()) for (const auto& key : dictionary.getKeys()) {
            // Back-references must not reinterpret another page's resources.
            if (key == "/Parent" || key == "/P" || key == "/Pages") continue;
            walk(dictionary.getKey(key), resources, depth + 1);
        }
    };
    for (auto page : QPDFPageDocumentHelper(pdf).getAllPages())
        walk(page.getObjectHandle(), page.getAttribute("/Resources", false), 0);
    walk(pdf.getRoot(), Object::newNull(), 0);
    return images;
}

void compressImages(QPDF& pdf, const PDFCompressionPlan& plan,
                    const std::map<QPDFObjGen, std::size_t>& pageOwners,
                    const std::map<QPDFObjGen, PDFImagePlacement>& placements) {
    auto images = imageInventory(pdf);
    std::set<QPDFObjGen> masks;
    for (auto& [id, image] : images) for (const char* key : {"/SMask", "/Mask"}) {
        auto mask = image.object.getDict().getKey(key);
        if (mask.isStream()) masks.insert(mask.getObjGen());
    }
    for (auto& [id, image] : images) {
        checkPDFProcessing();
        const auto placement = placements.find(id);
        const auto owner = pageOwners.find(id);
        const auto& policy = placement != placements.end() &&
            placement->second.firstPage != std::numeric_limits<size_t>::max()
            ? plan.policyForPage(placement->second.firstPage)
            : owner == pageOwners.end() ? plan.document : plan.policyForPage(owner->second);
        auto dictionary = image.object.getDict();
        auto stencil = dictionary.getKey("/ImageMask");
        if (masks.contains(id) || (stencil.isBool() && stencil.getBoolValue())) {
            // Alpha/stencil samples carry geometry, not display colors. Never
            // threshold them or reduce their depth as ordinary picture data.
            if (filter(image.object, "/JPXDecode"))
                throw PDFProcessingUnsupported("JPEG 2000 masks require a lossless alpha conversion");
            if (!image.colorSpace.isNull() && !image.colorSpace.isNameAndEquals("/DeviceGray"))
                throw PDFProcessingUnsupported("A technical mask has an unsupported color interpretation");
            continue;
        }
        if (dictionary.getKey("/Mask").isArray())
            throw PDFProcessingUnsupported("Color-key image masks require a separate alpha conversion");
        auto softMask = dictionary.getKey("/SMask");
        if (softMask.isStream() && softMask.getDict().hasKey("/Matte"))
            throw PDFProcessingUnsupported("Preblended image masks require a dedicated matte conversion.");
        if (image.colorSpace.isArray() && image.colorSpace.getArrayNItems() > 1) {
            auto type = image.colorSpace.getArrayItem(0), names = image.colorSpace.getArrayItem(1);
            if (type.isNameAndEquals("/Separation") || type.isNameAndEquals("/DeviceN")) {
                const auto colorants = names.isArray() ? names.getArrayAsVector() : std::vector<Object>{names};
                for (auto name : colorants) if (name.isNameAndEquals("/None") || name.isNameAndEquals("/All"))
                    throw PDFProcessingUnsupported("Registration or non-painting image colorants require a dedicated conversion.");
            }
        }
        const int sourceWidth = dictionary.getKey("/Width").getIntValueAsInt();
        const int sourceHeight = dictionary.getKey("/Height").getIntValueAsInt();
        if (sourceWidth <= 0 || sourceHeight <= 0)
            throw std::runtime_error("Invalid PDF image dimensions");
        const auto found = placements.find(id);
        double ppi = found == placements.end() ? 0 : found->second.minimumPPI;
        auto scale = policy.resizeScale(ppi);
        int width = sourceWidth;
        int height = sourceHeight;
        if (scale < 1) {
            width = std::max(1, static_cast<int>(std::ceil(sourceWidth * scale)));
            height = std::max(1, static_cast<int>(std::ceil(sourceHeight * scale)));
            const double actual = std::min(double(width) / sourceWidth, double(height) / sourceHeight);
            ppi *= actual;
        }
        recompressPDFImage(image.object, image.colorSpace, width, height, policy);
    }
}
} // namespace

PDFCompressionChanges compressPDFObjects(QPDF& pdf, const PDFCompressionPlan& plan, int previewPage) {
    plan.validate();
    const auto inputFonts = fontPrograms(pdf);
    auto changes = removeAttachments(pdf);
    externalizePDFInlineImages(pdf);
    applyOutputIntent(pdf);
    const auto pages = QPDFPageDocumentHelper(pdf).getAllPages();
    plan.validatePageCount(pages.size());
    const auto census = pdfContentCensus(pdf);
    auto ownership = assignPageOwners(pdf);
    // Content invocation is authoritative. A resource name that is present
    // but unused on an earlier page must not claim the object.
    for (const auto& [id, page] : census.firstResourcePages) ownership.owners[id] = page;
    if (previewPage >= 0) for (const auto& [id, pagesUsingResource] : census.resourcePages) {
        const auto first = census.firstResourcePages.find(id);
        if (first != census.firstResourcePages.end() && first->second < static_cast<std::size_t>(previewPage) &&
            pagesUsingResource.contains(static_cast<std::size_t>(previewPage)))
            ++changes.sharedResourcesFromEarlierPages;
    }
    if (previewPage >= 0) {
        QPDFPageDocumentHelper document(pdf);
        if (static_cast<size_t>(previewPage) >= pages.size()) throw std::runtime_error("Invalid PDF preview page");
        for (size_t i = 0; i < pages.size(); ++i) if (i != static_cast<size_t>(previewPage)) document.removePage(pages[i]);
        // This private one-page result is never offered for adoption/export.
        // Remove document navigation that could retain unrelated page graphs;
        // keep form defaults so the selected page's widgets still render.
        auto root = pdf.getRoot();
        for (const auto& key : root.getKeys())
            if (key != "/Type" && key != "/Pages" && key != "/AcroForm" && key != "/OutputIntents") root.removeKey(key);
    }
    const auto fonts = previewPage < 0 ? inputFonts : fontPrograms(pdf);
    // Decode original image colors before the vector pass removes color-space
    // aliases. No page, text object or embedded font is regenerated.
    compressImages(pdf, plan, ownership.owners, census.images);
    rewritePDFColors(pdf, plan, ownership.owners);
    visit(pdf.getRoot(), [](Object object) {
        auto dictionary = object.isStream() ? object.getDict() : object;
        if (!dictionary.isDictionary()) return;
        dictionary.removeKey("/OutputIntents");
        if (dictionary.hasKey("/DestOutputProfile")) dictionary.removeKey("/DestOutputProfile");
        if (dictionary.hasKey("/DestOutputProfileRef")) dictionary.removeKey("/DestOutputProfileRef");
    });
    // A successful result must contain no remaining ICC color-space graph.
    // Unsupported dependencies fail before any candidate can be accepted.
    visit(pdf.getRoot(), [](Object object) {
        if (object.isNameAndEquals("/ICCBased")) throw PDFProcessingUnsupported("An ICC-dependent PDF object was not converted");
    });
    verifyFonts(pdf, fonts);
    return changes;
}
} // namespace ips2pdf
