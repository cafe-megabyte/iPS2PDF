#pragma once
#include <qpdf/QPDF.hh>
#include <limits>
#include <map>
#include <set>
#include <string>
#include <vector>

namespace ips2pdf {
struct PDFContentOperation {
    std::string name;
    std::vector<QPDFObjectHandle> operands;
    size_t start = 0;
    size_t end = 0;
};
struct PDFContentProgram {
    std::string bytes;
    std::vector<PDFContentOperation> operations;
};
PDFContentProgram readPDFContent(QPDF& pdf, QPDFObjectHandle holder);
// Expose inline image containers to the same codecs and metadata scrubber as
// ordinary XObjects, retaining the effective resources of inherited forms.
void externalizePDFInlineImages(QPDF& pdf);

struct PDFPlacementMatrix {
    double a = 1, b = 0, c = 0, d = 1, e = 0, f = 0;
    PDFPlacementMatrix concatenated(const PDFPlacementMatrix& inner) const;
    static PDFPlacementMatrix fromOperands(const std::vector<QPDFObjectHandle>& operands);
};

struct PDFImagePlacement {
    QPDFObjectHandle image;
    double minimumPPI = 0;
    uint64_t placements = 0;
    size_t firstPage = std::numeric_limits<size_t>::max();
    std::set<size_t> pages;
};
struct PDFContentCensus {
    std::map<QPDFObjGen, PDFImagePlacement> images;
    std::map<QPDFObjGen, size_t> firstResourcePages;
    std::map<QPDFObjGen, std::set<size_t>> resourcePages;
};
// Census before any image is changed: the largest display placement and both
// axes constrain downsampling, including repeated/nested forms and UserUnit.
PDFContentCensus pdfContentCensus(QPDF& pdf);
std::map<QPDFObjGen, PDFImagePlacement> pdfImagePlacements(QPDF& pdf);
} // namespace ips2pdf
