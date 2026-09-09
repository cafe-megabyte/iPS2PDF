#include "PDFProcessingBridge.h"
#include "PDFProcessingControl.h"
#include "PDFConformityMetadata.h"
#include "PDFStructuralWriter.h"
#include "PDFProcessingUnsupported.h"
#include "PDFResourceExtraction.h"
#include "PDFSignatureWriter.h"

#include <cmath>
#include <cstdio>
#include <cstring>
#include <algorithm>
#include <mutex>
#include <set>
#include <string>
#include <vector>

namespace {
std::mutex processingMutex;
bool copyPaperColors(ips2pdf::PDFCompressionPolicy& policy,
                     const IPS2PDFPaperColor* colors, uint32_t count) {
    if (count > policy.paperColors.size() || (count > 0 && !colors)) return false;
    policy.paperColorCount = count;
    for (uint32_t index = 0; index < count; ++index) {
        policy.paperColors[index] = {colors[index].red, colors[index].green,
                                     colors[index].blue};
        if (!policy.paperColors[index].isValid()) return false;
    }
    return true;
}

bool copyPaperColors(ips2pdf::PDFCompressionPolicy& policy,
                     const IPS2PDFPageCompressionOverride& item) {
    const IPS2PDFPaperColor colors[] = {
        item.paper_color_0, item.paper_color_1, item.paper_color_2
    };
    return item.paper_color_count >= 0 &&
           copyPaperColors(policy, colors, static_cast<uint32_t>(item.paper_color_count));
}

int32_t process(const char* input, const char* output, const char* password,
                int32_t preserve, const ips2pdf::PDFCompressionPlan* compression,
                IPS2PDFProcessingControl* control, IPS2PDFProcessingResult* result, int previewPage = -1) {
    if (!result) return IPS2PDF_PROCESSING_INVALID_REQUEST;
    *result = {};
    result->version = 1;
    result->status = IPS2PDF_PROCESSING_INVALID_REQUEST;
    if (!input || !*input || !output || !*output || (preserve != 0 && preserve != 1)) return result->status;
    std::unique_lock lock(processingMutex, std::try_to_lock);
    if (!lock.owns_lock()) return result->status = IPS2PDF_PROCESSING_BUSY;
    ips2pdf::PDFProcessingScope scope(control);
    try {
        ips2pdf::checkPDFProcessing();
        auto finished = compression ? ips2pdf::compressPDF(input, output, password ? password : "", *compression, previewPage) :
            ips2pdf::removePDFMetadata(input, output, password ? password : "", {}, preserve != 0);
        result->output_bytes = finished.outputBytes;
        if (finished.sanitization.signaturesRemoved) result->warnings |= IPS2PDF_WARNING_SIGNATURES_REMOVED;
        if (finished.protectionRemoved) result->warnings |= IPS2PDF_WARNING_PROTECTION_REMOVED;
        if (finished.sanitization.signatureAppearancesMayDiffer) result->warnings |= IPS2PDF_WARNING_SIGNATURE_APPEARANCE;
        if (finished.compression.attachmentsRemoved) result->warnings |= IPS2PDF_WARNING_ATTACHMENTS_REMOVED;
        if (finished.compression.invoiceAttachmentRemoved) result->warnings |= IPS2PDF_WARNING_INVOICE_ATTACHMENT_REMOVED;
        result->shared_resources_from_earlier_pages = finished.compression.sharedResourcesFromEarlierPages;
        result->status = IPS2PDF_PROCESSING_SUCCESS;
    } catch (const ips2pdf::PDFProcessingStopped& error) {
        result->status = error.cancelled ? IPS2PDF_PROCESSING_CANCELLED : IPS2PDF_PROCESSING_LIMIT_EXCEEDED;
    } catch (const ips2pdf::PDFConformityError& error) {
        result->status = IPS2PDF_PROCESSING_CONFORMITY_UNSUPPORTED;
        std::snprintf(result->detail, sizeof(result->detail), "%s", error.what());
    } catch (const ips2pdf::PDFProcessingUnsupported& error) {
        result->status = IPS2PDF_PROCESSING_UNSUPPORTED;
        std::snprintf(result->detail, sizeof(result->detail), "%s", error.what());
    } catch (const QPDFExc& error) {
        result->status = error.getErrorCode() == qpdf_e_password ? IPS2PDF_PROCESSING_PASSWORD_REQUIRED : IPS2PDF_PROCESSING_FAILED;
    } catch (...) {
        // Third-party exceptions may include PDF strings or file paths. Only
        // our own conformity exceptions have reviewed, fixed diagnostic text.
        result->status = IPS2PDF_PROCESSING_FAILED;
    }
    return result->status;
}
} // namespace

