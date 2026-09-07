#pragma once

#include <qpdf/QPDF.hh>
#include <map>
#include <string>

namespace ips2pdf {

struct PDFMetadataRetention {
    // The conformity policy supplies only the metadata required by a retained
    // declaration. Empty values mean that all descriptive metadata is removed.
    // This API does not validate a document's claimed conformance.
    std::string xmp;
    std::map<std::string, std::string> infoStrings;
    std::string trappedState;
};

struct PDFSanitizationResult {
    bool signaturesRemoved = false;
    bool signatureAppearancesMayDiffer = false;
    unsigned signatureFontsAnonymized = 0;
    unsigned metadataEntriesRemoved = 0;
    unsigned jpegStreamsCleaned = 0;
};

// Mutates a private, authenticated working document. The caller must perform a
// full rewrite and omit unreachable objects; incremental saving is forbidden.
// Font programs remain unchanged except for the exact Pages signature-font
// subset recognized by PDFSignatureFontAnonymizer. Embedded-file and ICC
// payloads are never edited here. Content, semantic structure and functional
// identifiers remain.
PDFSanitizationResult sanitizePDFMetadata(QPDF& pdf, const PDFMetadataRetention& retention = {});

} // namespace ips2pdf
