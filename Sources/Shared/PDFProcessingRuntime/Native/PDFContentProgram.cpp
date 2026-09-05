#include "PDFProcessingUnsupported.h"
#include "PDFContentProgram.h"
#include "PDFProcessingControl.h"
#include <qpdf/Pipeline.hh>
#include <qpdf/QPDFPageDocumentHelper.hh>
#include <algorithm>
#include <cmath>
#include <limits>
#include <functional>
#include <set>
#include <stdexcept>

namespace ips2pdf {
namespace {
using Object = QPDFObjectHandle;
constexpr size_t maximumContentBytes = 64 * 1024 * 1024;

class ContentBuffer : public Pipeline {
public:
    ContentBuffer() : Pipeline("private PDF content", nullptr) {}
    void write(const unsigned char* data, size_t size) override {
        checkPDFProcessing();
        if (size > maximumContentBytes - bytes.size()) throw PDFProcessingStopped(false);
        bytes.append(reinterpret_cast<const char*>(data), size);
    }
    void finish() override { checkPDFProcessing(); }
    std::string bytes;
};

class ContentComments : public Object::TokenFilter {
public:
    bool changed = false;
    void handleToken(const QPDFTokenizer::Token& token) override {
        checkPDFProcessing();
        if (token.getType() == QPDFTokenizer::tt_comment) { write("\n"); changed = true; }
        else writeToken(token);
    }
};

class Operations : public Object::ParserCallbacks {
public:
    explicit Operations(PDFContentProgram& result) : result(result) {}
    void handleObject(Object object, size_t offset, size_t length) override {
        checkPDFProcessing();
        if (offset > result.bytes.size() || length > result.bytes.size() - offset)
            throw std::runtime_error("Invalid PDF content token offsets");
        if (object.isInlineImage())
            throw std::runtime_error("Inline PDF images must be externalized before compression");
        if (operands.empty()) start = offset;
        if (object.isOperator()) {
            result.operations.push_back({object.getOperatorValue(), std::move(operands), start, offset + length});
            operands.clear();
            if (result.operations.size() > 1'000'000) throw PDFProcessingStopped(false);
        } else {
            operands.push_back(object);
            if (operands.size() > 1'024) throw std::runtime_error("Invalid PDF content operand count");
        }
    }
    void handleEOF() override {
        if (!operands.empty()) throw std::runtime_error("Unterminated PDF content operation");
    }
private:
    PDFContentProgram& result;
    std::vector<Object> operands;
    size_t start = 0;
};

class Census {
public:
    explicit Census(QPDF& pdf) : pdf(pdf) {}
    std::map<QPDFObjGen, PDFImagePlacement> run() {
        for (auto page : QPDFPageDocumentHelper(pdf).getAllPages()) {
            auto userUnit = page.getObjectHandle().getKey("/UserUnit");
            const double unit = userUnit.isNull() ? 1 : userUnit.isNumber() ? userUnit.getNumericValue() : 0;
            if (!std::isfinite(unit) || unit <= 0) throw std::runtime_error("Invalid PDF UserUnit");
            PDFPlacementMatrix matrix;
            matrix.a = matrix.d = unit;
            visit(page.getObjectHandle(), page.getAttribute("/Resources", false), matrix, 0);
        }
        return images;
    }
private:
    QPDF& pdf;
    std::map<QPDFObjGen, PDFImagePlacement> images;
    std::map<QPDFObjGen, PDFContentProgram> programs;
    std::set<QPDFObjGen> active;
    uint64_t operations = 0;

