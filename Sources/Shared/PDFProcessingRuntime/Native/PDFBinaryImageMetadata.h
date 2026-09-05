#pragma once
#include <cstdint>
#include <span>
#include <vector>
namespace ips2pdf {
std::vector<uint8_t> removeJPEG2000Metadata(std::span<const uint8_t> input);
std::vector<uint8_t> removeJBIG2Metadata(std::span<const uint8_t> input);
} // namespace ips2pdf
