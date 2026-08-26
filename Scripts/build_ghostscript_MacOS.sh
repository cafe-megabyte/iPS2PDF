#!/bin/bash
set -euo pipefail

# Build a universal MacOS Ghostscript static library from the unchanged source
# archive. The upstream MacOS script is copied into Derived Data and patched
# there; neither the archive nor an unpacked source tree is changed in place.

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
project_root="$(cd "$script_directory/.." && pwd)"
local_base14_directory="$project_root/BundledResources/PostScriptBase14"

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
    printf 'deployment_target=%s\n' "$deployment_target"
    printf 'sdk_name=%s\n' "$sdk_name"
    shasum -a 256 "$source_archive" "$script_patch" "$0" | awk '{ print $1; }'
} | shasum -a 256 | awk '{ print $1; }')"

existing_stamp="$artifact_directory/build.stamp"
existing_library="$artifact_directory/lib/libgs.a"
existing_files=(
    "$existing_library"
    "$artifact_directory/include/iapi.h"
    "$artifact_directory/include/gserrors.h"
    "$artifact_directory/resources/PDFA_def.ps"
    "$artifact_directory/resources/PDFX_def.ps"
    "$artifact_directory/resources/srgb.icc"
    "$artifact_directory/resources/Resource/Init/gs_init.ps"
    "$artifact_directory/resources/Resource/Font/NimbusMonoPS-Regular"
)
can_reuse=true
for existing_file in "${existing_files[@]}"; do
    if [ ! -s "$existing_file" ]; then
        can_reuse=false
        break
    fi
done
if [ "$can_reuse" = true ] \
    && grep -qx "input_fingerprint=$input_fingerprint" "$existing_stamp" 2>/dev/null \
    && lipo -archs "$existing_library" | grep -qw arm64 \
    && lipo -archs "$existing_library" | grep -qw x86_64; then
    echo "Reusing universal MacOS Ghostscript artifacts at $artifact_directory"
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
staged_artifact_directory="$(mktemp -d "$artifact_parent/.macos-universal.stage.XXXXXX")"

cleanup() {
    if [ -n "${work_directory:-}" ] && [ -d "$work_directory" ]; then
        rm -rf -- "$work_directory"
    fi
    if [ -n "${staged_artifact_directory:-}" ] && [ -d "$staged_artifact_directory" ]; then
        rm -rf -- "$staged_artifact_directory"
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

if [ ! -s "$upstream_artifact" ]; then
    echo "Ghostscript did not create $upstream_artifact" >&2
    exit 70
fi

pdfa_definition="$upstream_root/lib/PDFA_def.ps"
pdfx_definition="$upstream_root/lib/PDFX_def.ps"
srgb_profile="$upstream_root/iccprofiles/srgb.icc"
ghostscript_resource_directory="$upstream_root/Resource"
iapi_header="$upstream_root/psi/iapi.h"
gserrors_header="$upstream_root/base/gserrors.h"

for required_file in "$pdfa_definition" "$pdfx_definition" "$srgb_profile" "$iapi_header" "$gserrors_header"; do
    if [ ! -f "$required_file" ]; then
        echo "Missing required Ghostscript artifact: $required_file" >&2
        exit 71
    fi
done
if [ ! -d "$ghostscript_resource_directory/Init" ] || [ ! -d "$ghostscript_resource_directory/Font" ]; then
    echo "Missing required Ghostscript Resource tree: $ghostscript_resource_directory" >&2
    exit 71
fi

mkdir -p \
    "$staged_artifact_directory/lib" \
    "$staged_artifact_directory/include" \
    "$staged_artifact_directory/resources"

install -m 0644 "$upstream_artifact" "$staged_artifact_directory/lib/libgs.a"
install -m 0644 "$iapi_header" "$staged_artifact_directory/include/iapi.h"
install -m 0644 "$gserrors_header" "$staged_artifact_directory/include/gserrors.h"
install -m 0644 "$pdfa_definition" "$staged_artifact_directory/resources/PDFA_def.ps"
sed 's/ISO Coated sb\.icc/CoatedFOGRA39.icc/g' \
    "$pdfx_definition" > "$staged_artifact_directory/resources/PDFX_def.ps"
install -m 0644 "$srgb_profile" "$staged_artifact_directory/resources/srgb.icc"
ditto "$ghostscript_resource_directory" "$staged_artifact_directory/resources/Resource"

base14_fonts=(
    Couri CouriBol CouriObl CouriBolObl
    Helve HelveBol HelveObl HelveBolObl
    TimesRom TimesBol TimesIta TimesBolIta
    Symbo ZapfDin
)
usable_base14_count=0
missing_base14_fonts=()
for font in "${base14_fonts[@]}"; do
    if [ -s "$local_base14_directory/$font.pfb" ]; then
        usable_base14_count=$((usable_base14_count + 1))
    else
        missing_base14_fonts+=("$font.pfb")
    fi
done
if [ "$usable_base14_count" -eq "${#base14_fonts[@]}" ]; then
    for font in "${base14_fonts[@]}"; do
        install -m 0644 "$local_base14_directory/$font.pfb" "$staged_artifact_directory/resources/Resource/Font/$font.pfb"
    done
    cat > "$staged_artifact_directory/resources/Resource/Init/Fontmap.iPS2PDF" <<'EOF'
/Courier (Couri.pfb) ;
/Courier-Bold (CouriBol.pfb) ;
/Courier-Oblique (CouriObl.pfb) ;
/Courier-BoldOblique (CouriBolObl.pfb) ;
/Helvetica (Helve.pfb) ;
/Helvetica-Bold (HelveBol.pfb) ;
/Helvetica-Oblique (HelveObl.pfb) ;
/Helvetica-BoldOblique (HelveBolObl.pfb) ;
/Times-Roman (TimesRom.pfb) ;
/Times-Bold (TimesBol.pfb) ;
/Times-Italic (TimesIta.pfb) ;
/Times-BoldItalic (TimesBolIta.pfb) ;
/Symbol (Symbo.pfb) ;
/ZapfDingbats (ZapfDin.pfb) ;
EOF
    cat > "$staged_artifact_directory/resources/Resource/Init/Fontmap" <<'EOF'
(Fontmap.GS) .runlibfile
(Fontmap.iPS2PDF) .runlibfile
EOF
else
    echo "Found $usable_base14_count of ${#base14_fonts[@]} usable local Base 14 fonts; using Ghostscript bundled fonts." >&2
    if [ "${#missing_base14_fonts[@]}" -gt 0 ]; then
        echo "Missing or empty local Base 14 fonts: ${missing_base14_fonts[*]}" >&2
    fi
fi
xattr -cr "$staged_artifact_directory/resources" 2>/dev/null || true

{
    printf 'platform=macosx\n'
    printf 'architectures=arm64 x86_64\n'
    printf 'deployment_target=%s\n' "$deployment_target"
    printf 'sdk_name=%s\n' "$sdk_name"
    printf 'input_fingerprint=%s\n' "$input_fingerprint"
    shasum -a 256 "$source_archive" "$script_patch" "$0"
} > "$staged_artifact_directory/build.stamp"

if [ -e "$artifact_directory" ]; then
    rm -rf -- "$artifact_directory"
fi
mv "$staged_artifact_directory" "$artifact_directory"
staged_artifact_directory=""

echo "Built universal MacOS Ghostscript artifacts at $artifact_directory"
