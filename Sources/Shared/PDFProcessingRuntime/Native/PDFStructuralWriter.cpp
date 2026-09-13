#include "PDFStructuralWriter.h"
#include "PDFConformityMetadata.h"
#include "PDFProcessingControl.h"
#include "PDFProcessingUnsupported.h"
#include "PDFContentProgram.h"

#include <qpdf/FileInputSource.hh>
#include <qpdf/Pipeline.hh>
#include <qpdf/QPDFWriter.hh>
#include <qpdf/QUtil.hh>
#include <cstdio>
#include <fcntl.h>
#include <functional>
#include <memory>
#include <set>
#include <stdexcept>
#include <sys/stat.h>
#include <unistd.h>

namespace ips2pdf {
namespace {

class CheckedInput : public FileInputSource {
public:
    explicit CheckedInput(const std::filesystem::path& path) {
        const int fd = ::open(path.c_str(), O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
        if (fd < 0) throw std::runtime_error("Could not open the private PDF input");
        try {
            struct stat status{};
            if (fstat(fd, &status) || !S_ISREG(status.st_mode) || status.st_size < 0)
                throw std::runtime_error("The private PDF input is not a regular file");
            checkPDFInputSize(static_cast<uint64_t>(status.st_size));
        } catch (...) { close(fd); throw; }
        FILE* file = fdopen(fd, "rb");
        if (!file) { close(fd); throw std::runtime_error("Could not open the private PDF input"); }
        setFile("private PDF input", file, true);
    }
    size_t read(char* buffer, size_t count) override {
        checkPDFProcessing();
        return FileInputSource::read(buffer, count);
    }
    void seek(qpdf_offset_t offset, int whence) override {
        checkPDFProcessing();
        FileInputSource::seek(offset, whence);
    }
    qpdf_offset_t findAndSkipNextEOL() override {
        checkPDFProcessing();
        return FileInputSource::findAndSkipNextEOL();
    }
};

class CheckedOutput : public Pipeline {
public:
    explicit CheckedOutput(FILE* file) : Pipeline("private PDF output", nullptr), file(file) {}
    void write(const unsigned char* data, size_t count) override {
        if (count > UINT64_MAX - bytes) throw PDFProcessingStopped(false);
        checkPDFOutputSize(bytes + count);
        if (fwrite(data, 1, count, file) != count) throw std::runtime_error("Could not write the PDF result");
        bytes += count;
    }
    void finish() override { checkPDFProcessing(); }
private:
    FILE* file;
    uint64_t bytes = 0;
};

PDFInputNormalizationResult normalizeRecoverableInput(QPDF& pdf) {
    using Object = QPDFObjectHandle;
    PDFInputNormalizationResult result;
    const auto xref = pdf.getXRefTable();
    std::set<QPDFObjGen> zeroOffsetObjects;
    for (const auto& [id, entry] : xref) {
        if (entry.getType() == 1 && entry.getOffset() == 0) zeroOffsetObjects.insert(id);
    }
    if (zeroOffsetObjects.empty()) {
        pdf.fixDanglingReferences();
        if (pdf.anyWarnings())
            throw PDFProcessingUnsupported(
                "The PDF contains damaged objects that cannot be repaired without risking document content.");
        return result;
    }

    auto root = pdf.getRoot();
    const auto structureReference = root.getKey("/StructTreeRoot");
    QPDFObjGen structureRoot;
    if (structureReference.isIndirect() &&
        !zeroOffsetObjects.contains(structureReference.getObjGen())) {
        structureRoot = structureReference.getObjGen();
    }

    struct SafeReference { Object dictionary; std::string key; };
    std::vector<SafeReference> safeReferences;
    std::set<QPDFObjGen> unsafeReferences;
    std::set<QPDFObjGen> visited;
    std::function<void(Object, unsigned)> walk = [&](Object object, unsigned depth) {
        checkPDFProcessing();
        if (depth > 256)
            throw PDFProcessingUnsupported(
                "The PDF object hierarchy is too deep to repair safely.");
        if (object.isIndirect()) {
            const auto id = object.getObjGen();
            if (zeroOffsetObjects.contains(id)) {
                unsafeReferences.insert(id);
                return;
            }
            if (!visited.insert(id).second) return;
        }
        if (object.isArray()) {
            for (auto child : object.getArrayAsVector()) walk(child, depth + 1);
            return;
        }
        auto dictionary = object.isStream() ? object.getDict() : object;
        if (!dictionary.isDictionary()) return;
        const bool isStructureRoot = object.isIndirect() && object.getObjGen() == structureRoot;
        for (const auto& [key, child] : dictionary.getDictAsMap()) {
            if (child.isIndirect() && zeroOffsetObjects.contains(child.getObjGen())) {
                const bool safe = isStructureRoot && (key == "/ParentTree" || key == "/IDTree");
                if (safe) safeReferences.push_back({dictionary, key});
                else unsafeReferences.insert(child.getObjGen());
                continue;
            }
            walk(child, depth + 1);
        }
    };
    walk(root, 0);
    if (!unsafeReferences.empty())
        throw PDFProcessingUnsupported(
            "The PDF has a missing object that is required to preserve visible or functional content.");

    for (auto& reference : safeReferences) reference.dictionary.removeKey(reference.key);
    for (const auto& id : zeroOffsetObjects) pdf.replaceObject(id, Object::newNull());
    result.zeroOffsetObjectsRemoved = static_cast<unsigned>(zeroOffsetObjects.size());
    pdf.fixDanglingReferences();
    if (pdf.anyWarnings())
        throw PDFProcessingUnsupported(
            "The PDF contains damaged objects that cannot be repaired without risking document content.");
    return result;
}

} // namespace

bool canPreservePDFEncryption(QPDF& pdf) {
    if (!pdf.isEncrypted()) return true;
    int revision = 0, permissions = 0, version = 0;
    QPDF::encryption_method_e streams, strings, files;
    pdf.isEncrypted(revision, permissions, version, streams, strings, files);
    // QPDFWriter normalizes V4+ to AES. Preserve exactly the supported common
    // protection schemes; attachment-only or mixed crypt filters instead use
    // the user's approved removal-and-warning path after authentication.
    if (revision == 2 || revision == 3) return true;
    const auto expected = version >= 5 ? QPDF::e_aesv3 : QPDF::e_aes;
    return streams == expected && strings == expected && files == expected;
}

std::unique_ptr<QPDF> openPDFDocument(const std::filesystem::path& input, const std::string& password,
                                      PDFInputNormalizationResult* normalization) {
    auto read = [&](const std::string& encoded) {
        auto pdf = std::make_unique<QPDF>();
        pdf->setSuppressWarnings(true);
        // Do not silently repair a damaged input and then promise lossless
        // structural editing. The original remains available after any error.
        pdf->setAttemptRecovery(false);
        pdf->processInputSource(std::make_shared<CheckedInput>(input), encoded.c_str());
        if (normalization) *normalization = normalizeRecoverableInput(*pdf);
        return pdf;
    };
    try {
        return read(password);
    } catch (const QPDFExc& error) {
        if (error.getErrorCode() != qpdf_e_password) throw;
        // PDF encryption before revision 5 uses PDFDocEncoding; newer PDFs
        // use UTF-8. Retry only the lossless PDFDocEncoding representation.
        std::string legacy;
        if (QUtil::utf8_to_pdf_doc(password, legacy) && legacy != password) return read(legacy);
        throw;
    }
}

std::uintmax_t writePDFDocument(QPDF& pdf, const std::filesystem::path& output,
                               bool preserveEncryption, bool compressStreams) {
    // Exclusivity prevents accidental overwrite and rejects symlink targets.
    int descriptor = ::open(output.c_str(), O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
    if (descriptor < 0) throw std::runtime_error("Could not create the private PDF result");
    FILE* file = fdopen(descriptor, "wb");
    if (!file) {
        close(descriptor);
        std::filesystem::remove(output);
        throw std::runtime_error("Could not open the private PDF result");
    }
    try {
        CheckedOutput pipeline(file);
        QPDFWriter writer(pdf);
        writer.setOutputPipeline(&pipeline);
        writer.setPreserveUnreferencedObjects(false);
        writer.setObjectStreamMode(compressStreams ? qpdf_o_generate : qpdf_o_preserve);
        writer.setStreamDataMode(compressStreams ? qpdf_s_compress : qpdf_s_preserve);
        writer.setPreserveEncryption(preserveEncryption);
        writer.write();
        checkPDFProcessing();
        if (fflush(file) || ferror(file)) throw std::runtime_error("Could not finish the PDF result");
        int status = fclose(file);
        file = nullptr;
        if (status) throw std::runtime_error("Could not close the PDF result");
        if (pdf.anyWarnings()) throw std::runtime_error("The PDF contains unsupported or damaged objects");
        return std::filesystem::file_size(output);
    } catch (...) {
        if (file) fclose(file);
        std::error_code ignored;
        std::filesystem::remove(output, ignored);
        throw;
    }
}

namespace {

static PDFStructuralWriteResult rewritePDF(const std::filesystem::path& input,
                                          const std::filesystem::path& output,
                                          const std::string& password,
                                          const PDFMetadataRetention& retention,
                                          bool preserveConformity,
                                          const PDFCompressionPlan* compression, int previewPage = -1) {
    if (input == output) throw std::runtime_error("PDF processing requires a separate output file");
    PDFInputNormalizationResult normalization;
    auto pdf = openPDFDocument(input, password, &normalization);
    PDFStructuralWriteResult result;
    result.protectionRemoved = !canPreservePDFEncryption(*pdf);
    result.inputStructureRepaired = normalization.repaired();
    const auto effectiveRetention = preserveConformity ? metadataPreservingConformity(*pdf) : retention;
    if (compression) result.compression = compressPDFObjects(*pdf, *compression, previewPage);
    else externalizePDFInlineImages(*pdf);
    result.sanitization = sanitizePDFMetadata(*pdf, effectiveRetention);
    result.outputBytes = writePDFDocument(*pdf, output, !result.protectionRemoved, compression != nullptr);
    return result;
}
} // namespace

PDFStructuralWriteResult removePDFMetadata(const std::filesystem::path& input,
                                          const std::filesystem::path& output,
                                          const std::string& password,
                                          const PDFMetadataRetention& retention,
                                          bool preserveConformity) {
    return rewritePDF(input, output, password, retention, preserveConformity, nullptr);
}
PDFStructuralWriteResult compressPDF(const std::filesystem::path& input,
                                    const std::filesystem::path& output,
                                    const std::string& password,
                                    const PDFCompressionPlan& plan, int previewPage) {
    plan.validate();
    return rewritePDF(input, output, password, {}, false, &plan, previewPage);
}
} // namespace ips2pdf
