#pragma once
#include "PDFStructuralSanitizer.h"
#include <stdexcept>

namespace ips2pdf {

class PDFConformityError : public std::runtime_error {
public:
    using std::runtime_error::runtime_error;
};

// Builds minimal metadata for a recognized, coherent declaration. This does
// not validate conformance or repair missing required data. Unsupported or
// conflicting declarations fail, allowing the UI to offer discard or cancel.
PDFMetadataRetention metadataPreservingConformity(QPDF& pdf);

} // namespace ips2pdf
