#pragma once
#include <stdexcept>
namespace ips2pdf {
// Construct only with fixed application-owned text, never PDF object values.
// This diagnostic may cross the helper boundary and be localized by the UI.
class PDFProcessingUnsupported : public std::runtime_error {
public:
    explicit PDFProcessingUnsupported(const char* message) : std::runtime_error(message) {}
};
} // namespace ips2pdf
