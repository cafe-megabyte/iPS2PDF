#pragma once

#ifdef __cplusplus
extern "C" {
#endif

// Runs only synthetic fixtures. The caller owns the output directory.
// A nonzero return value means at least one native feasibility check failed.
__attribute__((visibility("default")))
int ips2pdf_run_native_smoke(const char* fixture_directory, const char* output_directory);

#ifdef __cplusplus
}
#endif
