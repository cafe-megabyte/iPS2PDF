#pragma once
#include "PDFCompressionPolicy.h"
#include <qpdf/QPDF.hh>

namespace ips2pdf {
struct PDFCompressionChanges {
    bool attachmentsRemoved = false;
    bool invoiceAttachmentRemoved = false;
    uint32_t sharedResourcesFromEarlierPages = 0;
};
PDFCompressionChanges compressPDFObjects(QPDF& pdf, const PDFCompressionPlan& plan, int previewPage = -1);
} // namespace ips2pdf