int32_t ips2pdf_pdf_remove_metadata(const char* input, const char* output, const char* password,
                                   int32_t preserve, IPS2PDFProcessingControl* control, IPS2PDFProcessingResult* result) {
    return process(input, output, password, preserve, nullptr, control, result);
}
int32_t ips2pdf_pdf_compress(const char* input, const char* output, const char* password,
                            int32_t level, int32_t monochrome, int32_t threshold, int32_t contrast,
                            int32_t paperCleanup, const IPS2PDFPaperColor* paperColors,
                            uint32_t paperColorCount,
                            const IPS2PDFPageCompressionOverride* pageOverrides, uint32_t pageOverrideCount,
                            IPS2PDFProcessingControl* control, IPS2PDFProcessingResult* result) {
    return ips2pdf_pdf_compress_preview(input, output, password, level, monochrome, threshold, contrast,
                                        paperCleanup, paperColors, paperColorCount,
                                        pageOverrides, pageOverrideCount, -1, control, result);
}
int32_t ips2pdf_pdf_compress_preview(const char* input, const char* output, const char* password,
                                    int32_t level, int32_t monochrome, int32_t threshold, int32_t contrast,
                                    int32_t paperCleanup, const IPS2PDFPaperColor* paperColors,
                                    uint32_t paperColorCount,
                                    const IPS2PDFPageCompressionOverride* pageOverrides, uint32_t pageOverrideCount,
                                    int32_t pageIndex,
                                    IPS2PDFProcessingControl* control, IPS2PDFProcessingResult* result) {
    if (level < 0 || level > 2 || monochrome < 0 || monochrome > 1 || threshold < 0 || threshold > 100 ||
        contrast < 0 || contrast > 100 || paperCleanup < 0 || paperCleanup > 100 ||
        pageIndex < -1 || paperColorCount > 3 || pageOverrideCount > 100000 ||
        (paperColorCount > 0 && !paperColors) ||
        (pageOverrideCount > 0 && !pageOverrides)) {
        if (result) { *result = {}; result->version = 1; result->status = IPS2PDF_PROCESSING_INVALID_REQUEST; }
        return IPS2PDF_PROCESSING_INVALID_REQUEST;
    }
    ips2pdf::PDFCompressionPlan plan{{static_cast<ips2pdf::PDFCompressionLevel>(level), monochrome != 0,
                                      threshold, contrast, paperCleanup}, {}};
    if (!copyPaperColors(plan.document, paperColors, paperColorCount)) {
        if (result) { *result = {}; result->version = 1; result->status = IPS2PDF_PROCESSING_INVALID_REQUEST; }
        return IPS2PDF_PROCESSING_INVALID_REQUEST;
    }
    int32_t previousPage = -1;
    for (uint32_t index = 0; index < pageOverrideCount; ++index) {
        const auto& item = pageOverrides[index];
        if (item.page_index <= previousPage || item.level < 0 || item.level > 2 || item.monochrome < 0 || item.monochrome > 1 ||
            item.threshold < 0 || item.threshold > 100 || item.contrast < 0 || item.contrast > 100 ||
            item.paper_cleanup < 0 || item.paper_cleanup > 100 || item.paper_color_count < 0 ||
            item.paper_color_count > 3) {
            if (result) { *result = {}; result->version = 1; result->status = IPS2PDF_PROCESSING_INVALID_REQUEST; }
            return IPS2PDF_PROCESSING_INVALID_REQUEST;
        }
        previousPage = item.page_index;
        auto policy = ips2pdf::PDFCompressionPolicy{
            static_cast<ips2pdf::PDFCompressionLevel>(item.level), item.monochrome != 0,
            item.threshold, item.contrast, item.paper_cleanup};
        if (!copyPaperColors(policy, item)) {
            if (result) { *result = {}; result->version = 1; result->status = IPS2PDF_PROCESSING_INVALID_REQUEST; }
            return IPS2PDF_PROCESSING_INVALID_REQUEST;
        }
        plan.pages.emplace(item.page_index, policy);
    }
    return process(input, output, password, 0, &plan, control, result, pageIndex);
}

