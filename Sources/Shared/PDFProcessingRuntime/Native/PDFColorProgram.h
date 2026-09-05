#pragma once
#include "PDFCompressionPolicy.h"
#include <qpdf/QPDF.hh>

namespace ips2pdf {
QPDFObjectHandle resolvePDFColorSpace(QPDFObjectHandle space, QPDFObjectHandle resources,
                                     bool useDeviceDefaults = true);
// Rewrite color operators while preserving every other content token. Complex
// cases that cannot preserve painting behavior fail before any output is saved.
void rewritePDFColors(QPDF& pdf, const PDFCompressionPolicy& policy);
} // namespace ips2pdf
