#include "PDFProcessingBridge.h"
#include "PDFProcessingControl.h"
#include "PDFConformityMetadata.h"
#include "PDFStructuralWriter.h"
#include "PDFProcessingUnsupported.h"

#include <cstdio>
#include <mutex>

namespace {
std::mutex processingMutex;
int32_t process(const char* input, const char* output, const char* password,
                int32_t preserve, const ips2pdf::PDFCompressionPolicy* compression,
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
                            int32_t level, int32_t monochrome, int32_t threshold,
                            IPS2PDFProcessingControl* control, IPS2PDFProcessingResult* result) {
    return ips2pdf_pdf_compress_preview(input, output, password, level, monochrome, threshold, -1, control, result);
}
int32_t ips2pdf_pdf_compress_preview(const char* input, const char* output, const char* password,
                                    int32_t level, int32_t monochrome, int32_t threshold, int32_t pageIndex,
                                    IPS2PDFProcessingControl* control, IPS2PDFProcessingResult* result) {
    if (level < 0 || level > 2 || monochrome < 0 || monochrome > 1 || threshold < 0 || threshold > 100 || pageIndex < -1) {
        if (result) { *result = {}; result->version = 1; result->status = IPS2PDF_PROCESSING_INVALID_REQUEST; }
        return IPS2PDF_PROCESSING_INVALID_REQUEST;
    }
    ips2pdf::PDFCompressionPolicy policy{static_cast<ips2pdf::PDFCompressionLevel>(level), monochrome != 0, threshold};
    return process(input, output, password, 0, &policy, control, result, pageIndex);
}
