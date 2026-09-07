#include "PDFProcessingBridge.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>

// Small command-line acceptance harness for the exact helper C interface.
// Inputs are read-only and the interface requires a previously absent output.
int main(int argc, char** argv) {
    const bool metadata = argc == 5 && std::strcmp(argv[1], "metadata") == 0;
    if (!metadata && argc != 6 && argc != 7) {
        std::fprintf(stderr, "usage: pdf-processing input output level monochrome threshold [contrast]\n       pdf-processing metadata input output preserve_conformity\n"); return 2;
    }
    auto* control = ips2pdf_pdf_control_create(900000, 1024ull * 1024 * 1024, 2ull * 1024 * 1024 * 1024);
    if (!control) return 2;
    IPS2PDFProcessingResult result{};
    const int status = metadata ? ips2pdf_pdf_remove_metadata(argv[2], argv[3], nullptr, std::atoi(argv[4]), control, &result) :
        ips2pdf_pdf_compress(argv[1], argv[2], nullptr, std::atoi(argv[3]), std::atoi(argv[4]), std::atoi(argv[5]),
                            argc == 7 ? std::atoi(argv[6]) : 0, nullptr, 0, control, &result);
    ips2pdf_pdf_control_destroy(control);
    std::printf("status=%d bytes=%llu warnings=%u detail=%s\n", status,
                static_cast<unsigned long long>(result.output_bytes), result.warnings, result.detail);
    return status ? 1 : 0;
}
