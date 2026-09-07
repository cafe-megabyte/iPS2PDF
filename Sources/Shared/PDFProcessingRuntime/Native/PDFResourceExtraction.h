#pragma once

#include <cstdint>
#include <filesystem>
#include <string>

namespace ips2pdf {

std::uintmax_t extractPDFResource(const std::filesystem::path& input,
                                  const std::filesystem::path& output,
                                  const std::string& password,
                                  const std::string& format,
                                  const std::string& fingerprint,
                                  int width, int height, int bitsPerComponent);

} // namespace ips2pdf
