#!/bin/bash
set -euo pipefail

destination_root="${1:?Bundle resource destination is required}"

for directory_name in Joboptions Profiles Ghostscript; do
    directory="$destination_root/$directory_name"
    if [[ -d "$directory" ]]; then
        find "$directory" -depth -delete
    fi
done
