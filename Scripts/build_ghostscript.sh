#!/bin/bash
set -euo pipefail

# This is a patcher, not a patched copy of Ghostscript's iOS script. It makes
# a disposable working copy under upstream/ios/build and applies only the
# deterministic changes required for current, single-architecture SDK builds.

if [ "$#" -ne 3 ]; then
    echo "Usage: build_ghostscript.sh <iphonesimulator|iphoneos> <architecture> <deployment-target>" >&2
    exit 64
fi

platform="$1"
architecture="$2"
deployment_target="$3"

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

project_root="$(cd "$(dirname "$0")/.." && pwd)"
vendor_root="$project_root/Vendor/Ghostscript"
upstream_root="$vendor_root/upstream"
official_script="$upstream_root/ios/build_ios_gslib.sh"

if [ -e "$upstream_root" ] && [ ! -d "$upstream_root" ]; then
    echo "error: $upstream_root exists but is not a directory." >&2
    exit 69
fi

needs_extraction=0
if [ ! -d "$upstream_root" ]; then
    needs_extraction=1
elif [ ! -f "$official_script" ]; then
    # Xcode may pre-create the declared libgs.a output path before this build
    # phase runs. Remove that directory-only scaffold, but never replace an
    # upstream directory that already contains files or symbolic links.
    unexpected_entry="$(find "$upstream_root" -mindepth 1 ! -type d -print -quit)"
    if [ -n "$unexpected_entry" ]; then
        echo "error: $upstream_root is incomplete and contains existing data: $unexpected_entry" >&2
        exit 72
    fi
    find "$upstream_root" -depth -type d -exec rmdir {} \;
    needs_extraction=1
fi

if [ "$needs_extraction" -eq 1 ]; then
    shopt -s nullglob
    source_archives=("$vendor_root"/*.tar.gz)
    shopt -u nullglob

    if [ "${#source_archives[@]}" -ne 1 ]; then
        echo "error: Expected exactly one *.tar.gz in $vendor_root, found ${#source_archives[@]}." >&2
        exit 70
    fi

    extraction_root="$(mktemp -d "$vendor_root/.upstream-extract.XXXXXX")"
    cleanup_extraction() {
        if [ -n "${extraction_root:-}" ] && [ -d "$extraction_root" ]; then
            rm -rf -- "$extraction_root"
        fi
    }
    trap cleanup_extraction EXIT

    if ! tar -xzf "${source_archives[0]}" -C "$extraction_root"; then
        echo "error: Could not extract ${source_archives[0]}." >&2
        exit 71
    fi

    shopt -s dotglob nullglob
    extracted_entries=("$extraction_root"/*)
    shopt -u dotglob nullglob

    if [ "${#extracted_entries[@]}" -eq 1 ] && [ -d "${extracted_entries[0]}" ]; then
        mv "${extracted_entries[0]}" "$upstream_root"
        rmdir "$extraction_root"
    else
        mv "$extraction_root" "$upstream_root"
    fi

    extraction_root=""
    trap - EXIT
    echo "Extracted ${source_archives[0]} as $upstream_root"
fi

build_root="$upstream_root/ios/build"
artifact_directory="$build_root/$platform"
artifact="$artifact_directory/libgs.a"
working_script="$build_root/build_ios_gslib.$platform.patched.sh"

# Xcode exports simulator DYLD variables to build phases. Ghostscript's build
# also runs host-side generator binaries, so they must not inherit that
# simulator runtime environment.
unset DYLD_ROOT_PATH DYLD_LIBRARY_PATH DYLD_FRAMEWORK_PATH DYLD_INSERT_LIBRARIES
unset SDKROOT SDK_NAME SDK_DIR IPHONEOS_DEPLOYMENT_TARGET

if [ -f "$artifact" ]; then
    exit 0
fi

if [ ! -f "$official_script" ]; then
    echo "error: Missing official Ghostscript iOS script: $official_script" >&2
    exit 67
fi

mkdir -p "$artifact_directory"

# The known 10.07.1 script has the historical x86/i386 and armv7 universal
# library setup. Unknown versions still receive this best-effort patch, as
# required by the design description.
if ! grep -q 'BUILDDIRPREFIX=ios_x86-' "$official_script"; then
    echo "warning: Unknown Ghostscript iOS script version; applying compatibility patch anyway." >&2
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
    -e "s#^mv Makefile Makefile.x86\$#mkdir -p \"$artifact_directory\"; cp \"./ios_${platform}-bin/libgs_${platform}.a\" \"$artifact\"; exit 0#" \
    "$working_script"

chmod +x "$working_script"
(cd "$upstream_root/ios" && "$working_script")

if [ ! -s "$artifact" ]; then
    echo "error: Ghostscript did not create $artifact" >&2
    exit 68
fi
