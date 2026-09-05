#include "PDFConformityMetadata.h"

#include <libxml/parser.h>
#include <libxml/tree.h>
#include <algorithm>
#include <qpdf/QUtil.hh>
#include <ctime>
#include <iomanip>
#include <sstream>
#include <map>
#include <memory>
#include <set>
#include <stdexcept>
#include <string>
#include <vector>

namespace ips2pdf {
namespace {
constexpr auto rdf = "http://www.w3.org/1999/02/22-rdf-syntax-ns#";
constexpr auto dc = "http://purl.org/dc/elements/1.1/";
constexpr auto pdfa = "http://www.aiim.org/pdfa/ns/id/";
constexpr auto pdfua = "http://www.aiim.org/pdfua/ns/id/";
constexpr auto pdfx = "http://www.npes.org/pdfx/ns/id/";
constexpr auto legacyPDFX = "http://ns.adobe.com/pdfx/1.3/";
constexpr auto pdfSchema = "http://ns.adobe.com/pdf/1.3/";
constexpr auto xmp = "http://ns.adobe.com/xap/1.0/";
constexpr auto xmpMM = "http://ns.adobe.com/xap/1.0/mm/";
constexpr auto extension = "http://www.aiim.org/pdfa/ns/extension/";
constexpr auto schema = "http://www.aiim.org/pdfa/ns/schema#";
constexpr auto property = "http://www.aiim.org/pdfa/ns/property#";

const xmlChar* xml(const char* value) { return reinterpret_cast<const xmlChar*>(value); }
const xmlChar* xml(const std::string& value) { return xml(value.c_str()); }
std::string str(const xmlChar* value) { return value ? reinterpret_cast<const char*>(value) : ""; }
std::string uri(xmlNode* node) { return node->ns ? str(node->ns->href) : ""; }
bool named(xmlNode* node, const char* space, const char* name) {
    return node && node->type == XML_ELEMENT_NODE && uri(node) == space && str(node->name) == name;
}
std::string value(xmlNode* node) {
    auto text = xmlNodeGetContent(node);
    auto result = str(text);
    xmlFree(text);
    return result;
}
std::string attribute(xmlNode* node, const char* space, const char* name) {
    auto text = xmlGetNsProp(node, xml(name), xml(space));
    auto result = str(text);
    xmlFree(text);
    return result;
}
bool nonempty(const std::string& text) { return text.find_first_not_of(" \t\r\n") != std::string::npos; }

std::string newDocumentID() {
    unsigned char bytes[16]; QUtil::initializeWithRandomBytes(bytes, sizeof(bytes));
    bytes[6] = (bytes[6] & 15) | 0x40; bytes[8] = (bytes[8] & 63) | 0x80;
    std::ostringstream output; output << "uuid:" << std::hex << std::setfill('0');
    for (int i = 0; i < 16; ++i) {
        if (i == 4 || i == 6 || i == 8 || i == 10) output << '-';
        output << std::setw(2) << unsigned(bytes[i]);
    }
    return output.str();
}

class Metadata {
public:
    explicit Metadata(QPDF& pdf) {
        auto info = pdf.getTrailer().getKey("/Info");
        if (info.isDictionary()) {
            for (const char* key : {"/GTS_PDFXVersion", "/GTS_PDFXConformance"}) {
                auto entry = info.getKey(key);
                if (!entry.isNull()) {
                    if (!entry.isString()) throw PDFConformityError("The PDF/X Info declaration is not a text string");
                    record(pdfx, std::string(key).substr(1), entry.getUTF8Value());
                }
            }
            if (info.hasKey("/GTS_PDFA1Version")) throw PDFConformityError("This Info-based conformity declaration cannot yet be preserved safely");
            auto trap = info.getKey("/Trapped");
            if (trap.isName()) trapped.insert(trap.getName().substr(1));
        }
        auto stream = pdf.getRoot().getKey("/Metadata");
        if (stream.isNull()) return;
        if (!stream.isStream()) throw PDFConformityError("The conformity metadata is not a readable XMP stream");
        auto data = stream.getStreamData();
        if (data->getSize() > 16 * 1024 * 1024) throw PDFConformityError("The conformity metadata exceeds the processing limit");
        document.reset(xmlReadMemory(reinterpret_cast<const char*>(data->getBuffer()),
                                     static_cast<int>(data->getSize()), "private-xmp", nullptr,
                                     XML_PARSE_NONET | XML_PARSE_NOERROR | XML_PARSE_NOWARNING));
        // Never load DTDs or resolve external entities. Do not use NOENT or
        // HUGE: libxml's built-in expansion and nesting limits stay enabled.
        if (!document || document->intSubset || document->extSubset)
            throw PDFConformityError("The conformity metadata is malformed or contains a DTD");
        scan(xmlDocGetRootElement(document.get()), 0);
    }

