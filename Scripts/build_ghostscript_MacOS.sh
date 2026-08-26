#!/bin/bash
set -euo pipefail

# Build a universal MacOS Ghostscript static library from the unchanged source
# archive. Resource packaging is handled by package_ghostscript_resources.sh.

if [ "$#" -ne 6 ]; then
    echo "Usage: build_ghostscript_MacOS.sh <deployment-target> <sdk-name> <project-temp-dir> <source-archive> <script-patch> <artifact-directory>" >&2
    exit 64
fi

deployment_target="$1"
sdk_name="$2"
project_temp_dir="$3"
source_archive="$4"
script_patch="$5"
artifact_directory="$6"
script_directory="$(cd "$(dirname "$0")" && pwd)"
fingerprint_helpers="$script_directory/Shared/ghostscript_fingerprint.sh"

# shellcheck source=Shared/ghostscript_fingerprint.sh
source "$fingerprint_helpers"

case "$deployment_target" in
    *[!0-9.]* | "")
        echo "Invalid deployment target: $deployment_target" >&2
        exit 65
        ;;
esac

case "$sdk_name" in
    macosx*) ;;
    *)
        echo "Unsupported MacOS SDK: $sdk_name" >&2
        exit 66
        ;;
esac

for required_path in "$source_archive" "$script_patch"; do
    if [ ! -f "$required_path" ]; then
        echo "Required Ghostscript input is missing: $required_path" >&2
        exit 67
    fi
done

if [ -z "$project_temp_dir" ] || [ -z "$artifact_directory" ]; then
    echo "Build and artifact directories must not be empty." >&2
    exit 68
fi

input_fingerprint="$({
    printf 'artifact_schema=ghostscript-compile-v2\n'
    printf 'platform=macosx\n'
    printf 'architectures=arm64 x86_64\n'
    printf 'deployment_target=%s\n' "$deployment_target"
    printf 'sdk_name=%s\n' "$sdk_name"
    ghostscript_hash_file "$source_archive"
    ghostscript_hash_file "$script_patch"
    ghostscript_hash_file "$0"
    ghostscript_hash_file "$fingerprint_helpers"
} | ghostscript_fingerprint)"

compile_stamp="$artifact_directory/compile.stamp"
existing_library="$artifact_directory/lib/libgs.a"
existing_files=(
    "$existing_library"
    "$artifact_directory/include/iapi.h"
    "$artifact_directory/include/gserrors.h"
)
can_reuse=true
for existing_file in "${existing_files[@]}"; do
    if [ ! -s "$existing_file" ]; then
        can_reuse=false
        break
    fi
done
if [ "$can_reuse" = true ] \
    && ghostscript_stamp_contains_fingerprint "$compile_stamp" "$input_fingerprint" \
    && lipo -archs "$existing_library" | grep -qw arm64 \
    && lipo -archs "$existing_library" | grep -qw x86_64; then
    echo "Reusing universal MacOS Ghostscript compile artifacts at $artifact_directory"
    exit 0
fi

