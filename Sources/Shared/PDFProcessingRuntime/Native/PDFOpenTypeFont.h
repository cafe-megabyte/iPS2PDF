#pragma once

#include <cstdint>
#include <span>
#include <vector>

namespace ips2pdf {

std::vector<uint8_t> openTypeContainerForCFF(std::span<const uint8_t> cff);

} // namespace ips2pdf
