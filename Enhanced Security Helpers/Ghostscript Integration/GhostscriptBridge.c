#include "GhostscriptBridge.h"

#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <sys/stat.h>
#include <signal.h>
#include <time.h>
#include <unistd.h>

#include "gserrors.h"
#include "iapi.h"

/* Public Ghostscript gp_file helpers are linked from libgs, but gp.h pulls
 * internal build headers that intentionally are not part of this bridge's
 * public include surface. iapi.h already supplies the opaque types. */
extern gp_file *gp_file_FILE_alloc(const gs_memory_t *mem);
extern int gp_file_FILE_set(gp_file *file, FILE *stream, int (*close_fn)(FILE *));

static int bridge_stdin(void *caller_handle, char *buffer, int length)
{
    (void)caller_handle;
    (void)buffer;
    (void)length;
    return 0;
}

static int is_pdf_version(const char *version, const char *expected)
{
    return version != NULL && strcmp(version, expected) == 0;
}

enum { kMaximumJournalBytes = 1024 * 1024 };

typedef struct DescriptorCapture {
    int input_fd;
    int journal_fd;
    int output_fd;
    int limits_enabled;
    long long deadline_epoch_seconds;
    long long maximum_output_bytes;
    size_t journal_bytes;
    int limit_reason;
} DescriptorCapture;

static const char *kDescriptorInputPDFName = "iPS2PDF-input.pdf";
static const char *kDescriptorOutputName = "iPS2PDF-output.pdf";

static volatile sig_atomic_t descriptor_cancellation_requested = 0;

void gs_bridge_reset_cancellation(void)
{
    descriptor_cancellation_requested = 0;
}

void gs_bridge_request_cancellation(void)
{
    descriptor_cancellation_requested = 1;
}

static int descriptor_write(DescriptorCapture *capture, const char *text, int length)
{
    if (capture == NULL || text == NULL || length <= 0) {
        return length;
    }
    size_t remaining = capture->journal_bytes < kMaximumJournalBytes
        ? kMaximumJournalBytes - capture->journal_bytes
        : 0;
    size_t requested = (size_t)length < remaining ? (size_t)length : remaining;
    while (requested > 0) {
        ssize_t result = write(capture->journal_fd, text, requested);
        if (result < 0 && errno == EINTR) {
            continue;
        }
        if (result <= 0) {
            break;
        }
        capture->journal_bytes += (size_t)result;
        text += result;
        requested -= (size_t)result;
    }
    return length;
}

static int descriptor_stdout(void *caller_handle, const char *text, int length)
{
    return descriptor_write((DescriptorCapture *)caller_handle, text, length);
}

static int descriptor_stderr(void *caller_handle, const char *text, int length)
{
    return descriptor_write((DescriptorCapture *)caller_handle, text, length);
}

static int descriptor_poll(void *caller_handle)
{
    DescriptorCapture *capture = (DescriptorCapture *)caller_handle;
    if (capture == NULL) {
        return 0;
    }
    if (descriptor_cancellation_requested) {
        capture->limit_reason = 3;
        return -1;
    }
    if (!capture->limits_enabled) return 0;
    if ((long long)time(NULL) >= capture->deadline_epoch_seconds) {
        capture->limit_reason = 1;
        return -1;
    }
    struct stat status;
    if (capture->output_fd >= 0 &&
        fstat(capture->output_fd, &status) == 0 &&
        (long long)status.st_size > capture->maximum_output_bytes) {
        capture->limit_reason = 2;
        return -1;
    }
    return 0;
}

static int descriptor_run_stream(
    void *instance,
    int descriptor,
    DescriptorCapture *capture
)
{
    char buffer[64 * 1024];
    int exit_code = 0;
    int code = gsapi_run_string_begin(instance, 0, &exit_code);
    if (code != 0) return code;

    if (lseek(descriptor, 0, SEEK_SET) < 0) {
        return -1;
    }
    for (;;) {
        if (descriptor_poll(capture) != 0) return -1;
        ssize_t count = read(descriptor, buffer, sizeof(buffer));
        if (count < 0 && errno == EINTR) continue;
        if (count < 0) return -1;
        if (count == 0) break;
        code = gsapi_run_string_continue(
            instance,
            buffer,
            (unsigned int)count,
            0,
            &exit_code
        );
        if (code != 0 && code != gs_error_NeedInput) return code;
    }

    code = gsapi_run_string_end(instance, 0, &exit_code);
    return code == gs_error_NeedInput ? 0 : code;
}