artifact_parent="$(dirname "$artifact_directory")"
xcode_temp_root="$project_temp_dir"
case "$project_temp_dir" in
    */Build/Intermediates.noindex/*)
        xcode_temp_root="${project_temp_dir%%/Build/Intermediates.noindex/*}/Build/Intermediates.noindex"
        ;;
esac
scratch_parent="$xcode_temp_root/iPS2PDFGhostscriptBuilds"
mkdir -p "$project_temp_dir" "$artifact_parent" "$scratch_parent"

work_directory="$(mktemp -d "$scratch_parent/GhostscriptMacOSBuild.XXXXXX")"
staged_compile_directory="$(mktemp -d "$artifact_parent/.macos-universal.compile.stage.XXXXXX")"

cleanup() {
    if [ -n "${work_directory:-}" ] && [ -d "$work_directory" ]; then
        rm -rf -- "$work_directory"
    fi
    if [ -n "${staged_compile_directory:-}" ] && [ -d "$staged_compile_directory" ]; then
        rm -rf -- "$staged_compile_directory"
    fi
}
trap cleanup EXIT

extraction_directory="$work_directory/extracted"
mkdir -p "$extraction_directory"
tar -xzf "$source_archive" -C "$extraction_directory"

shopt -s dotglob nullglob
extracted_entries=("$extraction_directory"/*)
shopt -u dotglob nullglob

if [ "${#extracted_entries[@]}" -eq 1 ] && [ -d "${extracted_entries[0]}" ]; then
    upstream_root="${extracted_entries[0]}"
else
    upstream_root="$extraction_directory"
fi

official_script="$upstream_root/toolbin/macos_build_uni_dylib.sh"
working_script="$work_directory/build_macos_gslib.patched.sh"
upstream_artifact="$work_directory/libgs.a"

if [ ! -f "$official_script" ]; then
    echo "Missing official Ghostscript MacOS build script: $official_script" >&2
    exit 69
fi

cp "$official_script" "$working_script"
patch --silent "$working_script" "$script_patch"
chmod +x "$working_script"

# Host-side generators must use the host runtime, not SDK variables inherited
# from an Xcode build phase.
unset DYLD_ROOT_PATH DYLD_LIBRARY_PATH DYLD_FRAMEWORK_PATH DYLD_INSERT_LIBRARIES
unset SDKROOT SDK_NAME SDK_DIR

export IP2PDF_MACOSX_DEPLOYMENT_TARGET="$deployment_target"
export IP2PDF_MACOS_SDK="$sdk_name"
export IP2PDF_MACOS_OUTPUT="$upstream_artifact"

set +e
(
    cd "$upstream_root" && "$working_script"
) 2>&1 | sed -E 's/[Ww]arning:/warn:/g'
build_status=${PIPESTATUS[0]}
set -e

if [ "$build_status" -ne 0 ]; then
    exit "$build_status"
fi

iapi_header="$upstream_root/psi/iapi.h"
gserrors_header="$upstream_root/base/gserrors.h"
for required_file in "$upstream_artifact" "$iapi_header" "$gserrors_header"; do
    if [ ! -s "$required_file" ]; then
        echo "Missing required Ghostscript compile artifact: $required_file" >&2
        exit 70
    fi
done
if ! lipo -archs "$upstream_artifact" | grep -qw arm64 \
    || ! lipo -archs "$upstream_artifact" | grep -qw x86_64; then
    echo "Ghostscript MacOS library does not contain both arm64 and x86_64 slices: $upstream_artifact" >&2
    exit 71
fi

mkdir -p "$staged_compile_directory/lib" "$staged_compile_directory/include"
install -m 0644 "$upstream_artifact" "$staged_compile_directory/lib/libgs.a"
install -m 0644 "$iapi_header" "$staged_compile_directory/include/iapi.h"
install -m 0644 "$gserrors_header" "$staged_compile_directory/include/gserrors.h"

{
    printf 'artifact_schema=ghostscript-compile-v2\n'
    printf 'platform=macosx\n'
    printf 'architectures=arm64 x86_64\n'
    printf 'deployment_target=%s\n' "$deployment_target"
    printf 'sdk_name=%s\n' "$sdk_name"
    printf 'source_archive=%s\n' "$source_archive"
    printf 'input_fingerprint=%s\n' "$input_fingerprint"
} > "$staged_compile_directory/compile.stamp"

mkdir -p "$artifact_directory"
rm -rf -- "$artifact_directory/lib" "$artifact_directory/include"
ditto "$staged_compile_directory/lib" "$artifact_directory/lib"
ditto "$staged_compile_directory/include" "$artifact_directory/include"
install -m 0644 "$staged_compile_directory/compile.stamp" "$compile_stamp"
staged_compile_directory=""

echo "Built universal MacOS Ghostscript compile artifacts at $artifact_directory"
