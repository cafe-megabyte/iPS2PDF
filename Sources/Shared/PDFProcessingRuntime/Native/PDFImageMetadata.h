#pragma once

#include <cstdint>
#include <span>
#include <vector>

namespace ips2pdf {

// Remove JPEG container metadata without decoding or re-encoding image samples.
// ICC chunks are preserved for metadata-only editing and removed only after
// the compression pipeline has converted the pixels to the output color space.
// Malformed marker structure throws; callers must not claim successful cleanup.
std::vector<uint8_t> removeJPEGMetadata(std::span<const uint8_t> input, bool preserveICC);

} // namespace ips2pdf
