#pragma once

#include "PDFStructuralSanitizer.h"
#include "PDFCompressionTransform.h"
#include <filesystem>
#include <memory>
#include <qpdf/QPDF.hh>
#include <string>

namespace ips2pdf {

std::unique_ptr<QPDF> openPDFDocument(const std::filesystem::path& input,
                                      const std::string& password);

struct PDFStructuralWriteResult {
    PDFSanitizationResult sanitization;
    bool protectionRemoved = false;
    PDFCompressionChanges compression;
    std::uintmax_t outputBytes = 0;
};

// The output must be a new file in a private job directory. This never replaces
// an input or existing output. Passwords are passed in memory by the dispatcher.
// No password or source PDF bytes may be included in logs or user-facing errors.
PDFStructuralWriteResult removePDFMetadata(const std::filesystem::path& input,
                                          const std::filesystem::path& output,
                                          const std::string& password,
                                          const PDFMetadataRetention& retention = {},
                                          bool preserveConformity = false);

PDFStructuralWriteResult compressPDF(const std::filesystem::path& input,
                                    const std::filesystem::path& output,
                                    const std::string& password,
                                    const PDFCompressionPolicy& policy, int previewPage = -1);

} // namespace ips2pdf
