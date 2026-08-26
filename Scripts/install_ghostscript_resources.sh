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

rm -rf "$destination_directory"
mkdir -p "$destination_directory"
install -m 0644 "$source_directory/PDFA_def.ps" "$destination_directory/PDFA_def.ps"
install -m 0644 "$source_directory/PDFX_def.ps" "$destination_directory/PDFX_def.ps"
install -m 0644 "$source_directory/srgb.icc" "$destination_directory/srgb.icc"
ditto "$source_directory/Resource" "$destination_directory/Resource"
xattr -cr "$destination_directory" 2>/dev/null || true
