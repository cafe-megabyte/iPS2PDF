#include "GhostscriptBridge.h"

#include <stdio.h>
#include <string.h>

#include "gserrors.h"
#include "iapi.h"

enum {
    kMaximumDiagnosticBytes = 300,
    kOutputArgumentCapacity = 8192,
    kMaximumGhostscriptArguments = 100
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

static int is_pdfa_version(const char *version, const char *expected)
{
    return version != NULL && strcmp(version, expected) == 0;
}

static void append_argument(const char **arguments, int *argument_count, const char *argument)
{
    arguments[(*argument_count)++] = argument;
}

static void append_common_pdfwrite_options(
    const char **arguments,
    int *argument_count,
    int pdfa_enabled,
    int supports_transparency,
    int allow_postscript_transparency
)
{
    static const char *options[] = {
        "-dAutoRotatePages=/None",
        "-dPreserveOverprintSettings=true",
        "-dTransferFunctionInfo=/Apply",
        "-dUCRandBGInfo=/Remove",
        "-dDownsampleColorImages=false",
        "-dDownsampleGrayImages=false",
        "-dDownsampleMonoImages=false",
        "-dPassThroughJPEGImages=true",
        "-dPassThroughJPXImages=false",
        "-dEncodeColorImages=true",
        "-dEncodeGrayImages=true",
        "-dEncodeMonoImages=true",
        "-dAutoFilterColorImages=true",
        "-dAutoFilterGrayImages=true",
        "-dColorImageFilter=/DCTEncode",
        "-dGrayImageFilter=/DCTEncode",
        "-dMonoImageFilter=/CCITTFaxEncode",
        "-dEmbedAllFonts=true",
        "-dEmbedSubstituteFonts=true",
        "-dSubsetFonts=true",
        "-dMaxSubsetPct=100",
        "-dCompressPages=true",
        "-dCompressStreams=true",
        "-dFastWebView=false",
        "-r2400"
    };

    if (!pdfa_enabled) {
        append_argument(arguments, argument_count, "-sColorConversionStrategy=LeaveColorUnchanged");
    }
    if (supports_transparency) {
        append_argument(arguments, argument_count, "-dHaveTransparency=true");
        if (allow_postscript_transparency) {
            append_argument(arguments, argument_count, "-dALLOWPSTRANSPARENCY");
        }
    }

    for (size_t index = 0; index < sizeof(options) / sizeof(options[0]); index++) {
        append_argument(arguments, argument_count, options[index]);
    }
}

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
)
{
    BridgeCapture capture = {0};
    void *instance = NULL;
    int return_code = 0;
    int initialized = 0;
    int current_stage = GS_BRIDGE_STAGE_NEW_INSTANCE;
    char output_argument[kOutputArgumentCapacity];
    char pdfa_option[32];
    char pdfa_include_argument[kOutputArgumentCapacity];
    char pdfa_permit_read_argument[kOutputArgumentCapacity];
    char transparency_prolog[kOutputArgumentCapacity];

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
    const char *pdfa_policy_option = NULL;
    const char *pdfa_color_conversion_option = NULL;
    const char *pdfa_blend_conversion_option = NULL;
    const int pdfa_enabled = pdfa_version != NULL && pdfa_version[0] != '\0';
    int supports_transparency = 0;
    int permits_pdfa_transparency = 0;
    int allow_postscript_transparency = 0;
    const char *distiller_parameters =
        "<<"
        " /NeverEmbed []"
        " /ColorImageDict <<"
        " /QFactor 0.15"
        " /HSamples [1 1 1 1]"
        " /VSamples [1 1 1 1]"
        " >>"
        " /ColorACSImageDict <<"
        " /QFactor 0.15"
        " /HSamples [1 1 1 1]"
        " /VSamples [1 1 1 1]"
        " >>"
        " /GrayImageDict <<"
        " /QFactor 0.15"
        " /HSamples [1 1 1 1]"
        " /VSamples [1 1 1 1]"
        " >>"
        " /GrayACSImageDict <<"
        " /QFactor 0.15"
        " /HSamples [1 1 1 1]"
        " /VSamples [1 1 1 1]"
        " >>"
        " /MonoImageDict <<"
        " /K -1"
        " >>"
        " >> setdistillerparams";

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
        supports_transparency = 1;
    } else if (is_pdf_version(pdf_version, "1.5")) {
        compatibility_option = "-dCompatibilityLevel=1.5";
        xref_option = "-dWriteXRefStm=true";
        object_stream_option = "-dWriteObjStms=true";
        supports_transparency = 1;
        permits_pdfa_transparency = 1;
    } else if (is_pdf_version(pdf_version, "1.6")) {
        compatibility_option = "-dCompatibilityLevel=1.6";
        xref_option = "-dWriteXRefStm=true";
        object_stream_option = "-dWriteObjStms=true";
        supports_transparency = 1;
        permits_pdfa_transparency = 1;
    } else if (is_pdf_version(pdf_version, "1.7")) {
        compatibility_option = "-dCompatibilityLevel=1.7";
        xref_option = "-dWriteXRefStm=true";
        object_stream_option = "-dWriteObjStms=true";
        supports_transparency = 1;
        permits_pdfa_transparency = 1;
    } else if (is_pdf_version(pdf_version, "2.0")) {
        compatibility_option = "-dCompatibilityLevel=2.0";
        xref_option = "-dWriteXRefStm=true";
        object_stream_option = "-dWriteObjStms=true";
        supports_transparency = 1;
        permits_pdfa_transparency = 1;
    } else {
        if (stage != NULL) {
            *stage = GS_BRIDGE_STAGE_CONVERSION;
        }
        return -1;
    }

    if (pdfa_enabled) {
        if (!is_pdfa_version(pdfa_version, "1") &&
            !is_pdfa_version(pdfa_version, "2") &&
            !is_pdfa_version(pdfa_version, "3")) {
            if (stage != NULL) {
                *stage = GS_BRIDGE_STAGE_CONVERSION;
            }
            return -1;
        }
        if (pdfa_definition_path == NULL || pdfa_resource_directory == NULL ||
            snprintf(pdfa_option, sizeof(pdfa_option), "-dPDFA=%s", pdfa_version) >= (int)sizeof(pdfa_option) ||
            snprintf(pdfa_include_argument, sizeof(pdfa_include_argument), "-I%s", pdfa_resource_directory) >= (int)sizeof(pdfa_include_argument) ||
            snprintf(pdfa_permit_read_argument, sizeof(pdfa_permit_read_argument), "--permit-file-read=%s", pdfa_resource_directory) >= (int)sizeof(pdfa_permit_read_argument)) {
            if (stage != NULL) {
                *stage = GS_BRIDGE_STAGE_CONVERSION;
            }
            return -1;
        }
        pdfa_policy_option = "-dPDFACompatibilityPolicy=2";
        pdfa_color_conversion_option = "-sColorConversionStrategy=RGB";
        if (is_pdfa_version(pdfa_version, "2") || is_pdfa_version(pdfa_version, "3")) {
            pdfa_blend_conversion_option = "-sBlendConversionStrategy=Simple";
        }
    }

    allow_postscript_transparency = supports_transparency && (!pdfa_enabled || permits_pdfa_transparency);
    if (allow_postscript_transparency &&
        snprintf(
            transparency_prolog,
            sizeof(transparency_prolog),
            "<<"
            " /PageUsesTransparency true"
            " /CompatibilityLevel %s"
            " /PageSpotColors 0"
            " >> setpagedevice"
            " 0 .pushpdf14devicefilter"
            " /.origshowpage /showpage load def"
            " /showpage {"
            " .poppdf14devicefilter"
            " .origshowpage"
            " } bind def"
            " /.origpdfmark /pdfmark load def"
            " /pdfmark {"
            " dup /SetTransparency eq {"
            " pop"
            " counttomark 2 idiv dict begin"
            " counttomark 2 idiv { def } repeat"
            " ca .setfillconstantalpha"
            " CA .setstrokeconstantalpha"
            " BM .setblendmode"
            " end"
            " pop"
            " } {"
            " .origpdfmark"
            " } ifelse"
            " } bind def",
            pdf_version
        ) >= (int)sizeof(transparency_prolog)) {
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
    const char *arguments[kMaximumGhostscriptArguments];
    int argument_count = 0;
    arguments[argument_count++] = "iPS2PDF";
    arguments[argument_count++] = "-P-";
    arguments[argument_count++] = "-dSAFER";
    if (pdfa_enabled) {
        arguments[argument_count++] = pdfa_include_argument;
        arguments[argument_count++] = pdfa_permit_read_argument;
        arguments[argument_count++] = pdfa_option;
        arguments[argument_count++] = pdfa_policy_option;
        arguments[argument_count++] = pdfa_color_conversion_option;
        if (pdfa_blend_conversion_option != NULL) {
            arguments[argument_count++] = pdfa_blend_conversion_option;
        }
    }
    append_common_pdfwrite_options(
        arguments,
        &argument_count,
        pdfa_enabled,
        supports_transparency,
        allow_postscript_transparency
    );
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
    if (pdfa_enabled) {
        arguments[argument_count++] = pdfa_include_argument;
        arguments[argument_count++] = pdfa_permit_read_argument;
        arguments[argument_count++] = pdfa_option;
        arguments[argument_count++] = pdfa_policy_option;
        arguments[argument_count++] = pdfa_color_conversion_option;
        if (pdfa_blend_conversion_option != NULL) {
            arguments[argument_count++] = pdfa_blend_conversion_option;
        }
    }
    append_common_pdfwrite_options(
        arguments,
        &argument_count,
        pdfa_enabled,
        supports_transparency,
        allow_postscript_transparency
    );
    arguments[argument_count++] = compatibility_option;
    if (xref_option != NULL) {
        arguments[argument_count++] = xref_option;
        arguments[argument_count++] = object_stream_option;
    }
    if (pdfa_enabled) {
        arguments[argument_count++] = pdfa_definition_path;
    }
    arguments[argument_count++] = "-c";
    arguments[argument_count++] = distiller_parameters;
    if (allow_postscript_transparency) {
        arguments[argument_count++] = "-c";
        arguments[argument_count++] = transparency_prolog;
    }
    arguments[argument_count++] = "-f";
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
