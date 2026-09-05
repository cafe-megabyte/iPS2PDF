#include "PDFColorProgram.h"
#include "PDFContentProgram.h"
#include "PDFImageCodec.h"
#include "PDFProcessingControl.h"
#include "PDFProcessingUnsupported.h"
#include <qpdf/QPDFPageDocumentHelper.hh>
#include <array>
#include <cmath>
#include <iomanip>
#include <map>
#include <set>
#include <sstream>
#include <stdexcept>

namespace ips2pdf {
namespace {
using Object = QPDFObjectHandle;
using RGB = std::array<double, 3>;

std::string number(double value) {
    if (!std::isfinite(value)) throw std::runtime_error("Invalid PDF color component");
    std::ostringstream output;
    output.imbue(std::locale::classic());
    output << std::fixed << std::setprecision(8) << value;
    auto text = output.str();
    while (text.size() > 1 && text.back() == '0') text.pop_back();
    if (text.back() == '.') text.pop_back();
    return text == "-0" ? "0" : text;
}
std::vector<double> numeric(const std::vector<Object>& values) {
    std::vector<double> result;
    for (auto value : values) {
        if (!value.isNumber()) throw std::runtime_error("Invalid PDF color operands");
        const double component = value.getNumericValue();
        if (!std::isfinite(component)) throw std::runtime_error("Invalid PDF color operands");
        result.push_back(component);
    }
    return result;
}
bool white(const RGB& value) { return value[0] >= 1 && value[1] >= 1 && value[2] >= 1; }
bool pattern(Object space) {
    return space.isNameAndEquals("/Pattern") ||
        (space.isArray() && space.getArrayNItems() > 0 && space.getArrayItem(0).isNameAndEquals("/Pattern"));
}
bool hasICC(Object object, std::set<QPDFObjGen>& seen, unsigned depth = 0) {
    if (depth > 128) throw std::runtime_error("PDF color hierarchy exceeds the processing limit");
    if (object.isIndirect() && !seen.insert(object.getObjGen()).second) return false;
    if (object.isNameAndEquals("/ICCBased")) return true;
    if (object.isArray()) for (auto item : object.getArrayAsVector()) if (hasICC(item, seen, depth + 1)) return true;
    return false;
}
bool hasICC(Object object) { std::set<QPDFObjGen> seen; return hasICC(object, seen); }

struct Color {
    Object space = Object::newName("/DeviceGray");
    RGB rgb{0, 0, 0};
    bool pattern = false;
};
struct State { Color fill, stroke; };

class Rewriter {
public:
    Rewriter(QPDF& pdf, const PDFCompressionPolicy& policy) : pdf(pdf), policy(policy) {}
    void run() {
        std::set<QPDFObjGen> profileObjects;
        discoverProfiles(pdf.getRoot(), profileObjects, 0);
        collect(pdf.getRoot(), 0);
        for (auto page : QPDFPageDocumentHelper(pdf).getAllPages())
            process(page.getObjectHandle(), page.getAttribute("/Resources", false), {}, 0);
        // Appearance states and tiling patterns can be hidden until a form,
        // layer or annotation is used. They require the same color policy.
        for (auto& [id, holder] : holders) {
            if (!rewritten.contains(id)) process(holder, holder.getDict().getKey("/Resources"), {}, 0);
        }
        for (const auto& [id, bytes] : rewritten) {
            auto holder = pdf.getObject(id);
            if (holder.isStream()) holder.replaceStreamData(bytes, Object::newNull(), Object::newNull());
            else holder.replaceKey("/Contents", pdf.newStream(bytes));
        }
        for (auto dictionary : resourcesToClean) cleanResources(dictionary);
    }
private:
    QPDF& pdf;
    const PDFCompressionPolicy& policy;
    std::map<std::string, std::unique_ptr<PDFColorConverter>> converters;
    std::map<QPDFObjGen, PDFContentProgram> programs;
    std::map<QPDFObjGen, Object> holders;
    std::map<QPDFObjGen, std::string> rewritten;
    std::set<QPDFObjGen> visited, active;
    std::vector<Object> resourcesToClean;
    uint64_t steps = 0;
    bool usesProfiles = false;

    void discoverProfiles(Object object, std::set<QPDFObjGen>& seen, unsigned depth) {
        checkPDFProcessing();
        if (depth > 256) throw std::runtime_error("PDF color hierarchy exceeds the processing limit");
        if (object.isIndirect() && !seen.insert(object.getObjGen()).second) return;
        if (object.isNameAndEquals("/ICCBased")) usesProfiles = true;
        if (object.isArray()) for (auto child : object.getArrayAsVector()) discoverProfiles(child, seen, depth + 1);
        auto dictionary = object.isStream() ? object.getDict() : object;
        if (dictionary.isDictionary()) {
            if (dictionary.hasKey("/OutputIntents")) usesProfiles = true;
            for (const auto& key : dictionary.getKeys()) discoverProfiles(dictionary.getKey(key), seen, depth + 1);
        }
    }

