#pragma once

#include <qpdf/QPDFObjectHandle.hh>

namespace ips2pdf {

// Renames the narrowly identified Pages signature font while preserving its
// character mapping, metrics and CFF outlines. Returns true only when every
// PDF and CFF invariant of that signature subset matches.
bool anonymizeSignatureFont(QPDFObjectHandle font);

} // namespace ips2pdf