    PDFMetadataRetention retention() {
        PDFMetadataRetention output;
        if (values.empty()) return output;
        std::map<std::string, std::string> ids;
        for (const auto& [key, entries] : values) {
            if (entries.size() != 1) throw PDFConformityError("The PDF contains conflicting conformity metadata");
            ids[key] = *entries.begin();
        }
        const auto a = ids.find(std::string(pdfa) + "|part");
        const auto ua = ids.find(std::string(pdfua) + "|part");
        const auto x = ids.find(std::string(pdfx) + "|GTS_PDFXVersion");
        if (a == ids.end() && ua == ids.end() && x == ids.end()) throw PDFConformityError("The PDF conformity declaration is incomplete");
        const auto get = [&](const char* space, const char* name) {
            auto found = ids.find(std::string(space) + "|" + name);
            return found == ids.end() ? std::string() : found->second;
        };
        if (a != ids.end()) {
            const auto part = a->second;
            const auto level = get(pdfa, "conformance");
            const bool valid = (part == "1" && (level == "A" || level == "B")) ||
                ((part == "2" || part == "3") && (level == "A" || level == "B" || level == "U")) ||
                (part == "4" && (level.empty() || level == "E" || level == "F") && get(pdfa, "rev") == "2020");
            if (!valid) throw PDFConformityError("This PDF/A declaration is unsupported or incomplete");
        }
        if (ua != ids.end()) {
            if (ua->second != "1" && !(ua->second == "2" && get(pdfua, "rev") == "2024"))
                throw PDFConformityError("This PDF/UA declaration is unsupported or incomplete");
            if (titles.empty()) throw PDFConformityError("PDF/UA requires a meaningful document title; none could be preserved");
            // UA-2 requires PDF 2.0 and cannot be combined with an older A part.
            if (ua->second == "2" && a != ids.end() && a->second != "4")
                throw PDFConformityError("The PDF/A and PDF/UA declarations conflict");
        }
        bool legacyX = false;
        std::string trap, nowISO, nowPDF;
        if (x != ids.end()) {
            const std::set<std::string> legacy{"PDF/X-1:2001", "PDF/X-1a:2003", "PDF/X-3:2002", "PDF/X-3:2003"};
            legacyX = legacy.contains(x->second);
            if (!legacyX && x->second != "PDF/X-4" && x->second != "PDF/X-4p")
                throw PDFConformityError("This PDF/X variant requires additional conformity metadata support");
            if (!legacyX && a != ids.end() && a->second == "1")
                throw PDFConformityError("The PDF/A and PDF/X declarations require incompatible PDF versions");
            const auto conformance = get(pdfx, "GTS_PDFXConformance");
            if (x->second == "PDF/X-1:2001" && conformance != "PDF/X-1a:2001")
                throw PDFConformityError("This early PDF/X declaration is unsupported or incomplete");
            if (!conformance.empty() && !(x->second == "PDF/X-1:2001" && conformance == "PDF/X-1a:2001") && conformance != x->second)
                throw PDFConformityError("The PDF/X version and conformance declarations conflict");
            if (trapped.size() != 1 || (*trapped.begin() != "True" && *trapped.begin() != "False"))
                throw PDFConformityError("PDF/X requires an unambiguous trapped state; none could be preserved");
            trap = *trapped.begin();
            // This is a freshly rewritten PDF. Required dates describe this
            // rewrite, not the source document's private creation history.
            const auto now = std::time(nullptr); std::tm utc{};
            if (!gmtime_r(&now, &utc)) throw PDFConformityError("Could not generate required PDF/X dates");
            char iso[32], pdfDate[32];
            std::strftime(iso, sizeof(iso), "%Y-%m-%dT%H:%M:%SZ", &utc);
            std::strftime(pdfDate, sizeof(pdfDate), "D:%Y%m%d%H%M%SZ", &utc);
            nowISO = iso; nowPDF = pdfDate;
            if (legacyX) {
                output.infoStrings["/GTS_PDFXVersion"] = x->second;
                if (!conformance.empty()) output.infoStrings["/GTS_PDFXConformance"] = conformance;
                output.infoStrings["/Title"] = "Document";
                if (ua != ids.end()) {
                    auto title = titles.find("x-default");
                    if (title == titles.end() || title->second.size() != 1) throw PDFConformityError("The required default document title cannot be preserved consistently");
                    output.infoStrings["/Title"] = *title->second.begin();
                }
                output.infoStrings["/CreationDate"] = nowPDF; output.infoStrings["/ModDate"] = nowPDF;
                output.trappedState = trap;
                if (a == ids.end() && ua == ids.end()) return output;
            }
        }

        std::unique_ptr<xmlDoc, decltype(&xmlFreeDoc)> clean(xmlNewDoc(xml("1.0")), xmlFreeDoc);
        auto root = xmlNewNode(nullptr, xml("xmpmeta"));
        auto xns = xmlNewNs(root, xml("adobe:ns:meta/"), xml("x"));
        xmlSetNs(root, xns);
        xmlDocSetRootElement(clean.get(), root);
        auto rns = xmlNewNs(root, xml(rdf), xml("rdf"));
        auto rdfNode = xmlNewChild(root, rns, xml("RDF"), nullptr);
        auto description = xmlNewChild(rdfNode, rns, xml("Description"), nullptr);
        xmlNewNsProp(description, rns, xml("about"), xml(""));
        auto ans = xmlNewNs(description, xml(pdfa), xml("pdfaid"));
        auto uns = xmlNewNs(description, xml(pdfua), xml("pdfuaid"));
        auto xids = x != ids.end() && !legacyX ? xmlNewNs(description, xml(pdfx), xml("pdfxid")) : nullptr;
        for (const auto& [key, text] : ids) {
            const auto split = key.find('|');
            const auto space = key.substr(0, split);
            if (space == pdfx && legacyX) continue;
            if (space == pdfx && key.substr(split + 1) == "GTS_PDFXConformance") continue;
            xmlNewTextChild(description, space == pdfa ? ans : space == pdfx ? xids : uns,
                            xml(key.substr(split + 1)), xml(text));
        }
        if (ua != ids.end() || x != ids.end()) {
            auto dns = xmlNewNs(description, xml(dc), xml("dc"));
            auto title = xmlNewChild(description, dns, xml("title"), nullptr);
            auto alternative = xmlNewChild(title, rns, xml("Alt"), nullptr);
            auto language = xmlSearchNsByHref(clean.get(), root, xml("http://www.w3.org/XML/1998/namespace"));
            const auto retainedTitles = ua != ids.end() ? titles : std::map<std::string, std::set<std::string>>{{"x-default", {"Document"}}};
            for (const auto& [locale, texts] : retainedTitles) {
                if (texts.size() != 1 || !nonempty(*texts.begin()))
                    throw PDFConformityError("The PDF/UA document title is empty or conflicting");
                auto item = xmlNewTextChild(alternative, rns, xml("li"), xml(*texts.begin()));
                xmlNewNsProp(item, language, xml("lang"), xml(locale));
            }
        }
        if (x != ids.end()) {
            auto xns = xmlNewNs(description, xml(xmp), xml("xmp"));
            for (const char* field : {"CreateDate", "ModifyDate", "MetadataDate"})
                xmlNewTextChild(description, xns, xml(field), xml(nowISO));
            auto pns = xmlNewNs(description, xml(pdfSchema), xml("pdf"));
            xmlNewTextChild(description, pns, xml("Trapped"), xml(trap));
            if (!legacyX) {
                auto mm = xmlNewNs(description, xml(xmpMM), xml("xmpMM"));
                xmlNewTextChild(description, mm, xml("DocumentID"), xml(newDocumentID()));
                xmlNewTextChild(description, mm, xml("VersionID"), xml("1"));
                if (renditions.size() > 1) throw PDFConformityError("The PDF/X rendition class is conflicting");
                const auto rendition = renditions.empty() ? "default" : *renditions.begin();
                if (!nonempty(rendition)) throw PDFConformityError("The PDF/X rendition class is empty");
                xmlNewTextChild(description, mm, xml("RenditionClass"), xml(rendition));
            }
        }
        if (a != ids.end() && a->second != "4" && (ua != ids.end() || (x != ids.end() && !legacyX)))
            addIdentificationSchemas(description, rns, ids, !legacyX);
        xmlChar* bytes = nullptr;
        int length = 0;
        xmlDocDumpMemoryEnc(clean.get(), &bytes, &length, "UTF-8");
        if (!bytes) throw PDFConformityError("Could not write minimal conformity metadata");
        output.xmp.assign(reinterpret_cast<char*>(bytes), length);
        xmlFree(bytes);
        return output;
    }

private:
    std::unique_ptr<xmlDoc, decltype(&xmlFreeDoc)> document{nullptr, xmlFreeDoc};
    std::map<std::string, std::set<std::string>> values;
    std::map<std::string, std::set<std::string>> titles;
    std::set<std::string> trapped, renditions;

