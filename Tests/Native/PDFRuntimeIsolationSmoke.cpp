#include "PDFProcessingBridge.h"
#include "PDFProcessingSmoke.h"
#include <cstdio>
#include <filesystem>
#include <thread>

// Stand-ins for colliding symbols exported by Ghostscript's static dependencies.
// Any accidental call from the PDF engine would fail its rendering/codec tests.
static unsigned collisions = 0;
#if defined(IPS2PDF_REAL_GHOSTSCRIPT)
extern "C" int gsapi_revision(void*, int);
#else
extern "C" int FT_Init_FreeType(void*) { ++collisions; return -99; }
extern "C" void* cmsCreate_sRGBProfile() { ++collisions; return nullptr; }
extern "C" void* pixCreate(int, int, int) { ++collisions; return nullptr; }
#endif

int main(int argc, char** argv) {
    if (argc != 3) return 2;
    if (ips2pdf_run_native_smoke(argv[1], argv[2]) || collisions) return 1;
    namespace fs = std::filesystem;
    const auto input = fs::path(argv[1]) / "InfoPlain.pdf";
    const auto output = fs::path(argv[2]) / "BridgeResult.pdf";
    fs::remove(output);
    IPS2PDFProcessingResult result{};
    if (ips2pdf_pdf_remove_metadata(input.c_str(), output.c_str(), nullptr, 0, nullptr, &result) ||
        result.version != 1 || result.output_bytes == 0 || result.warnings != 0) return 1;
    fs::remove(output);
    const auto encrypted = fs::path(argv[1]) / "InfoEncrypted-AES-256.pdf";
    if (ips2pdf_pdf_remove_metadata(encrypted.c_str(), output.c_str(), "wrong-password", 0, nullptr, &result) !=
        IPS2PDF_PROCESSING_PASSWORD_REQUIRED || fs::exists(output) || result.detail[0]) return 1;
    for (int scenario = 0; scenario < 4; ++scenario) {
        auto* control = ips2pdf_pdf_control_create(scenario == 3 ? 1 : 60000,
                                                  scenario == 1 ? 1 : 1024 * 1024,
                                                  scenario == 2 ? 128 : 1024 * 1024);
        if (!control) return 1;
        if (scenario == 0) ips2pdf_pdf_control_cancel(control);
        if (scenario == 3) std::this_thread::sleep_for(std::chrono::milliseconds(5));
        const int status = ips2pdf_pdf_remove_metadata(input.c_str(), output.c_str(), nullptr, 0, control, &result);
        ips2pdf_pdf_control_destroy(control);
        if (status != (scenario == 0 ? IPS2PDF_PROCESSING_CANCELLED : IPS2PDF_PROCESSING_LIMIT_EXCEEDED) ||
            fs::exists(output) || result.output_bytes) return 1;
    }
    // A cancelled request cannot poison the next request in the same process.
    if (ips2pdf_pdf_remove_metadata(input.c_str(), output.c_str(), nullptr, 0, nullptr, &result)) return 1;
    fs::remove(output);
    std::printf("PASS processing control: cancellation, input/output limits, deadline and partial-file cleanup\n");
#if defined(IPS2PDF_REAL_GHOSTSCRIPT)
    if (gsapi_revision(nullptr, 0) <= 0) return 1;
#else
    if (FT_Init_FreeType(nullptr) != -99 || cmsCreate_sRGBProfile() || pixCreate(1, 1, 1) || collisions != 3) return 1;
#endif
    std::printf("PASS isolated C runtime: codec symbols cannot bind to another static engine; bridge and password errors verified\n");
    return 0;
}
