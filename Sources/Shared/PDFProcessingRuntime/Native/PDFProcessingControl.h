#pragma once
#include "PDFProcessingBridge.h"
#include <atomic>
#include <chrono>
#include <stdexcept>

struct IPS2PDFProcessingControl {
    std::atomic_bool cancelled{false};
    std::chrono::steady_clock::time_point deadline;
    uint64_t maximumInputBytes;
    uint64_t maximumOutputBytes;
};

namespace ips2pdf {
class PDFProcessingStopped : public std::runtime_error {
public:
    explicit PDFProcessingStopped(bool cancellation)
        : std::runtime_error("PDF processing stopped"), cancelled(cancellation) {}
    const bool cancelled;
};

// Native jobs are serialized. The scope keeps cancellation local to the active
// thread and prevents a late cancellation from affecting the next operation.
class PDFProcessingScope {
public:
    explicit PDFProcessingScope(IPS2PDFProcessingControl* control);
    ~PDFProcessingScope();
    PDFProcessingScope(const PDFProcessingScope&) = delete;
    PDFProcessingScope& operator=(const PDFProcessingScope&) = delete;
private:
    IPS2PDFProcessingControl* previous;
};
void checkPDFProcessing();
void checkPDFInputSize(uint64_t bytes);
void checkPDFOutputSize(uint64_t bytes);
} // namespace ips2pdf
