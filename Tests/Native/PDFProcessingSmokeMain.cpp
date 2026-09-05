#include "PDFProcessingSmoke.h"
#include <cstdio>

int main(int argc, char** argv) {
    if (argc != 3) {
        std::fprintf(stderr, "Usage: PDFProcessingSmoke FIXTURE_DIRECTORY OUTPUT_DIRECTORY\n");
        return 2;
    }
    return ips2pdf_run_native_smoke(argv[1], argv[2]);
}