static int descriptor_run_bytes(
    void *instance,
    const char *bytes,
    DescriptorCapture *capture
)
{
    if (bytes == NULL || bytes[0] == '\0') return 0;
    if (descriptor_poll(capture) != 0) return -1;
    int exit_code = 0;
    int code = gsapi_run_string_with_length(
        instance,
        bytes,
        (unsigned int)strlen(bytes),
        0,
        &exit_code
    );
    return code == gs_error_NeedInput ? 0 : code;
}

static int descriptor_run_file(
    void *instance,
    const char *filename,
    DescriptorCapture *capture
)
{
    if (descriptor_poll(capture) != 0) return -1;
    int exit_code = 0;
    int code = gsapi_run_file(instance, filename, 0, &exit_code);
    return code == gs_error_NeedInput ? 0 : code;
}

static int descriptor_is_pdf(int descriptor)
{
    unsigned char header[5];
    ssize_t count;

    if (lseek(descriptor, 0, SEEK_SET) < 0) return 0;
    do {
        count = read(descriptor, header, sizeof(header));
    } while (count < 0 && errno == EINTR);
    lseek(descriptor, 0, SEEK_SET);

    return count == (ssize_t)sizeof(header) &&
        memcmp(header, "%PDF-", sizeof(header)) == 0;
}

static int descriptor_make_input_file(
    const gs_memory_t *memory,
    DescriptorCapture *capture,
    const char *mode,
    gp_file **file
)
{
    FILE *stream = NULL;
    *file = NULL;
    if (capture->input_fd < 0 || strchr(mode, 'w') != NULL || strchr(mode, 'a') != NULL) {
        return -1;
    }

    int duplicate = dup(capture->input_fd);
    if (duplicate >= 0) {
        lseek(duplicate, 0, SEEK_SET);
        stream = fdopen(duplicate, "rb");
        if (stream == NULL) close(duplicate);
    }
    if (stream == NULL) return -1;

    gp_file *result = gp_file_FILE_alloc(memory);
    if (result == NULL || gp_file_FILE_set(result, stream, fclose) != 0) {
        fclose(stream);
        return -1;
    }
    *file = result;
    return 0;
}

static int descriptor_make_output_file(
    const gs_memory_t *memory,
    DescriptorCapture *capture,
    const char *mode,
    gp_file **file
)
{
    FILE *stream = NULL;
    *file = NULL;
    if (capture->output_fd < 0) {
        stream = fopen("/dev/null", mode);
    } else {
        int duplicate = dup(capture->output_fd);
        if (duplicate >= 0) {
            stream = fdopen(duplicate, mode);
            if (stream == NULL) close(duplicate);
        }
    }
    if (stream == NULL) return -1;

    gp_file *result = gp_file_FILE_alloc(memory);
    if (result == NULL || gp_file_FILE_set(result, stream, fclose) != 0) {
        fclose(stream);
        return -1;
    }
    *file = result;
    return 0;
}

static int descriptor_open_file(
    const gs_memory_t *memory,
    void *secret,
    const char *filename,
    const char *mode,
    gp_file **file
)
{
    *file = NULL;
    if (strcmp(filename, kDescriptorInputPDFName) == 0) {
        return descriptor_make_input_file(
            memory,
            (DescriptorCapture *)secret,
            mode,
            file
        );
    }
    if (strcmp(filename, kDescriptorOutputName) != 0) return 0;
    if (strchr(mode, 'w') == NULL && strchr(mode, 'a') == NULL) return -1;
    return descriptor_make_output_file(
        memory,
        (DescriptorCapture *)secret,
        mode,
        file
    );
}

static int descriptor_open_printer(
    const gs_memory_t *memory,
    void *secret,
    char *filename,
    int binary,
    gp_file **file
)
{
    *file = NULL;
    if (strcmp(filename, kDescriptorOutputName) != 0) return 0;
    return descriptor_make_output_file(
        memory,
        (DescriptorCapture *)secret,
        binary ? "wb" : "w",
        file
    );
}