    void visit(Object holder, Object resources, PDFPlacementMatrix matrix, unsigned depth) {
        checkPDFProcessing();
        if (depth > 64 || !active.insert(holder.getObjGen()).second)
            throw std::runtime_error("Recursive PDF form content");
        auto found = programs.find(holder.getObjGen());
        if (found == programs.end()) found = programs.emplace(holder.getObjGen(), readPDFContent(pdf, holder)).first;
        // std::map keeps the program reference valid while nested forms add
        // their own entries. Every placement still gets its own matrix stack.
        const auto& program = found->second;
        std::vector<PDFPlacementMatrix> stack;
        for (const auto& operation : program.operations) {
            checkPDFProcessing();
            if (++operations > 4'000'000) throw PDFProcessingStopped(false);
            if (operation.name == "q") {
                if (!operation.operands.empty() || stack.size() >= 256) throw std::runtime_error("Invalid PDF graphics state stack");
                stack.push_back(matrix);
            } else if (operation.name == "Q") {
                if (!operation.operands.empty() || stack.empty()) throw std::runtime_error("Unbalanced PDF graphics state stack");
                matrix = stack.back(); stack.pop_back();
            } else if (operation.name == "cm") {
                matrix = matrix.concatenated(PDFPlacementMatrix::fromOperands(operation.operands));
            } else if (operation.name == "Do") {
                if (operation.operands.size() != 1 || !operation.operands.front().isName())
                    throw std::runtime_error("Invalid PDF XObject invocation");
                auto xobjects = resources.isDictionary() ? resources.getKey("/XObject") : Object::newNull();
                auto object = xobjects.isDictionary() ? xobjects.getKey(operation.operands.front().getName()) : Object::newNull();
                if (!object.isStream()) throw std::runtime_error("Missing PDF XObject resource");
                auto dictionary = object.getDict();
                auto subtype = dictionary.getKey("/Subtype");
                if (subtype.isNameAndEquals("/Image")) record(object, matrix);
                else if (subtype.isNameAndEquals("/Form")) {
                    auto transform = dictionary.getKey("/Matrix");
                    const auto nested = transform.isNull() ? matrix : transform.isArray()
                        ? matrix.concatenated(PDFPlacementMatrix::fromOperands(transform.getArrayAsVector()))
                        : throw std::runtime_error("Invalid PDF form matrix");
                    auto nestedResources = dictionary.getKey("/Resources");
                    if (nestedResources.isNull()) nestedResources = resources;
                    visit(object, nestedResources, nested, depth + 1);
                }
            }
        }
        if (!stack.empty()) throw std::runtime_error("Unbalanced PDF graphics state stack");
        active.erase(holder.getObjGen());
    }
    void record(Object image, const PDFPlacementMatrix& matrix) {
        auto dictionary = image.getDict();
        auto width = dictionary.getKey("/Width"), height = dictionary.getKey("/Height");
        if (!width.isInteger() || !height.isInteger() || width.getIntValue() <= 0 || height.getIntValue() <= 0)
            throw std::runtime_error("Invalid PDF image dimensions");
        auto& entry = images[image.getObjGen()];
        entry.image = image;
        ++entry.placements;
        const double x = std::hypot(matrix.a, matrix.b), y = std::hypot(matrix.c, matrix.d);
        if (!std::isfinite(x) || !std::isfinite(y)) throw std::runtime_error("Invalid PDF image placement");
        if (x == 0 || y == 0) return;
        const double ppi = std::min(72.0 * width.getIntValue() / x, 72.0 * height.getIntValue() / y);
        if (!std::isfinite(ppi) || ppi <= 0) throw std::runtime_error("Invalid effective PDF image resolution");
        entry.minimumPPI = entry.minimumPPI > 0 ? std::min(entry.minimumPPI, ppi) : ppi;
    }
};
} // namespace

PDFContentProgram readPDFContent(QPDF& pdf, Object holder) {
    ContentBuffer buffer;
    if (holder.isStream()) {
        if (!holder.pipeStreamData(&buffer, 0, qpdf_dl_specialized))
            throw std::runtime_error("Unsupported PDF content filter");
    } else { QPDFPageObjectHelper(holder).pipeContents(&buffer); }
    PDFContentProgram result{std::move(buffer.bytes), {}};
    Operations reader(result);
    pdf.newStream(result.bytes).parseAsContents(&reader);
    checkPDFProcessing();
    return result;
}

PDFPlacementMatrix PDFPlacementMatrix::fromOperands(const std::vector<Object>& operands) {
    if (operands.size() != 6) throw std::runtime_error("Invalid PDF transformation matrix");
    double values[6];
    for (size_t i = 0; i < 6; ++i) {
        if (!operands[i].isNumber()) throw std::runtime_error("Invalid PDF transformation matrix");
        values[i] = operands[i].getNumericValue();
        if (!std::isfinite(values[i])) throw std::runtime_error("Invalid PDF transformation matrix");
    }
    return {values[0], values[1], values[2], values[3], values[4], values[5]};
}
PDFPlacementMatrix PDFPlacementMatrix::concatenated(const PDFPlacementMatrix& n) const {
    return {a*n.a + c*n.b, b*n.a + d*n.b, a*n.c + c*n.d, b*n.c + d*n.d,
            a*n.e + c*n.f + e, b*n.e + d*n.f + f};
}
std::map<QPDFObjGen, PDFImagePlacement> pdfImagePlacements(QPDF& pdf) { return Census(pdf).run(); }

void externalizePDFInlineImages(QPDF& pdf) {
    struct Holder { Object object, resources; std::string context; };
    std::map<QPDFObjGen, Holder> holders;
    std::set<std::pair<QPDFObjGen, std::string>> seen;
    std::function<void(Object, Object, bool, unsigned)> collect = [&](Object object, Object resources, bool appearance, unsigned depth) {
        checkPDFProcessing();
        if (depth > 256) throw std::runtime_error("PDF content hierarchy exceeds the processing limit");
        auto dictionary = object.isStream() ? object.getDict() : object;
        if (dictionary.isDictionary() && dictionary.getKey("/Resources").isDictionary()) resources = dictionary.getKey("/Resources");
        const auto context = resources.unparse();
        if (object.isIndirect() && !seen.emplace(object.getObjGen(), context).second) return;
        const bool form = object.isStream() && (appearance || dictionary.getKey("/Subtype").isNameAndEquals("/Form") ||
            dictionary.hasKey("/PatternType"));
        const bool page = dictionary.isDictionary() && dictionary.getKey("/Type").isNameAndEquals("/Page");
        if (form || page) {
            auto found = holders.find(object.getObjGen());
            if (found != holders.end() && found->second.context != context)
                throw PDFProcessingUnsupported("A shared PDF form has conflicting inherited resources");
            holders[object.getObjGen()] = {object, resources, context};
        }
        if (object.isArray()) for (auto child : object.getArrayAsVector()) collect(child, resources, appearance, depth + 1);
        if (dictionary.isDictionary()) for (const auto& key : dictionary.getKeys()) {
            if (key == "/Parent" || key == "/P" || key == "/Pages" || key == "/FontFile" || key == "/FontFile2" || key == "/FontFile3") continue;
            collect(dictionary.getKey(key), resources, key == "/AP" || (appearance && !object.isStream()), depth + 1);
        }
    };
    for (auto page : QPDFPageDocumentHelper(pdf).getAllPages())
        collect(page.getObjectHandle(), page.getAttribute("/Resources", false), false, 0);
    collect(pdf.getRoot(), Object::newNull(), false, 0);
    for (auto& [id, holder] : holders) {
        checkPDFProcessing();
        auto dictionary = holder.object.isStream() ? holder.object.getDict() : holder.object;
        // Own the resource dictionary before qpdf adds image names. In
        // particular, an inherited form must not lose its original fonts.
        dictionary.replaceKey("/Resources", holder.resources.isDictionary() ? holder.resources.shallowCopy() : Object::newDictionary());
        auto subtype = dictionary.getKey("/Subtype");
        if (holder.object.isStream()) dictionary.replaceKey("/Subtype", Object::newName("/Form"));
        try {
            ContentBuffer bounded;
            QPDFPageObjectHelper helper(holder.object);
            helper.pipeContents(&bounded);
            helper.externalizeInlineImages(0, true);
            ContentComments comments;
            ContentBuffer cleaned;
            helper.filterContents(&comments, &cleaned);
            if (comments.changed) {
                if (holder.object.isStream()) holder.object.replaceStreamData(cleaned.bytes, Object::newNull(), Object::newNull());
                else holder.object.replaceKey("/Contents", pdf.newStream(cleaned.bytes));
            }
            if (pdf.anyWarnings()) throw std::runtime_error("An inline PDF image could not be safely externalized");
        } catch (...) {
            if (holder.object.isStream()) dictionary.replaceKey("/Subtype", subtype);
            throw;
        }
        if (holder.object.isStream()) dictionary.replaceKey("/Subtype", subtype);
    }
}
} // namespace ips2pdf
