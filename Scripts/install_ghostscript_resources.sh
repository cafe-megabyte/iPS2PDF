#!/bin/bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "Usage: install_ghostscript_resources.sh <artifact-directory> <bundle-resource-directory>" >&2
    exit 64
fi

artifact_directory="$1"
bundle_resource_directory="$2"
source_directory="$artifact_directory/resources"
destination_directory="$bundle_resource_directory/Ghostscript"
resources_stamp="$artifact_directory/resources.stamp"

if [ ! -s "$resources_stamp" ]; then
    script_directory="$(cd "$(dirname "$0")" && pwd)"
    project_root="${SRCROOT:-$(cd "$script_directory/.." && pwd)}"
    project_temp_dir="${PROJECT_TEMP_DIR:-}"
    source_archive="${GHOSTSCRIPT_ARCHIVE_PATH:-}"
    base14_directory="$project_root/BundledResources/PostScriptBase14"
    package_script="$script_directory/package_ghostscript_resources.sh"

    if [ -n "$project_temp_dir" ] && [ -n "$source_archive" ] && [ -x "$package_script" ]; then
        "$package_script" "$project_temp_dir" "$source_archive" "$base14_directory" "$artifact_directory"
    fi
fi

for resource in PDFA_def.ps PDFX_def.ps srgb.icc; do
    if [ ! -f "$source_directory/$resource" ]; then
        echo "Missing Ghostscript resource: $source_directory/$resource" >&2
        exit 65
    fi
done
if [ ! -f "$source_directory/Resource/Init/gs_init.ps" ] || [ ! -d "$source_directory/Resource/Font" ]; then
    echo "Missing Ghostscript Resource tree: $source_directory/Resource" >&2
    exit 65
fi
if [ ! -s "$resources_stamp" ]; then
    echo "Missing Ghostscript resource stamp: $resources_stamp" >&2
    exit 65
fi

rm -rf "$destination_directory"
mkdir -p "$destination_directory"
install -m 0644 "$source_directory/PDFA_def.ps" "$destination_directory/PDFA_def.ps"
install -m 0644 "$source_directory/PDFX_def.ps" "$destination_directory/PDFX_def.ps"
install -m 0644 "$source_directory/srgb.icc" "$destination_directory/srgb.icc"
ditto "$source_directory/Resource" "$destination_directory/Resource"
install -m 0644 "$resources_stamp" "$destination_directory/.install.stamp"
xattr -cr "$destination_directory" 2>/dev/null || true
