#include "PDFProcessingControl.h"
#include <new>

namespace {
thread_local IPS2PDFProcessingControl* active = nullptr;
}

IPS2PDFProcessingControl* ips2pdf_pdf_control_create(uint64_t milliseconds, uint64_t input, uint64_t output) {
    // Bound conversions before constructing chrono durations, including values
    // received through an invalid or future IPC client.
    if (!milliseconds || milliseconds > 24 * 60 * 60 * 1000ULL || !input || !output) return nullptr;
    return new (std::nothrow) IPS2PDFProcessingControl{
        false, std::chrono::steady_clock::now() + std::chrono::milliseconds(milliseconds), input, output};
}
void ips2pdf_pdf_control_cancel(IPS2PDFProcessingControl* control) {
    if (control) control->cancelled.store(true, std::memory_order_relaxed);
}
void ips2pdf_pdf_control_destroy(IPS2PDFProcessingControl* control) { delete control; }

namespace ips2pdf {
PDFProcessingScope::PDFProcessingScope(IPS2PDFProcessingControl* control) : previous(active) { active = control; }
PDFProcessingScope::~PDFProcessingScope() { active = previous; }
void checkPDFProcessing() {
    if (!active) return;
    if (active->cancelled.load(std::memory_order_relaxed)) throw PDFProcessingStopped(true);
    if (std::chrono::steady_clock::now() >= active->deadline) throw PDFProcessingStopped(false);
}
void checkPDFInputSize(uint64_t bytes) {
    checkPDFProcessing();
    if (active && bytes > active->maximumInputBytes) throw PDFProcessingStopped(false);
}
void checkPDFOutputSize(uint64_t bytes) {
    checkPDFProcessing();
    if (active && bytes > active->maximumOutputBytes) throw PDFProcessingStopped(false);
}
} // namespace ips2pdf