int32_t ips2pdf_pdf_add_signatures(const char* input, const char* output, const char* font,
                                  const char* password, const IPS2PDFSignaturePlacement* placements,
                                  uint32_t placementCount, IPS2PDFProcessingControl* control,
                                  IPS2PDFProcessingResult* result) {
    if (!result) return IPS2PDF_PROCESSING_INVALID_REQUEST;
    *result = {};
    result->version = 1;
    result->status = IPS2PDF_PROCESSING_INVALID_REQUEST;
    if (!input || !*input || !output || !*output || !font || !*font || placementCount == 0 ||
        placementCount > 10000 || !placements) return result->status;
    std::vector<ips2pdf::PDFSignaturePlacement> values;
    values.reserve(placementCount);
    for (uint32_t index = 0; index < placementCount; ++index) {
        const auto& item = placements[index];
        if (item.page_index < 0 || !std::isfinite(item.x) || !std::isfinite(item.y) ||
            !std::isfinite(item.font_size) || item.font_size < 5 || item.font_size > 500)
            return result->status;
        values.push_back({item.page_index, item.x, item.y, item.font_size});
    }
    std::unique_lock lock(processingMutex, std::try_to_lock);
    if (!lock.owns_lock()) return result->status = IPS2PDF_PROCESSING_BUSY;
    ips2pdf::PDFProcessingScope scope(control);
    try {
        auto finished = ips2pdf::addPDFSignatures(input, output, font, password ? password : "", values);
        result->output_bytes = finished.outputBytes;
        if (finished.sanitization.signaturesRemoved) result->warnings |= IPS2PDF_WARNING_SIGNATURES_REMOVED;
        if (finished.protectionRemoved) result->warnings |= IPS2PDF_WARNING_PROTECTION_REMOVED;
        if (finished.sanitization.signatureAppearancesMayDiffer) result->warnings |= IPS2PDF_WARNING_SIGNATURE_APPEARANCE;
        result->status = IPS2PDF_PROCESSING_SUCCESS;
    } catch (const ips2pdf::PDFProcessingStopped& error) {
        result->status = error.cancelled ? IPS2PDF_PROCESSING_CANCELLED : IPS2PDF_PROCESSING_LIMIT_EXCEEDED;
    } catch (const QPDFExc& error) {
        result->status = error.getErrorCode() == qpdf_e_password ? IPS2PDF_PROCESSING_PASSWORD_REQUIRED : IPS2PDF_PROCESSING_FAILED;
    } catch (...) {
        result->status = IPS2PDF_PROCESSING_FAILED;
    }
    return result->status;
}

int32_t ips2pdf_pdf_extract_resource(const char* input, const char* output, const char* password,
                                    const char* format, const char* fingerprint, int32_t width,
                                    int32_t height, int32_t bitsPerComponent,
                                    IPS2PDFProcessingControl* control, IPS2PDFProcessingResult* result) {
    if (!result) return IPS2PDF_PROCESSING_INVALID_REQUEST;
    *result = {}; result->version = 1; result->status = IPS2PDF_PROCESSING_INVALID_REQUEST;
    const std::set<std::string> formats = {"embeddedFile", "jpeg", "jpeg2000", "png", "type1", "trueType",
        "trueTypeCollection", "cff", "openType", "openTypeCollection", "icc", "xml"};
    if (!input || !*input || !output || !*output || !format || !*format || !fingerprint || std::strlen(fingerprint) != 64 ||
        formats.find(format) == formats.end() ||
        !std::all_of(fingerprint, fingerprint + 64, [](unsigned char c) { return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'); }) ||
        width < 0 || height < 0 || bitsPerComponent < 0) return result->status;
    std::unique_lock lock(processingMutex, std::try_to_lock);
    if (!lock.owns_lock()) return result->status = IPS2PDF_PROCESSING_BUSY;
    ips2pdf::PDFProcessingScope scope(control);
    try {
        result->output_bytes = ips2pdf::extractPDFResource(input, output, password ? password : "", format,
                                                           fingerprint, width, height, bitsPerComponent);
        result->status = IPS2PDF_PROCESSING_SUCCESS;
    } catch (const ips2pdf::PDFProcessingStopped& error) {
        result->status = error.cancelled ? IPS2PDF_PROCESSING_CANCELLED : IPS2PDF_PROCESSING_LIMIT_EXCEEDED;
    } catch (const QPDFExc& error) {
        result->status = error.getErrorCode() == qpdf_e_password ? IPS2PDF_PROCESSING_PASSWORD_REQUIRED : IPS2PDF_PROCESSING_FAILED;
    } catch (...) {
        result->status = IPS2PDF_PROCESSING_FAILED;
    }
    return result->status;
}
