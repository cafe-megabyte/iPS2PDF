#include "GhostscriptBridge.h"

#include <stdio.h>
#include <string.h>

#include "gserrors.h"
#include "iapi.h"

enum {
    kMaximumDiagnosticBytes = 300,
    kOutputArgumentCapacity = 8192
};

typedef struct BridgeCapture {
    char stdout_text[kMaximumDiagnosticBytes + 1];
    size_t stdout_length;
    int stdout_truncated;
    char stderr_text[kMaximumDiagnosticBytes + 1];
    size_t stderr_length;
    int stderr_truncated;
} BridgeCapture;

static void append_capture(
    char *destination,
    size_t *length,
    int *truncated,
    const char *source,
    int source_length
)
{
    if (source == NULL || source_length <= 0) {
        return;
    }

    if (*length >= kMaximumDiagnosticBytes) {
        *truncated = 1;
        return;
    }

    size_t available = kMaximumDiagnosticBytes - *length;
    size_t copied = (size_t)source_length < available ? (size_t)source_length : available;
    memcpy(destination + *length, source, copied);
    *length += copied;
    destination[*length] = '\0';
    if (copied < (size_t)source_length) {
        *truncated = 1;
    }
}

static int bridge_stdin(void *caller_handle, char *buffer, int length)
{
    (void)caller_handle;
    (void)buffer;
    (void)length;
    return 0;
}

static int bridge_stdout(void *caller_handle, const char *text, int length)
{
    BridgeCapture *capture = (BridgeCapture *)caller_handle;
    append_capture(
        capture->stdout_text,
        &capture->stdout_length,
        &capture->stdout_truncated,
        text,
        length
    );
    return length;
}

static int bridge_stderr(void *caller_handle, const char *text, int length)
{
    BridgeCapture *capture = (BridgeCapture *)caller_handle;
    append_capture(
        capture->stderr_text,
        &capture->stderr_length,
        &capture->stderr_truncated,
        text,
        length
    );
    return length;
}

static void copy_diagnostics(
    const BridgeCapture *capture,
    char *diagnostics,
    size_t diagnostics_capacity
)
{
    if (diagnostics == NULL || diagnostics_capacity == 0) {
        return;
    }

    const int use_stderr = capture->stderr_length > 0;
    const char *source = use_stderr ? capture->stderr_text : capture->stdout_text;
    size_t source_length = use_stderr ? capture->stderr_length : capture->stdout_length;
    const int truncated = use_stderr ? capture->stderr_truncated : capture->stdout_truncated;
    size_t copied = source_length < diagnostics_capacity - 1 ? source_length : diagnostics_capacity - 1;
    memcpy(diagnostics, source, copied);
    diagnostics[copied] = '\0';

    if (truncated && copied < diagnostics_capacity - 1) {
        const char marker[] = "\n[truncated]";
        size_t marker_length = sizeof(marker) - 1;
        size_t marker_copied = marker_length < diagnostics_capacity - copied - 1
            ? marker_length
            : diagnostics_capacity - copied - 1;
        memcpy(diagnostics + copied, marker, marker_copied);
        diagnostics[copied + marker_copied] = '\0';
    }
}

static int is_pdf_version(const char *version, const char *expected)
{
    return version != NULL && strcmp(version, expected) == 0;
}