static gsapi_fs_t descriptor_file_system = {
    .open_file = descriptor_open_file,
    .open_pipe = NULL,
    .open_scratch = NULL,
    .open_printer = descriptor_open_printer,
    .open_handle = NULL
};

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
    int limits_enabled,
    long long deadline_epoch_seconds,
    long long maximum_output_bytes,
    int *ghostscript_return_code,
    int *stage
)
{
    void *instance = NULL;
    int return_code = 0;
    int initialized = 0;
    int file_system_added = 0;
    int current_stage = GS_BRIDGE_STAGE_NEW_INSTANCE;
    int standard_definition_fd = -1;
    char compatibility_option[32];
    char standard_option[32];
    char blend_conversion_option[40];
    char ghostscript_include[PATH_MAX + 3];
    char profile_include[PATH_MAX + 3];
    char permit_ghostscript[PATH_MAX + 24];
    char permit_profiles[PATH_MAX + 24];
    char permit_profile_overrides[PATH_MAX + 24];
    DescriptorCapture capture = {
        .input_fd = input_fd,
        .journal_fd = journal_fd,
        .output_fd = output_fd,
        .limits_enabled = limits_enabled,
        .deadline_epoch_seconds = deadline_epoch_seconds,
        .maximum_output_bytes = maximum_output_bytes,
        .journal_bytes = 0,
        .limit_reason = 0
    };

    if (ghostscript_return_code != NULL) *ghostscript_return_code = 0;
    if (stage != NULL) *stage = GS_BRIDGE_STAGE_NONE;
    if (joboptions_fd < 0 || journal_fd < 0 || (!validation_only && (input_fd < 0 || output_fd < 0))) {
        return -1;
    }

    lseek(joboptions_fd, 0, SEEK_SET);
    if (!validation_only) {
        lseek(input_fd, 0, SEEK_SET);
        ftruncate(output_fd, 0);
        lseek(output_fd, 0, SEEK_SET);
    }
    lseek(journal_fd, 0, SEEK_END);

    const char *starting_marker = "[iPS2PDF] starting Ghostscript\n";
    descriptor_write(&capture, starting_marker, (int)strlen(starting_marker));
    return_code = gsapi_new_instance(&instance, &capture);
    if (return_code != 0) goto descriptor_finished;
    return_code = gsapi_set_stdio(instance, bridge_stdin, descriptor_stdout, descriptor_stderr);
    if (return_code != 0) goto descriptor_finished;
    return_code = gsapi_set_poll_with_handle(instance, descriptor_poll, &capture);
    if (return_code != 0) goto descriptor_finished;
    return_code = gsapi_set_arg_encoding(instance, GS_ARG_ENCODING_UTF8);
    if (return_code != 0) goto descriptor_finished;
    return_code = gsapi_add_fs(instance, &descriptor_file_system, &capture);
    if (return_code != 0) goto descriptor_finished;
    file_system_added = 1;

    current_stage = GS_BRIDGE_STAGE_INITIALIZATION;
    const int has_standard = standard != NULL && strcmp(standard, "none") != 0;
    const int is_pdfa = has_standard && strncmp(standard, "pdfa", 4) == 0;
    const int is_pdfx = has_standard && strncmp(standard, "pdfx", 4) == 0;
    const int has_compatibility_level =
        compatibility_level != NULL && compatibility_level[0] != '\0';
    const int has_blend_conversion_strategy =
        blend_conversion_strategy != NULL && blend_conversion_strategy[0] != '\0';
    const int uses_pre_pdf15_layout =
        is_pdf_version(compatibility_level, "1.1") ||
        is_pdf_version(compatibility_level, "1.2") ||
        is_pdf_version(compatibility_level, "1.3") ||
        is_pdf_version(compatibility_level, "1.4");
    if (has_compatibility_level) {
        if (!is_pdf_version(compatibility_level, "1.1") &&
            !is_pdf_version(compatibility_level, "1.2") &&
            !is_pdf_version(compatibility_level, "1.3") &&
            !is_pdf_version(compatibility_level, "1.4") &&
            !is_pdf_version(compatibility_level, "1.5") &&
            !is_pdf_version(compatibility_level, "1.6") &&
            !is_pdf_version(compatibility_level, "1.7") &&
            !is_pdf_version(compatibility_level, "2.0")) {
            return_code = -1;
            goto descriptor_finished;
        }
        snprintf(
            compatibility_option,
            sizeof(compatibility_option),
            "-dCompatibilityLevel=%s",
            compatibility_level
        );
    }
    if (has_blend_conversion_strategy &&
        strcmp(blend_conversion_strategy, "None") != 0 &&
        strcmp(blend_conversion_strategy, "Simple") != 0 &&
        strcmp(blend_conversion_strategy, "Managed") != 0) {
        return_code = -1;
        goto descriptor_finished;
    }
    snprintf(
        blend_conversion_option,
        sizeof(blend_conversion_option),
        "-sBlendConversionStrategy=%s",
        has_blend_conversion_strategy ? blend_conversion_strategy : "Simple"
    );
    if (has_standard && (standard_definition_path == NULL || ghostscript_resource_directory == NULL || profile_resource_directory == NULL)) {
        return_code = -1;
        goto descriptor_finished;
    }
    if (is_pdfa) {
        const char *generation = standard[4] == '1' ? "1" : (standard[4] == '2' ? "2" : "3");
        snprintf(standard_option, sizeof(standard_option), "-dPDFA=%s", generation);
    } else if (is_pdfx) {
        const char *generation = standard[4] == '1' ? "1" : (standard[4] == '3' ? "3" : "4");
        snprintf(standard_option, sizeof(standard_option), "-dPDFX=%s", generation);
    }
    if (has_standard) {
        standard_definition_fd = open(standard_definition_path, O_RDONLY);
        if (standard_definition_fd < 0) {
            return_code = -1;
            goto descriptor_finished;
        }
        snprintf(ghostscript_include, sizeof(ghostscript_include), "-I%s", ghostscript_resource_directory);
        snprintf(permit_ghostscript, sizeof(permit_ghostscript), "--permit-file-read=%s", ghostscript_resource_directory);
    }
    const int has_profile_overrides = profile_overrides != NULL && profile_overrides[0] != '\0';
    if ((has_standard || has_profile_overrides) && profile_resource_directory == NULL) {
        return_code = -1;
        goto descriptor_finished;
    }
    if (has_standard || has_profile_overrides) {
        snprintf(profile_include, sizeof(profile_include), "-I%s", profile_resource_directory);
        snprintf(permit_profiles, sizeof(permit_profiles), "--permit-file-read=%s", profile_resource_directory);
    }
    const int has_profile_override_directory =
        profile_override_directory != NULL && profile_override_directory[0] != '\0';
    if (has_profile_override_directory) {
        snprintf(
            permit_profile_overrides,
            sizeof(permit_profile_overrides),
            "--permit-file-read=%s",
            profile_override_directory
        );
    }

    const char *arguments[48];
    int argument_count = 0;
    arguments[argument_count++] = "iPS2PDF";
    arguments[argument_count++] = "-P-";
    arguments[argument_count++] = "-dSAFER";
    if (!validation_only) arguments[argument_count++] = "--permit-file-read=iPS2PDF-input.pdf";
    arguments[argument_count++] = "--permit-file-write=iPS2PDF-output.pdf";
    if (allow_transparency && !validation_only) {
        arguments[argument_count++] = "-dHaveTransparency=true";
        arguments[argument_count++] = "-dALLOWPSTRANSPARENCY";
    }
    if (has_standard) {
        arguments[argument_count++] = ghostscript_include;
        arguments[argument_count++] = permit_ghostscript;
    }
    if (has_standard || has_profile_overrides) {
        arguments[argument_count++] = profile_include;
        arguments[argument_count++] = permit_profiles;
    }
    if (has_standard) {
        arguments[argument_count++] = standard_option;
        arguments[argument_count++] = is_pdfa ? "-dPDFACompatibilityPolicy=1" : "-dPDFXNoTrimBoxError=false";
        arguments[argument_count++] = is_pdfa ? "-sColorConversionStrategy=RGB" : "-sColorConversionStrategy=CMYK";
        if (is_pdfa && allow_transparency && !validation_only) {
            arguments[argument_count++] = blend_conversion_option;
        }
    }
    if (has_profile_override_directory) arguments[argument_count++] = permit_profile_overrides;
    if (has_compatibility_level) {
        arguments[argument_count++] = compatibility_option;
        if (uses_pre_pdf15_layout) {
            arguments[argument_count++] = "-dWriteXRefStm=false";
            arguments[argument_count++] = "-dWriteObjStms=false";
        }
    }
    arguments[argument_count++] = "-q";
    arguments[argument_count++] = "-dNOPAUSE";
    arguments[argument_count++] = "-sDEVICE=pdfwrite";
    arguments[argument_count++] = "-sstdout=%stderr";
    arguments[argument_count++] = "-sOutputFile=iPS2PDF-output.pdf";

    return_code = gsapi_init_with_args(instance, argument_count, (char **)arguments);
    initialized = 1;
    if (return_code != 0) goto descriptor_finished;

    return_code = descriptor_run_stream(instance, joboptions_fd, &capture);
    if (return_code != 0) goto descriptor_finished;
    if (allow_transparency && !validation_only) {
        const char *transparency_prolog =
            "<< /PageUsesTransparency true /PageSpotColors 0 >> setpagedevice\n"
            "0 .pushpdf14devicefilter\n"
            "/.iPS2PDFOriginalShowpage /showpage load def\n"
            "/showpage { .poppdf14devicefilter .iPS2PDFOriginalShowpage } bind def\n"
            "/.iPS2PDFOriginalPdfmark /pdfmark load def\n"
            "/pdfmark {\n"
            "  dup /SetTransparency eq {\n"
            "    pop counttomark 2 idiv dict begin\n"
            "    counttomark 2 idiv { def } repeat\n"
            "    ca .setfillconstantalpha\n"
            "    CA .setstrokeconstantalpha\n"
            "    BM .setblendmode\n"
            "    end pop\n"
            "  } { .iPS2PDFOriginalPdfmark } ifelse\n"
            "} bind def\n";
        return_code = descriptor_run_bytes(instance, transparency_prolog, &capture);
        if (return_code != 0) goto descriptor_finished;
    }
    if (has_profile_overrides) {
        return_code = descriptor_run_bytes(instance, profile_overrides, &capture);
        if (return_code != 0) goto descriptor_finished;
    }
    if (has_standard) {
        return_code = descriptor_run_stream(instance, standard_definition_fd, &capture);
        if (return_code != 0) goto descriptor_finished;
    }
    current_stage = GS_BRIDGE_STAGE_CONVERSION;
    if (!validation_only) {
        if (descriptor_is_pdf(input_fd)) {
            return_code = descriptor_run_file(instance, kDescriptorInputPDFName, &capture);
        } else {
            return_code = descriptor_run_stream(instance, input_fd, &capture);
        }
        if (return_code == gs_error_Quit) return_code = 0;
    }

descriptor_finished:
    if (initialized) {
        int exit_code = gsapi_exit(instance);
        if (return_code == 0 && exit_code != 0) return_code = exit_code;
    }
    if (file_system_added && instance != NULL) {
        gsapi_remove_fs(instance, &descriptor_file_system, &capture);
    }
    if (instance != NULL) gsapi_delete_instance(instance);
    if (standard_definition_fd >= 0) close(standard_definition_fd);
    if (capture.limit_reason == 1) {
        const char *marker = "[iPS2PDF] time limit exceeded\n";
        descriptor_write(&capture, marker, (int)strlen(marker));
        return_code = -1001;
    } else if (capture.limit_reason == 2) {
        const char *marker = "[iPS2PDF] output size limit exceeded\n";
        descriptor_write(&capture, marker, (int)strlen(marker));
        return_code = -1002;
    } else if (capture.limit_reason == 3) {
        const char *marker = "[iPS2PDF] conversion cancelled\n";
        descriptor_write(&capture, marker, (int)strlen(marker));
        return_code = -1004;
    }
    const char *finished_marker = "[iPS2PDF] Ghostscript finished\n";
    descriptor_write(&capture, finished_marker, (int)strlen(finished_marker));
    fsync(journal_fd);
    if (!validation_only && output_fd >= 0) fsync(output_fd);
    if (ghostscript_return_code != NULL) *ghostscript_return_code = return_code;
    if (stage != NULL) *stage = return_code == 0 ? GS_BRIDGE_STAGE_NONE : current_stage;
    return return_code == 0 ? 0 : -1;
}
