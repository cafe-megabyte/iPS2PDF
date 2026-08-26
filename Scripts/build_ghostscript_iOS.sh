#!/bin/bash
set -euo pipefail

# Build one iOS Ghostscript static-library variant into a shared artifact
# directory. Resource packaging is handled by package_ghostscript_resources.sh.

if [ "$#" -ne 6 ]; then
    echo "Usage: build_ghostscript_iOS.sh <iphonesimulator|iphoneos> <architecture> <deployment-target> <sdk-name> <project-temp-dir> <source-archive>" >&2
    exit 64
fi

platform="$1"
architecture="$2"
deployment_target="$3"
sdk_name="$4"
project_temp_dir="$5"
source_archive="$6"
script_directory="$(cd "$(dirname "$0")" && pwd)"
fingerprint_helpers="$script_directory/Shared/ghostscript_fingerprint.sh"

# shellcheck source=Shared/ghostscript_fingerprint.sh
source "$fingerprint_helpers"

case "$platform" in
    iphonesimulator)
        minimum_version_flag="-mios-simulator-version-min=$deployment_target"
        ;;
    iphoneos)
        minimum_version_flag="-miphoneos-version-min=$deployment_target"
        ;;
    *)
        echo "Unsupported Apple platform: $platform" >&2
        exit 65
        ;;
esac

case "$architecture" in
    arm64) ;;
    *)
        echo "Unsupported architecture: $architecture" >&2
        exit 66
        ;;
esac

case "$sdk_name" in
    *[!A-Za-z0-9._-]* | "")
        echo "Invalid SDK name: $sdk_name" >&2
        exit 67
        ;;
esac

case "$deployment_target" in
    *[!0-9.]* | "")
        echo "Invalid deployment target: $deployment_target" >&2
        exit 68
        ;;
esac

if [ -z "$project_temp_dir" ]; then
    echo "Project temporary directory must not be empty." >&2
    exit 69
fi

if [ ! -f "$source_archive" ]; then
    echo "Ghostscript source archive is missing: $source_archive" >&2
    exit 70
fi

artifact_key="$sdk_name-$architecture-ios$deployment_target"
artifact_parent="$project_temp_dir/GhostscriptArtifacts"
artifact_directory="$artifact_parent/$artifact_key"
compile_stamp="$artifact_directory/compile.stamp"
existing_library="$artifact_directory/lib/libgs.a"
existing_files=(
    "$existing_library"
    "$artifact_directory/include/iapi.h"
    "$artifact_directory/include/gserrors.h"
)

input_fingerprint="$({
    printf 'artifact_schema=ghostscript-compile-v2\n'
    printf 'platform=%s\n' "$platform"
    printf 'architecture=%s\n' "$architecture"
    printf 'deployment_target=%s\n' "$deployment_target"
    printf 'sdk_name=%s\n' "$sdk_name"
    ghostscript_hash_file "$source_archive"
    ghostscript_hash_file "$0"
    ghostscript_hash_file "$fingerprint_helpers"
} | ghostscript_fingerprint)"

can_reuse=true
for existing_file in "${existing_files[@]}"; do
    if [ ! -s "$existing_file" ]; then
        can_reuse=false
        break
    fi
done
if [ "$can_reuse" = true ] && ghostscript_stamp_contains_fingerprint "$compile_stamp" "$input_fingerprint"; then
    echo "Reusing iOS Ghostscript compile artifacts at $artifact_directory"
    exit 0
fi

xcode_temp_root="$project_temp_dir"
case "$project_temp_dir" in
    */Build/Intermediates.noindex/*)
        xcode_temp_root="${project_temp_dir%%/Build/Intermediates.noindex/*}/Build/Intermediates.noindex"
        ;;
esac
scratch_parent="$xcode_temp_root/iPS2PDFGhostscriptBuilds"

mkdir -p "$artifact_parent" "$scratch_parent"
work_directory="$(mktemp -d "$scratch_parent/GhostscriptBuild.$artifact_key.XXXXXX")"
staged_compile_directory="$(mktemp -d "$artifact_parent/.$artifact_key.compile.stage.XXXXXX")"

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

if ! tar -xzf "$source_archive" -C "$extraction_directory"; then
    echo "Could not extract $source_archive." >&2
    exit 71
fi

shopt -s dotglob nullglob
extracted_entries=("$extraction_directory"/*)
shopt -u dotglob nullglob

if [ "${#extracted_entries[@]}" -eq 1 ] && [ -d "${extracted_entries[0]}" ]; then
    upstream_root="${extracted_entries[0]}"
else
    upstream_root="$extraction_directory"
fi

official_script="$upstream_root/ios/build_ios_gslib.sh"
if [ ! -f "$official_script" ]; then
    echo "Missing official Ghostscript iOS script: $official_script" >&2
    exit 72
fi

build_root="$upstream_root/ios/build"
upstream_artifact_directory="$build_root/$platform"
upstream_artifact="$upstream_artifact_directory/libgs.a"
working_script="$build_root/build_ios_gslib.$platform.patched.sh"

# Xcode exports simulator DYLD variables to build phases. Ghostscript's build
# also runs host-side generator binaries, so they must not inherit that
# simulator runtime environment.
unset DYLD_ROOT_PATH DYLD_LIBRARY_PATH DYLD_FRAMEWORK_PATH DYLD_INSERT_LIBRARIES
unset SDKROOT SDK_NAME SDK_DIR IPHONEOS_DEPLOYMENT_TARGET

mkdir -p "$upstream_artifact_directory"

if ! grep -q 'BUILDDIRPREFIX=ios_x86-' "$official_script"; then
    echo "notice: Unknown Ghostscript iOS script version; applying compatibility patch anyway." >&2
fi

cp "$official_script" "$working_script"
sed -i '' '2i\
set -o pipefail
' "$working_script"

sed -i '' \
    -e "s/iphonesimulator/$platform/g" \
    -e "s/-arch x86_64 -arch i386/-arch $architecture $minimum_version_flag/g" \
    -e "s#./ios/ios_arch-x86.h#./ios/ios_arch-arm.h#g" \
    -e "s/--host=x86_64-apple-darwin7/--host=$architecture-apple-darwin/g" \
    -e "s/BUILDDIRPREFIX=ios_x86-/BUILDDIRPREFIX=ios_$platform-/g" \
    -e "s/libgs_x86/libgs_$platform/g" \
    -e "s/conflog_x86/conflog_$platform/g" \
    -e "s/buildlog_x86/buildlog_$platform/g" \
    -e "s#^mv Makefile Makefile.x86\$#mkdir -p \"$upstream_artifact_directory\"; cp \"./ios_${platform}-bin/libgs_${platform}.a\" \"$upstream_artifact\"; exit 0#" \
    "$working_script"

chmod +x "$working_script"

set +e
(
    cd "$upstream_root/ios" && "$working_script"
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
        exit 73
    fi
done

mkdir -p "$staged_compile_directory/lib" "$staged_compile_directory/include"
install -m 0644 "$upstream_artifact" "$staged_compile_directory/lib/libgs.a"
install -m 0644 "$iapi_header" "$staged_compile_directory/include/iapi.h"
install -m 0644 "$gserrors_header" "$staged_compile_directory/include/gserrors.h"

{
    printf 'artifact_schema=ghostscript-compile-v2\n'
    printf 'platform=%s\n' "$platform"
    printf 'architecture=%s\n' "$architecture"
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

echo "Built iOS Ghostscript compile artifacts at $artifact_directory"