    void record(const std::string& space, const std::string& name, const std::string& text) {
        if ((space == pdfx || space == legacyPDFX) && (name == "GTS_PDFXVersion" || name == "GTS_PDFXConformance")) {
            values[std::string(pdfx) + "|" + name].insert(text);
        } else if (space == pdfSchema && name == "Trapped") trapped.insert(text);
        else if (space == xmpMM && name == "RenditionClass") renditions.insert(text);
        else if (space == pdfa || space == pdfua) {
            if (name != "part" && name != "conformance" && name != "rev" && name != "amd" && name != "corr")
                throw PDFConformityError("An unknown conformity identification property cannot be preserved safely");
            values[space + "|" + name].insert(text);
        } else if (space.find("/id/") != std::string::npos || name.starts_with("GTS_PDF")) {
            throw PDFConformityError("This conformity family cannot yet be preserved safely");
        }
    }

    void scan(xmlNode* node, unsigned depth) {
        if (depth > 128) throw PDFConformityError("The XMP hierarchy exceeds the processing limit");
        for (; node; node = node->next) {
            if (named(node, rdf, "Description") && named(node->parent, rdf, "RDF")) {
                const auto subject = attribute(node, rdf, "about");
                if (!subject.empty() || !attribute(node, rdf, "nodeID").empty())
                    throw PDFConformityError("The XMP contains a non-document RDF subject that cannot be classified safely");
                for (auto prop = node->properties; prop; prop = prop->next) {
                    auto text = xmlNodeListGetString(document.get(), prop->children, 1);
                    record(prop->ns ? str(prop->ns->href) : "", str(prop->name), str(text));
                    xmlFree(text);
                }
                for (auto child = node->children; child; child = child->next) {
                    if (child->type != XML_ELEMENT_NODE) continue;
                    if (named(child, dc, "title")) {
                        bool alternativeFound = false;
                        for (auto alt = child->children; alt; alt = alt->next) if (named(alt, rdf, "Alt")) {
                            alternativeFound = true;
                            for (auto item = alt->children; item; item = item->next) if (named(item, rdf, "li")) {
                                auto locale = attribute(item, "http://www.w3.org/XML/1998/namespace", "lang");
                                if (locale.empty()) throw PDFConformityError("An XMP title alternative has no language");
                                titles[locale].insert(value(item));
                            }
                        }
                        if (!alternativeFound && nonempty(value(child))) titles["x-default"].insert(value(child));
                    } else record(uri(child), str(child->name), value(child));
                }
            }
            scan(node->children, depth + 1);
        }
    }

