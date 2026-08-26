#!/bin/bash
set -euo pipefail

# Build one Ghostscript variant into a shared, immutable artifact directory.
# Xcode's dependency analysis decides whether this script needs to run. When it
# does run, the build happens in disposable directories and the completed
# artifact set is published only after every required file is available.

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
project_root="$(cd "$script_directory/.." && pwd)"
local_base14_directory="$project_root/BundledResources/PostScriptBase14"

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
xcode_temp_root="$project_temp_dir"
case "$project_temp_dir" in
    */Build/Intermediates.noindex/*)
        xcode_temp_root="${project_temp_dir%%/Build/Intermediates.noindex/*}/Build/Intermediates.noindex"
        ;;
esac
scratch_parent="$xcode_temp_root/iPS2PDFGhostscriptBuilds"

mkdir -p "$artifact_parent" "$scratch_parent"
work_directory="$(mktemp -d "$scratch_parent/GhostscriptBuild.$artifact_key.XXXXXX")"
staged_artifact_directory="$(mktemp -d "$artifact_parent/.$artifact_key.stage.XXXXXX")"

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

# The known 10.07.1 script has the historical x86/i386 and armv7 universal
# library setup. Unknown versions still receive this best-effort patch.
if ! grep -q 'BUILDDIRPREFIX=ios_x86-' "$official_script"; then
    echo "notice: Unknown Ghostscript iOS script version; applying compatibility patch anyway." >&2
fi

cp "$official_script" "$working_script"

# The upstream script pipes configure/make output through tee. Make failures
# must remain failures in the working copy when the shell's pipefail behavior
# is otherwise unavailable.
sed -i '' '2i\
set -o pipefail
' "$working_script"

# Keep the official script's configure + make build logic. The patcher adapts
# its first build leg to the active SDK and ends after that leg, before the
# now-obsolete second architecture/lipo section.
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

# Xcode treats "warning:" in Run Script output as project warnings.
# Keep upstream diagnostics visible without letting vendored Ghostscript warnings pollute the issue navigator.
set +e
(
    cd "$upstream_root/ios" && "$working_script"
) 2>&1 | sed -E 's/[Ww]arning:/warn:/g'
build_status=${PIPESTATUS[0]}
set -e

if [ "$build_status" -ne 0 ]; then
    exit "$build_status"
fi

if [ ! -s "$upstream_artifact" ]; then
    echo "Ghostscript did not create $upstream_artifact" >&2
    exit 73
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
        exit 74
    fi
done
if [ ! -d "$ghostscript_resource_directory/Init" ] || [ ! -d "$ghostscript_resource_directory/Font" ]; then
    echo "Missing required Ghostscript Resource tree: $ghostscript_resource_directory" >&2
    exit 74
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
    if [ -s "$local_base14_directory/$font" ]; then
        usable_base14_count=$((usable_base14_count + 1))
    else
        missing_base14_fonts+=("$font")
    fi
done
if [ "$usable_base14_count" -eq "${#base14_fonts[@]}" ]; then
    for font in "${base14_fonts[@]}"; do
        install -m 0644 "$local_base14_directory/$font" "$staged_artifact_directory/resources/Resource/Font/$font"
    done
    cat > "$staged_artifact_directory/resources/Resource/Init/Fontmap.iPS2PDF" <<'EOF'
/Courier (Couri) ;
/Courier-Bold (CouriBol) ;
/Courier-Oblique (CouriObl) ;
/Courier-BoldOblique (CouriBolObl) ;
/Helvetica (Helve) ;
/Helvetica-Bold (HelveBol) ;
/Helvetica-Oblique (HelveObl) ;
/Helvetica-BoldOblique (HelveBolObl) ;
/Times-Roman (TimesRom) ;
/Times-Bold (TimesBol) ;
/Times-Italic (TimesIta) ;
/Times-BoldItalic (TimesBolIta) ;
/Symbol (Symbo) ;
/ZapfDingbats (ZapfDin) ;
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
    printf 'platform=%s\n' "$platform"
    printf 'architecture=%s\n' "$architecture"
    printf 'deployment_target=%s\n' "$deployment_target"
    printf 'sdk_name=%s\n' "$sdk_name"
    shasum -a 256 "$source_archive" "$0"
} > "$staged_artifact_directory/build.stamp"

if [ -e "$artifact_directory" ]; then
    rm -rf -- "$artifact_directory"
fi
mv "$staged_artifact_directory" "$artifact_directory"
staged_artifact_directory=""

echo "Built Ghostscript artifacts at $artifact_directory"
