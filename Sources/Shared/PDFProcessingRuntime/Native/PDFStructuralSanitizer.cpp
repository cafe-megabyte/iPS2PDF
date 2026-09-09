#include "PDFStructuralSanitizer.h"
#include "PDFSignatureFontAnonymizer.h"
#include "PDFStreamMetadata.h"
#include "PDFProcessingControl.h"
#include <qpdf/QPDFAnnotationObjectHelper.hh>
#include <qpdf/QPDFPageDocumentHelper.hh>

#include <functional>
#include <set>
#include <stdexcept>
#include <utility>
#include <vector>

namespace ips2pdf {
namespace {
using Object = QPDFObjectHandle;

class Sanitizer {
public:
    explicit Sanitizer(QPDF& owner) : pdf(owner) {}

    PDFSanitizationResult run(const PDFMetadataRetention& retention) {
        auto root = pdf.getRoot();
        remove(pdf.getTrailer(), "/Info");
        // A fresh ID is permitted only for unencrypted input. The original ID
        // participates in legacy PDF encryption and must survive that rewrite.
        if (!pdf.isEncrypted()) remove(pdf.getTrailer(), "/ID");
        invalidateSignatures(root);
        walk(root, 0);
        if (!retention.xmp.empty()) {
            auto metadata = pdf.newStream(retention.xmp);
            metadata.getDict().replaceKey("/Type", Object::newName("/Metadata"));
            metadata.getDict().replaceKey("/Subtype", Object::newName("/XML"));
            root.replaceKey("/Metadata", metadata);
        }
        if (!retention.infoStrings.empty() || !retention.trappedState.empty()) {
            auto info = Object::newDictionary();
            for (const auto& [key, value] : retention.infoStrings) {
                // Retention is deliberately restricted to conformity fields.
                if (key != "/Title" && key != "/GTS_PDFXVersion" && key != "/GTS_PDFXConformance" && key != "/CreationDate" && key != "/ModDate")
                    throw std::runtime_error("Unsupported conformity metadata retention key");
                info.replaceKey(key, Object::newUnicodeString(value));
            }
            if (!retention.trappedState.empty()) {
                if (retention.trappedState != "True" && retention.trappedState != "False")
                    throw std::runtime_error("Unsupported retained trapped state");
                info.replaceKey("/Trapped", Object::newName("/" + retention.trappedState));
            }
            pdf.getTrailer().replaceKey("/Info", pdf.makeIndirectObject(info));
        }
        return result;
    }

    PDFSanitizationResult signaturesOnly() {
        invalidateSignatures(pdf.getRoot());
        return result;
    }

private:
    QPDF& pdf;
    PDFSanitizationResult result;
    std::set<QPDFObjGen> visited;
    std::set<QPDFObjGen> signedWidgets;

    void invalidateSignatures(Object root) {
        auto form = root.getKey("/AcroForm");
        if (form.isDictionary()) {
            std::set<QPDFObjGen> active;
            clearSignatures(form.getKey("/Fields"), Object::newNull(), false, active, 0);
            auto flags = form.getKey("/SigFlags");
            if (flags.isInteger()) form.replaceKey("/SigFlags", Object::newInteger(flags.getIntValue() & ~2LL));
        }
        auto permissions = root.getKey("/Perms");
        if (permissions.isDictionary()) {
            for (const char* key : {"/DocMDP", "/UR", "/UR3"}) {
                if (!permissions.getKey(key).isNull()) result.signaturesRemoved = true;
                remove(permissions, key);
            }
            if (permissions.getKeys().empty()) remove(root, "/Perms");
        }
        // DSS contains validation material for signatures invalidated by any
        // rewrite. It is not part of a page's visible signature appearance.
        remove(root, "/DSS");
        preserveSignatureAppearances();
    }

    void remove(Object dictionary, const char* key) {
        if (!dictionary.hasKey(key)) return;
        dictionary.removeKey(key);
        ++result.metadataEntriesRemoved;
    }

