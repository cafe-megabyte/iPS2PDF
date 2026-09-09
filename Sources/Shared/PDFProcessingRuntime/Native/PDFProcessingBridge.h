#pragma once
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum {
    IPS2PDF_PROCESSING_SUCCESS = 0,
    IPS2PDF_PROCESSING_PASSWORD_REQUIRED = 1,
    IPS2PDF_PROCESSING_INVALID_REQUEST = 2,
    IPS2PDF_PROCESSING_CONFORMITY_UNSUPPORTED = 3,
    IPS2PDF_PROCESSING_FAILED = 4,
    IPS2PDF_PROCESSING_BUSY = 5,
    IPS2PDF_PROCESSING_CANCELLED = 6,
    IPS2PDF_PROCESSING_LIMIT_EXCEEDED = 7,
    IPS2PDF_PROCESSING_UNSUPPORTED = 8
};

enum {
    IPS2PDF_WARNING_SIGNATURES_REMOVED = 1,
    IPS2PDF_WARNING_PROTECTION_REMOVED = 2,
    IPS2PDF_WARNING_SIGNATURE_APPEARANCE = 4,
    IPS2PDF_WARNING_ATTACHMENTS_REMOVED = 8,
    IPS2PDF_WARNING_INVOICE_ATTACHMENT_REMOVED = 16
};

typedef struct {
    uint32_t version;
    int32_t status;
    uint32_t warnings;
    uint64_t output_bytes;
    // Only fixed, non-document diagnostic text is returned through this ABI.
    // The caller localizes status/warnings and never logs input passwords.
    char detail[512];
    uint32_t shared_resources_from_earlier_pages;
} IPS2PDFProcessingResult;

typedef struct {
    int32_t red;
    int32_t green;
    int32_t blue;
} IPS2PDFPaperColor;

typedef struct {
    int32_t page_index;
    int32_t level;
    int32_t monochrome;
    int32_t threshold;
    int32_t contrast;
    int32_t paper_cleanup;
    int32_t paper_color_count;
    IPS2PDFPaperColor paper_color_0;
    IPS2PDFPaperColor paper_color_1;
    IPS2PDFPaperColor paper_color_2;
} IPS2PDFPageCompressionOverride;

typedef struct {
    int32_t page_index;
    double x;
    double y;
    double font_size;
} IPS2PDFSignaturePlacement;

typedef struct IPS2PDFProcessingControl IPS2PDFProcessingControl;

// The caller retains this handle until processing and any cancellation callback
// have both finished. Cancellation is sticky and applies only to this request.
__attribute__((visibility("default")))
IPS2PDFProcessingControl* ips2pdf_pdf_control_create(uint64_t timeout_milliseconds,
                                                    uint64_t maximum_input_bytes,
                                                    uint64_t maximum_output_bytes);
__attribute__((visibility("default")))
void ips2pdf_pdf_control_cancel(IPS2PDFProcessingControl* control);
__attribute__((visibility("default")))
void ips2pdf_pdf_control_destroy(IPS2PDFProcessingControl* control);

// All paths identify files in the caller's private job directory. The output
// must not exist. Passwords stay in memory. This interface owns no UI or save
// dialog and never replaces the original. Engines run serially in the helper.
__attribute__((visibility("default")))
int32_t ips2pdf_pdf_remove_metadata(const char* input_path, const char* output_path,
                                   const char* password, int32_t preserve_conformity,
                                   IPS2PDFProcessingControl* control,
                                   IPS2PDFProcessingResult* result);

// level: 0 gentle, 1 balanced, 2 strong. monochrome: 0 color, 1 black/white.
// threshold, contrast and paper_cleanup: 0...100. Contrast is used only for
// color images. A paper_cleanup value of zero keeps the legacy image path.
// Paper colors are optional RGB modes learned from one user-selected screen
// area; one policy accepts at most three. The same policy produces preview and
// accepted output.
__attribute__((visibility("default")))
int32_t ips2pdf_pdf_compress(const char* input_path, const char* output_path,
                            const char* password, int32_t level, int32_t monochrome,
                            int32_t threshold, int32_t contrast, int32_t paper_cleanup,
                            const IPS2PDFPaperColor* paper_colors,
                            uint32_t paper_color_count,
                            const IPS2PDFPageCompressionOverride* page_overrides,
                            uint32_t page_override_count, IPS2PDFProcessingControl* control,
                            IPS2PDFProcessingResult* result);

__attribute__((visibility("default")))
int32_t ips2pdf_pdf_compress_preview(const char* input_path, const char* output_path,
                                    const char* password, int32_t level, int32_t monochrome,
                                    int32_t threshold, int32_t contrast, int32_t paper_cleanup,
                                    const IPS2PDFPaperColor* paper_colors,
                                    uint32_t paper_color_count,
                                    const IPS2PDFPageCompressionOverride* page_overrides,
                                    uint32_t page_override_count, int32_t page_index,
                                    IPS2PDFProcessingControl* control, IPS2PDFProcessingResult* result);

// Adds visible, flattened U+201A glyphs. The private OpenType/CFF font is read
// from the fixed per-request job file and embedded exactly once in the result.
__attribute__((visibility("default")))
int32_t ips2pdf_pdf_add_signatures(const char* input_path, const char* output_path,
                                  const char* font_path, const char* password,
                                  const IPS2PDFSignaturePlacement* placements,
                                  uint32_t placement_count,
                                  IPS2PDFProcessingControl* control,
                                  IPS2PDFProcessingResult* result);

__attribute__((visibility("default")))
int32_t ips2pdf_pdf_extract_resource(const char* input_path, const char* output_path,
                                    const char* password, const char* format,
                                    const char* fingerprint, int32_t width, int32_t height,
                                    int32_t bits_per_component,
                                    IPS2PDFProcessingControl* control, IPS2PDFProcessingResult* result);

#ifdef __cplusplus
}
#endif