int gs_convert_to_pdf(
    const char *input_path,
    const char *output_path,
    const char *pdf_version,
    char *diagnostics,
    size_t diagnostics_capacity,
    int *ghostscript_return_code,
    int *stage
)
{
    BridgeCapture capture = {0};
    void *instance = NULL;
    int return_code = 0;
    int initialized = 0;
    int current_stage = GS_BRIDGE_STAGE_NEW_INSTANCE;
    char output_argument[kOutputArgumentCapacity];

    if (diagnostics != NULL && diagnostics_capacity > 0) {
        diagnostics[0] = '\0';
    }
    if (ghostscript_return_code != NULL) {
        *ghostscript_return_code = 0;
    }
    if (stage != NULL) {
        *stage = GS_BRIDGE_STAGE_NONE;
    }

    if (input_path == NULL || output_path == NULL ||
        snprintf(output_argument, sizeof(output_argument), "-sOutputFile=%s", output_path) >= (int)sizeof(output_argument)) {
        if (stage != NULL) {
            *stage = GS_BRIDGE_STAGE_CONVERSION;
        }
        return -1;
    }

    const char *compatibility_option = NULL;
    const char *xref_option = NULL;
    const char *object_stream_option = NULL;

    if (is_pdf_version(pdf_version, "1.1")) {
        compatibility_option = "-dCompatibilityLevel=1.1";
        xref_option = "-dWriteXRefStm=false";
        object_stream_option = "-dWriteObjStms=false";
    } else if (is_pdf_version(pdf_version, "1.2")) {
        compatibility_option = "-dCompatibilityLevel=1.2";
        xref_option = "-dWriteXRefStm=false";
        object_stream_option = "-dWriteObjStms=false";
    } else if (is_pdf_version(pdf_version, "1.3")) {
        compatibility_option = "-dCompatibilityLevel=1.3";
    } else if (is_pdf_version(pdf_version, "1.4")) {
        compatibility_option = "-dCompatibilityLevel=1.4";
        xref_option = "-dWriteXRefStm=false";
        object_stream_option = "-dWriteObjStms=false";
    } else if (is_pdf_version(pdf_version, "1.5")) {
        compatibility_option = "-dCompatibilityLevel=1.5";
        xref_option = "-dWriteXRefStm=true";
        object_stream_option = "-dWriteObjStms=true";
    } else if (is_pdf_version(pdf_version, "1.6")) {
        compatibility_option = "-dCompatibilityLevel=1.6";
        xref_option = "-dWriteXRefStm=true";
        object_stream_option = "-dWriteObjStms=true";
    } else if (is_pdf_version(pdf_version, "1.7")) {
        compatibility_option = "-dCompatibilityLevel=1.7";
        xref_option = "-dWriteXRefStm=true";
        object_stream_option = "-dWriteObjStms=true";
    } else if (is_pdf_version(pdf_version, "2.0")) {
        compatibility_option = "-dCompatibilityLevel=2.0";
        xref_option = "-dWriteXRefStm=true";
        object_stream_option = "-dWriteObjStms=true";
    } else {
        if (stage != NULL) {
            *stage = GS_BRIDGE_STAGE_CONVERSION;
        }
        return -1;
    }

    return_code = gsapi_new_instance(&instance, &capture);
    if (return_code != 0) {
        goto finished;
    }

    return_code = gsapi_set_stdio(instance, bridge_stdin, bridge_stdout, bridge_stderr);
    if (return_code != 0) {
        goto finished;
    }

    return_code = gsapi_set_arg_encoding(instance, GS_ARG_ENCODING_UTF8);
    if (return_code != 0) {
        goto finished;
    }

    current_stage = GS_BRIDGE_STAGE_INITIALIZATION;

    /*
     * This is the argument sequence used by ps2pdf12/13/14 -> ps2pdfwr.
     * ps2pdfwr deliberately supplies OPTIONS before and after pdfwrite's
     * core arguments, so the order is retained exactly here.
     */
    const char *arguments[24];
    int argument_count = 0;
    arguments[argument_count++] = "iPS2PDF";
    arguments[argument_count++] = "-P-";
    arguments[argument_count++] = "-dSAFER";
    arguments[argument_count++] = compatibility_option;
    if (xref_option != NULL) {
        arguments[argument_count++] = xref_option;
        arguments[argument_count++] = object_stream_option;
    }
    arguments[argument_count++] = "-q";
    arguments[argument_count++] = "-P-";
    arguments[argument_count++] = "-dNOPAUSE";
    arguments[argument_count++] = "-dBATCH";
    arguments[argument_count++] = "-sDEVICE=pdfwrite";
    arguments[argument_count++] = "-sstdout=%stderr";
    arguments[argument_count++] = output_argument;
    arguments[argument_count++] = "-P-";
    arguments[argument_count++] = "-dSAFER";
    arguments[argument_count++] = compatibility_option;
    if (xref_option != NULL) {
        arguments[argument_count++] = xref_option;
        arguments[argument_count++] = object_stream_option;
    }
    arguments[argument_count++] = input_path;

    return_code = gsapi_init_with_args(instance, argument_count, (char **)arguments);
    initialized = 1;
    if (return_code == gs_error_Quit) {
        return_code = 0;
    }
    current_stage = GS_BRIDGE_STAGE_CONVERSION;

finished:
    if (initialized) {
        int exit_code = gsapi_exit(instance);
        if (return_code == 0 && exit_code != 0) {
            return_code = exit_code;
        }
    }
    if (instance != NULL) {
        gsapi_delete_instance(instance);
    }

    copy_diagnostics(&capture, diagnostics, diagnostics_capacity);
    if (ghostscript_return_code != NULL) {
        *ghostscript_return_code = return_code;
    }
    if (stage != NULL) {
        *stage = return_code == 0 ? GS_BRIDGE_STAGE_NONE : current_stage;
    }

    return return_code == 0 ? 0 : -1;
}