    PDFColorConverter& converter(Object space) {
        // Registration and non-painting colorants have semantics beyond RGB
        // color values. Never make previously invisible marks visible.
        if (space.isArray() && space.getArrayNItems() > 1 && space.getArrayItem(0).isNameAndEquals("/Separation")) {
            auto name = space.getArrayItem(1);
            if (name.isNameAndEquals("/None") || name.isNameAndEquals("/All"))
                throw PDFProcessingUnsupported("Registration or non-painting colorants require a dedicated conversion");
        }
        const auto key = space.unparse();
        auto found = converters.find(key);
        if (found == converters.end()) found = converters.emplace(key, std::make_unique<PDFColorConverter>(pdf, space)).first;
        return *found->second;
    }
    std::string command(const RGB& rgb, bool stroke, bool text = false) const {
        if (!policy.monochrome) return number(rgb[0]) + " " + number(rgb[1]) + " " + number(rgb[2]) + (stroke ? " RG\n" : " rg\n");
        // Colored text and strokes become black; white knockouts stay white.
        // Filled vector areas follow the same threshold as image samples.
        const double luminance = .2126 * rgb[0] + .7152 * rgb[1] + .0722 * rgb[2];
        const bool isWhite = white(rgb) || (!stroke && !text && luminance >= policy.threshold / 100.0);
        return std::string(isWhite ? "1" : "0") + (stroke ? " G\n" : " g\n");
    }
    void collect(Object object, unsigned depth) {
        checkPDFProcessing();
        if (depth > 256) throw std::runtime_error("PDF resource hierarchy exceeds the processing limit");
        if (object.isIndirect() && !visited.insert(object.getObjGen()).second) return;
        if (object.isArray()) {
            for (auto child : object.getArrayAsVector()) collect(child, depth + 1);
            return;
        }
        auto dictionary = object.isStream() ? object.getDict() : object;
        if (!dictionary.isDictionary()) return;
        auto subtype = dictionary.getKey("/Subtype");
        auto patternType = dictionary.getKey("/PatternType");
        if (object.isStream() && (subtype.isNameAndEquals("/Form") ||
            (patternType.isInteger() && patternType.getIntValue() == 1)))
            holders.emplace(object.getObjGen(), object);
        auto group = dictionary.getKey("/Group");
        if (group.isDictionary() && !group.getKey("/CS").isNull() &&
            (usesProfiles || (!group.getKey("/CS").isNameAndEquals("/DeviceRGB") && !group.getKey("/CS").isNameAndEquals("/DeviceGray"))))
            throw PDFProcessingUnsupported("This transparency blending space requires a dedicated color conversion.");
        if (dictionary.hasKey("/ShadingType") && (usesProfiles || hasICC(dictionary.getKey("/ColorSpace"))))
            throw PDFProcessingUnsupported("This shading requires a dedicated color conversion.");
        auto resources = dictionary.getKey("/Resources");
        if (resources.isDictionary()) resourcesToClean.push_back(resources);
        auto defaults = dictionary.getKey("/DR");
        if (defaults.isDictionary()) resourcesToClean.push_back(defaults);
        auto appearance = dictionary.getKey("/DA");
        if (appearance.isString()) {
            auto acroForm = pdf.getRoot().getKey("/AcroForm");
            auto defaultResources = defaults.isDictionary() ? defaults : acroForm.isDictionary() ? acroForm.getKey("/DR") : Object::newNull();
            auto program = pdf.newStream(appearance.getStringValue());
            process(program, defaultResources, {}, 0, true);
            dictionary.replaceKey("/DA", Object::newString(rewritten.at(program.getObjGen())));
        }
        if (dictionary.getKey("/Type").isNameAndEquals("/Annot") || (dictionary.hasKey("/Rect") && subtype.isName())) {
            const auto recolor = [&](Object container, const char* key, bool stroke) {
                auto color = container.getKey(key);
                if (!color.isArray() || color.getArrayNItems() == 0) return;
                const auto count = color.getArrayNItems();
                if (count != 1 && count != 3 && count != 4) throw std::runtime_error("Invalid annotation color component count");
                auto space = Object::newName(count == 1 ? "/DeviceGray" : count == 3 ? "/DeviceRGB" : "/DeviceCMYK");
                const auto rgb = converter(space).rgb(numeric(color.getArrayAsVector()));
                if (policy.monochrome) {
                    const auto selected = command(rgb, stroke);
                    container.replaceKey(key, Object::parse(selected.front() == '1' ? "[1]" : "[0]"));
                } else container.replaceKey(key, Object::parse("[" + number(rgb[0]) + " " + number(rgb[1]) + " " + number(rgb[2]) + "]"));
            };
            recolor(dictionary, "/C", true);
            recolor(dictionary, "/IC", false);
            // Readers may regenerate widget appearances from MK. Keep those
            // background and border colors consistent with the converted AP.
            auto characteristics = dictionary.getKey("/MK");
            if (characteristics.isDictionary()) {
                recolor(characteristics, "/BC", true);
                recolor(characteristics, "/BG", false);
            }
        }

        for (const auto& key : dictionary.getKeys()) {
            // Embedded font programs and Type 3 glyph programs are immutable.
            // Colored Type 3 glyphs need a separate preservation strategy.
            if (key == "/FontFile" || key == "/FontFile2" || key == "/FontFile3") continue;
            if (key == "/CharProcs") {
                if (policy.monochrome || usesProfiles) throw PDFProcessingUnsupported("Type 3 glyph colors cannot be converted while preserving the font program unchanged.");
                continue;
            }
            collect(dictionary.getKey(key), depth + 1);
        }
    }
    void cleanResources(Object resources) {
        auto spaces = resources.getKey("/ColorSpace");
        if (!spaces.isDictionary()) return;
        for (const auto& key : spaces.getKeys()) {
            if (key == "/DefaultRGB" || key == "/DefaultGray" || key == "/DefaultCMYK") {
                spaces.removeKey(key);
            } else if (hasICC(spaces.getKey(key))) {
                if (pattern(spaces.getKey(key))) throw PDFProcessingUnsupported("An ICC pattern base requires a dedicated conversion");
                // All explicit color operations have already become DeviceRGB
                // or DeviceGray operations; retain resource names for scripts.
                spaces.replaceKey(key, Object::newName(policy.monochrome ? "/DeviceGray" : "/DeviceRGB"));
            }
        }
    }
    void process(Object holder, Object resources, State state, unsigned depth, bool textDefaults = false) {
        checkPDFProcessing();
        if (depth > 64 || !active.insert(holder.getObjGen()).second)
            throw std::runtime_error("Recursive PDF color content");
        auto found = programs.find(holder.getObjGen());
        if (found == programs.end()) found = programs.emplace(holder.getObjGen(), readPDFContent(pdf, holder)).first;
        const auto& program = found->second;
        std::string output;
        size_t copied = 0;
        std::vector<State> stack;
        for (const auto& operation : program.operations) {
            checkPDFProcessing();
            if (++steps > 4'000'000) throw PDFProcessingStopped(false);
            const auto& name = operation.name;
            std::string replacement;
            bool replace = false;
            if (name == "q") {
                if (stack.size() >= 256) throw std::runtime_error("Invalid PDF graphics state stack");
                stack.push_back(state);
            } else if (name == "Q") {
                if (stack.empty()) throw std::runtime_error("Unbalanced PDF graphics state stack");
                state = stack.back(); stack.pop_back();
            } else if (name == "g" || name == "G" || name == "rg" || name == "RG" || name == "k" || name == "K" ||
                       name == "cs" || name == "CS" || name == "sc" || name == "SC" || name == "scn" || name == "SCN") {
                const bool stroke = name == "G" || name == "RG" || name == "K" || name == "CS" || name == "SC" || name == "SCN";
                auto& color = stroke ? state.stroke : state.fill;
                if (name == "cs" || name == "CS") {
                    if (operation.operands.size() != 1 || !operation.operands.front().isName()) throw std::runtime_error("Invalid PDF color space operator");
                    color.space = resolvePDFColorSpace(operation.operands.front(), resources);
                    color.pattern = pattern(color.space);
                    if (!color.pattern) {
                        auto& convert = converter(color.space);
                        color.rgb = convert.rgb(convert.defaultValues());
                    }
                } else {
                    if (name == "g" || name == "G") color.space = resolvePDFColorSpace(Object::newName("/DeviceGray"), resources);
                    if (name == "rg" || name == "RG") color.space = resolvePDFColorSpace(Object::newName("/DeviceRGB"), resources);
                    if (name == "k" || name == "K") color.space = resolvePDFColorSpace(Object::newName("/DeviceCMYK"), resources);
                    color.pattern = pattern(color.space);
                    if (!color.pattern) color.rgb = converter(color.space).rgb(numeric(operation.operands));
                }
                if (color.pattern) {
                    if (policy.monochrome || usesProfiles) throw PDFProcessingUnsupported("This pattern requires a dedicated color conversion.");
                } else { replacement = command(color.rgb, stroke, textDefaults); replace = true; }
            } else if (name == "Tj" || name == "TJ" || name == "'" || name == "\"") {
                if (policy.monochrome) {
                    replacement = command(state.fill.rgb, false, true) + command(state.stroke.rgb, true, true) +
                        program.bytes.substr(operation.start, operation.end - operation.start) + "\n" +
                        command(state.fill.rgb, false) + command(state.stroke.rgb, true);
                    replace = true;
                }
            } else if (name == "sh" && policy.monochrome) {
                throw PDFProcessingUnsupported("Shading paints require a dedicated monochrome conversion");
            } else if (name == "Do") {
                if (operation.operands.size() != 1 || !operation.operands.front().isName()) throw std::runtime_error("Invalid PDF XObject invocation");
                auto objects = resources.isDictionary() ? resources.getKey("/XObject") : Object::newNull();
                auto child = objects.isDictionary() ? objects.getKey(operation.operands.front().getName()) : Object::newNull();
                if (child.isStream() && child.getDict().getKey("/Subtype").isNameAndEquals("/Form")) {
                    auto ownResources = child.getDict().getKey("/Resources");
                    process(child, ownResources.isNull() ? resources : ownResources, state, depth + 1);
                }
            } else if (name == "gs") {
                if (operation.operands.size() != 1 || !operation.operands.front().isName()) throw std::runtime_error("Invalid PDF graphics state selection");
                auto states = resources.isDictionary() ? resources.getKey("/ExtGState") : Object::newNull();
                auto settings = states.isDictionary() ? states.getKey(operation.operands.front().getName()) : Object::newNull();
                if (!settings.isDictionary()) throw std::runtime_error("Missing PDF graphics state resource");
                for (const char* key : {"/OP", "/op"}) {
                    if (settings.getKey(key).isBool() && settings.getKey(key).getBoolValue())
                        throw PDFProcessingUnsupported("Overprinting requires a dedicated color conversion");
                }
                if (policy.monochrome) for (const char* key : {"/TR", "/TR2"}) {
                    auto value = settings.getKey(key);
                    if (!value.isNull() && !value.isNameAndEquals("/Identity") && !value.isNameAndEquals("/Default"))
                        throw PDFProcessingUnsupported("Transfer functions require a dedicated monochrome conversion");
                }
            }
            if (replace) {
                if (operation.start < copied) throw std::runtime_error("Overlapping PDF content operations");
                output.append(program.bytes, copied, operation.start - copied);
                output += replacement;
                copied = operation.end;
            }
        }
        output.append(program.bytes, copied, std::string::npos);
        auto existing = rewritten.find(holder.getObjGen());
        if (existing != rewritten.end() && existing->second != output)
            throw PDFProcessingUnsupported("A shared form needs incompatible inherited color conversions");
        rewritten[holder.getObjGen()] = std::move(output);
        active.erase(holder.getObjGen());
    }
};
} // namespace

static Object resolvePDFColorSpaceImpl(Object space, Object resources, bool defaults, unsigned depth) {
    if (depth > 64) throw std::runtime_error("Recursive PDF color space definition");
    auto spaces = resources.isDictionary() ? resources.getKey("/ColorSpace") : Object::newNull();
    std::set<std::string> visited;
    while (space.isName()) {
        auto name = space.getName();
        if (!visited.insert(name).second) throw std::runtime_error("Recursive PDF color space alias");
        const char* fallback = name == "/DeviceRGB" ? "/DefaultRGB" : name == "/DeviceGray" ? "/DefaultGray" :
                               name == "/DeviceCMYK" ? "/DefaultCMYK" : nullptr;
        if (fallback) {
            auto replacement = defaults && spaces.isDictionary() ? spaces.getKey(fallback) : Object::newNull();
            if (replacement.isNull()) return space;
            space = replacement;
            defaults = false;
        } else if (name == "/Pattern") return space;
        else {
            if (!spaces.isDictionary() || !spaces.hasKey(name)) throw std::runtime_error("Missing PDF color space resource");
            space = spaces.getKey(name);
        }
    }
    if (!space.isArray()) throw std::runtime_error("Invalid PDF color space");
    const auto count = space.getArrayNItems();
    if (count > 1) {
        auto type = space.getArrayItem(0);
        const int base = type.isNameAndEquals("/Indexed") || type.isNameAndEquals("/Pattern") ? 1 :
                         type.isNameAndEquals("/Separation") || type.isNameAndEquals("/DeviceN") ? 2 : -1;
        if (base >= 0 && count > base) {
            auto copy = space.shallowCopy();
            copy.setArrayItem(base, resolvePDFColorSpaceImpl(space.getArrayItem(base), resources, defaults, depth + 1));
            return copy;
        }
    }
    return space;
}
Object resolvePDFColorSpace(Object space, Object resources, bool defaults) {
    return resolvePDFColorSpaceImpl(space, resources, defaults, 0);
}
void rewritePDFColors(QPDF& pdf, const PDFCompressionPolicy& policy) { policy.validate(); Rewriter(pdf, policy).run(); }
} // namespace ips2pdf
