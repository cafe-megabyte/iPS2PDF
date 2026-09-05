#pragma once
#include "PDFCompressionPolicy.h"
#include <qpdf/QPDF.hh>

namespace ips2pdf {
struct PDFCompressionChanges {
    bool attachmentsRemoved = false;
    bool invoiceAttachmentRemoved = false;
};
PDFCompressionChanges compressPDFObjects(QPDF& pdf, const PDFCompressionPolicy& policy, int previewPage = -1);
} // namespace ips2pdf