    static void addIdentificationSchemas(xmlNode* description, xmlNs* rns, const std::map<std::string, std::string>& ids, bool includeX) {
        // A-1/2/3 require an extension schema for the retained UA properties.
        // Rebuild only that technical schema; discard unrelated custom schema
        // descriptions along with the custom metadata that used them.
        auto ens = xmlNewNs(description, xml(extension), xml("pdfaExtension"));
        auto sns = xmlNewNs(description, xml(schema), xml("pdfaSchema"));
        auto pns = xmlNewNs(description, xml(property), xml("pdfaProperty"));
        auto schemas = xmlNewChild(description, ens, xml("schemas"), nullptr);
        auto bag = xmlNewChild(schemas, rns, xml("Bag"), nullptr);
        for (const char* space : {pdfua, pdfx}) {
        if (space == pdfx && !includeX) continue;
        const std::string prefix = std::string(space) + "|";
        if (std::none_of(ids.begin(), ids.end(), [&](const auto& item) { return item.first.starts_with(prefix); })) continue;
        auto item = xmlNewChild(bag, rns, xml("li"), nullptr);
        xmlNewNsProp(item, rns, xml("parseType"), xml("Resource"));
        xmlNewTextChild(item, sns, xml("schema"), xml(space == pdfua ? "PDF/UA identification schema" : "PDF/X identification schema"));
        xmlNewTextChild(item, sns, xml("namespaceURI"), xml(space));
        xmlNewTextChild(item, sns, xml("prefix"), xml(space == pdfua ? "pdfuaid" : "pdfxid"));
        auto properties = xmlNewChild(item, sns, xml("property"), nullptr);
        auto sequence = xmlNewChild(properties, rns, xml("Seq"), nullptr);
        for (const auto& [key, unused] : ids) if (key.starts_with(prefix)) {
            const auto name = key.substr(key.find('|') + 1);
            if (space == pdfx && name == "GTS_PDFXConformance") continue;
            auto entry = xmlNewChild(sequence, rns, xml("li"), nullptr);
            xmlNewNsProp(entry, rns, xml("parseType"), xml("Resource"));
            xmlNewTextChild(entry, pns, xml("name"), xml(name));
            xmlNewTextChild(entry, pns, xml("valueType"), xml(name == "part" ? "Integer" : "Text"));
            xmlNewTextChild(entry, pns, xml("category"), xml("internal"));
            xmlNewTextChild(entry, pns, xml("description"), xml(space == pdfua ? "PDF/UA conformance identification" : "PDF/X conformance identification"));
        }
        }
    }
};
} // namespace

PDFMetadataRetention metadataPreservingConformity(QPDF& pdf) {
    return Metadata(pdf).retention();
}
} // namespace ips2pdf