    void clearSignatureValue(Object field) {
        if (!field.getKey("/V").isNull() || !field.getKey("/DV").isNull()) result.signaturesRemoved = true;
        // Retain the empty signature field, its appearance, accessibility
        // label, structure references and future signing behavior. Changing a
        // tagged Widget into a Stamp would invalidate those semantics.
        remove(field, "/V");
        remove(field, "/DV");
    }

    void clearSignatures(Object fields, Object inheritedType, bool signedAncestor,
                         std::set<QPDFObjGen>& active, unsigned depth) {
        if (!fields.isArray()) return;
        if (depth > 256) throw std::runtime_error("PDF form hierarchy exceeds the processing limit");
        for (int i = fields.getArrayNItems() - 1; i >= 0; --i) {
            checkPDFProcessing();
            auto field = fields.getArrayItem(i);
            if (!field.isDictionary()) continue;
            if (field.isIndirect() && !active.insert(field.getObjGen()).second)
                throw std::runtime_error("Cyclic PDF form hierarchy");
            auto type = field.getKey("/FT");
            if (type.isNull()) type = inheritedType;
            const bool signedField = type.isNameAndEquals("/Sig") && (signedAncestor || !field.getKey("/V").isNull());
            if (signedField && field.getKey("/Subtype").isNameAndEquals("/Widget") && field.isIndirect())
                signedWidgets.insert(field.getObjGen());
            auto children = field.getKey("/Kids");
            clearSignatures(children, type, signedField, active, depth + 1);
            if (type.isNameAndEquals("/Sig")) clearSignatureValue(field);
            if (field.isIndirect()) active.erase(field.getObjGen());
        }
    }

    void preserveSignatureAppearances() {
        for (auto page : QPDFPageDocumentHelper(pdf).getAllPages()) {
            auto annotations = page.getObjectHandle().getKey("/Annots");
            if (!annotations.isArray()) continue;
            std::string addedContent;
            for (auto annotation : annotations.getArrayAsVector()) {
                if (!annotation.isDictionary()) continue;
                const bool orphanSignedWidget = annotation.getKey("/Subtype").isNameAndEquals("/Widget") &&
                    annotation.getKey("/FT").isNameAndEquals("/Sig") && !annotation.getKey("/V").isNull();
                if (!signedWidgets.contains(annotation.getObjGen()) && !orphanSignedWidget) continue;
                if (orphanSignedWidget) clearSignatureValue(annotation);
                QPDFAnnotationObjectHelper helper(annotation);
                auto appearance = helper.getAppearanceStream("/N");
                if (!appearance.isStream()) { result.signatureAppearancesMayDiffer = true; continue; }
                const auto flags = helper.getFlags();
                // Preserve unusual screen/print visibility and zoom behavior
                // in the original appearance rather than changing it through
                // page content. The signature-removal warning remains visible.
                if (!(flags & an_print) || (flags & (an_invisible | an_hidden | an_no_view | an_no_zoom))) {
                    result.signatureAppearancesMayDiffer = true;
                    continue;
                }
                auto resources = page.getAttribute("/Resources", true);
                if (!resources.isDictionary()) {
                    resources = Object::newDictionary();
                    page.getObjectHandle().replaceKey("/Resources", resources);
                }
                int suffix = 1;
                const auto name = resources.getUniqueResourceName("/IPS2PDFSignature", suffix);
                const auto rotate = page.getAttribute("/Rotate", false);
                const int rotation = rotate.isInteger() ? rotate.getIntValueAsInt() : 0;
                const auto content = helper.getPageContentForAppearance(name, rotation);
                if (content.empty()) { result.signatureAppearancesMayDiffer = true; continue; }
                auto xobjects = resources.getKey("/XObject");
                xobjects = xobjects.isDictionary() ? xobjects.shallowCopy() : Object::newDictionary();
                xobjects.replaceKey(name, appearance);
                resources.replaceKey("/XObject", xobjects);
                // PDFKit hides AP on an unsigned signature widget. Reuse the
                // original vector appearance as page content and keep an empty
                // widget for its form/accessibility semantics. Mark the visual
                // duplicate as an artifact; no page or text is rasterized.
                addedContent += "/Artifact BMC\n" + content + "\nEMC\n";
                auto empty = pdf.newStream("");
                empty.getDict().replaceKey("/Type", Object::newName("/XObject"));
                empty.getDict().replaceKey("/Subtype", Object::newName("/Form"));
                empty.getDict().replaceKey("/BBox", appearance.getDict().getKey("/BBox"));
                annotation.replaceKey("/AP", Object::newDictionary({{"/N", empty}}));
                annotation.removeKey("/AS");
            }
            if (!addedContent.empty()) {
                // Isolate pre-existing page graphics state from the appended
                // appearance. Existing content streams stay byte-identical.
                page.addPageContents(pdf.newStream("q\n"), true);
                page.addPageContents(pdf.newStream("Q\n" + addedContent), false);
            }
        }
    }

