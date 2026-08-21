#ifndef GhostscriptBridge_h
#define GhostscriptBridge_h

#include <stddef.h>

typedef enum GSBridgeStage {
    GS_BRIDGE_STAGE_NONE = 0,
    GS_BRIDGE_STAGE_NEW_INSTANCE = 1,
    GS_BRIDGE_STAGE_INITIALIZATION = 2,
    GS_BRIDGE_STAGE_CONVERSION = 3
} GSBridgeStage;

/*
 * Executes the ps2pdf12/13/14 argument semantics with a fresh Ghostscript
 * interpreter instance. `diagnostics` receives the first 300 UTF-8 bytes and
 * a truncation marker when needed. The caller owns all buffers.
 */
int gs_convert_to_pdf(
    const char *input_path,
    const char *output_path,
    const char *pdf_version,
    const char *pdfa_version,
    const char *pdfa_definition_path,
    const char *pdfa_resource_directory,
    char *diagnostics,
    size_t diagnostics_capacity,
    int *ghostscript_return_code,
    int *stage
);

/*
 * Descriptor-only entry point used by the Enhanced Security helpers. No path
 * from the host process crosses the XPC boundary. Joboptions are executed
 * before the input stream and diagnostics are written directly to journal_fd.
 */
int gs_run_joboptions_with_fds(
    int input_fd,
    int output_fd,
    int joboptions_fd,
    int journal_fd,
    int validation_only,
    int allow_transparency,
    const char *standard,
    const char *standard_definition_path,
    const char *ghostscript_resource_directory,
    const char *profile_resource_directory,
    const char *profile_overrides,
    const char *profile_override_directory,
    int limits_enabled,
    long long deadline_epoch_seconds,
    long long maximum_output_bytes,
    int *ghostscript_return_code,
    int *stage
);

void gs_bridge_reset_cancellation(void);
void gs_bridge_request_cancellation(void);

#endif /* GhostscriptBridge_h */
