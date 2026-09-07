#pragma once
#include "PDFCompressionPolicy.h"
#include <qpdf/QPDF.hh>
#include <map>

namespace ips2pdf {
QPDFObjectHandle resolvePDFColorSpace(QPDFObjectHandle space, QPDFObjectHandle resources,
                                     bool useDeviceDefaults = true);
// Rewrite color operators while preserving every other content token. Complex
// cases that cannot preserve painting behavior fail before any output is saved.
void rewritePDFColors(QPDF& pdf, const PDFCompressionPlan& plan,
                      const std::map<QPDFObjGen, std::size_t>& pageOwners);
inline void rewritePDFColors(QPDF& pdf, const PDFCompressionPolicy& policy) {
    rewritePDFColors(pdf, PDFCompressionPlan{policy, {}}, {});
}
} // namespace ips2pdf
