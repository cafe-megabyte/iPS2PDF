#pragma once

#include <qpdf/QPDF.hh>

namespace ips2pdf {

bool isJPEGStream(QPDFObjectHandle stream);
// Returns true if encoded metadata or an outer transport filter changed.
// The image samples, dimensions, color space and DCT decode parameters remain.
bool cleanJPEGStream(QPDF& owner, QPDFObjectHandle stream, bool preserveICC);
bool cleanBinaryImageStream(QPDF& owner, QPDFObjectHandle stream);

} // namespace ips2pdf
