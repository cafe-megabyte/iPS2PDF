#ifndef GhostscriptBridge_h
#define GhostscriptBridge_h

typedef enum GSBridgeStage {
    GS_BRIDGE_STAGE_NONE = 0,
    GS_BRIDGE_STAGE_NEW_INSTANCE = 1,
    GS_BRIDGE_STAGE_INITIALIZATION = 2,
    GS_BRIDGE_STAGE_CONVERSION = 3
} GSBridgeStage;

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
    const char *compatibility_level,
    const char *standard,
    const char *standard_definition_path,
    const char *ghostscript_resource_directory,
    const char *profile_resource_directory,
    const char *profile_overrides,
    const char *profile_override_directory,
    const char *blend_conversion_strategy,
    int postscript_random_seed,
    int limits_enabled,
    long long deadline_epoch_seconds,
    long long maximum_output_bytes,
    int *ghostscript_return_code,
    int *stage
);

void gs_bridge_reset_cancellation(void);
void gs_bridge_request_cancellation(void);

#endif /* GhostscriptBridge_h */
