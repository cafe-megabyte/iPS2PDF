#pragma once

#include "PDFStructuralWriter.h"
#include <filesystem>
#include <string>
#include <vector>

namespace ips2pdf {

struct PDFSignaturePlacement {
    int pageIndex = -1;
    double x = 0;
    double y = 0;
    double fontSize = 50;
};

PDFStructuralWriteResult addPDFSignatures(const std::filesystem::path& input,
                                          const std::filesystem::path& output,
                                          const std::filesystem::path& font,
                                          const std::string& password,
                                          const std::vector<PDFSignaturePlacement>& placements);

} // namespace ips2pdf