    void walk(Object object, unsigned depth) {
        checkPDFProcessing();
        if (depth > 256) throw std::runtime_error("PDF object hierarchy exceeds the processing limit");
        if (object.isIndirect() && !visited.insert(object.getObjGen()).second) return;
        if (object.isArray()) {
            for (auto child : object.getArrayAsVector()) walk(child, depth + 1);
            return;
        }
        const bool stream = object.isStream();
        auto dictionary = stream ? object.getDict() : object;
        if (!dictionary.isDictionary()) return;
        if (!stream && anonymizeSignatureFont(object)) ++result.signatureFontsAnonymized;
        for (const char* key : {"/Metadata", "/PieceInfo"}) remove(dictionary, key);
        auto type = dictionary.getKey("/Type");
        auto subtype = dictionary.getKey("/Subtype");
        if (subtype.isNameAndEquals("/Widget") && dictionary.getKey("/FT").isNameAndEquals("/Sig") &&
            !dictionary.getKey("/V").isNull()) {
            clearSignatureValue(dictionary);
        }
        if (type.isNameAndEquals("/Catalog")) {
            for (const char* key : {"/SpiderInfo", "/Legal"}) remove(dictionary, key);
        }
        if (type.isNameAndEquals("/Page") || subtype.isNameAndEquals("/Form") || subtype.isNameAndEquals("/Image")) {
            for (const char* key : {"/LastModified", "/Thumb"}) remove(dictionary, key);
        }
        const bool annotation = type.isNameAndEquals("/Annot") ||
            (dictionary.hasKey("/Rect") && subtype.isName());
        if (annotation) {
            for (const char* key : {"/M", "/CreationDate"}) remove(dictionary, key);
            if (!subtype.isNameAndEquals("/Widget")) {
                remove(dictionary, "/T");
                remove(dictionary, "/Subj");
            }
            // /NM can be a JavaScript lookup key; /IRT links reply objects.
            // These functional identifiers and all comment text are retained.
        }
        if (type.isNameAndEquals("/EmbeddedFile")) {
            auto parameters = dictionary.getKey("/Params");
            if (parameters.isDictionary()) {
                remove(parameters, "/CreationDate");
                remove(parameters, "/ModDate");
            }
        }
        if (stream && subtype.isNameAndEquals("/Image") && isJPEGStream(object)) {
            if (cleanJPEGStream(pdf, object, true)) ++result.jpegStreamsCleaned;
        }
        if (stream && subtype.isNameAndEquals("/Image")) cleanBinaryImageStream(pdf, object);
        for (const auto& key : dictionary.getKeys()) walk(dictionary.getKey(key), depth + 1);
    }
};
} // namespace

PDFSanitizationResult sanitizePDFMetadata(QPDF& pdf, const PDFMetadataRetention& retention) {
    return Sanitizer(pdf).run(retention);
}

PDFSanitizationResult invalidatePDFDigitalSignatures(QPDF& pdf) {
    return Sanitizer(pdf).signaturesOnly();
}
} // namespace ips2pdf
