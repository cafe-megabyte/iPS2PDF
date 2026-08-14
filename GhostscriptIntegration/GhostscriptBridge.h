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
    char *diagnostics,
    size_t diagnostics_capacity,
    int *ghostscript_return_code,
    int *stage
);

#endif /* GhostscriptBridge_h */
