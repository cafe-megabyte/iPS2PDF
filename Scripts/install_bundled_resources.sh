#!/bin/bash

set -euo pipefail

source_root="${1:?Bundled resource root is required}"
destination_root="${2:?Bundle resource destination is required}"
resource_set="${3:-all}"

joboptions_source="$source_root/Joboptions"
profiles_source="$source_root/Profiles"

case "$resource_set" in
    all|joboptions|profiles) ;;
    *) echo "Resource set must be all, joboptions, or profiles." >&2; exit 1 ;;
esac

# Keep incremental build products aligned with the selected target role.
if [[ "$resource_set" == "joboptions" && -d "$destination_root/Profiles" ]]; then
    find "$destination_root/Profiles" -maxdepth 1 -type f -delete
    rmdir "$destination_root/Profiles" 2>/dev/null || true
elif [[ "$resource_set" == "profiles" && -d "$destination_root/Joboptions" ]]; then
    find "$destination_root/Joboptions" -maxdepth 1 -type f -delete
    rmdir "$destination_root/Joboptions" 2>/dev/null || true
fi

if [[ "$resource_set" == "all" || "$resource_set" == "joboptions" ]]; then
    [[ -d "$joboptions_source" ]] || {
        echo "Bundled Joboptions are missing. Run prepare_bundled_resources.sh." >&2
        exit 1
    }
    [[ -s "$joboptions_source/Normal.joboptions" ]] || {
        echo "Bundled Normal.joboptions is missing. Run prepare_bundled_resources.sh." >&2
        exit 1
    }
    mkdir -p "$destination_root/Joboptions"
    find "$destination_root/Joboptions" -maxdepth 1 -type f -delete
    ditto "$joboptions_source" "$destination_root/Joboptions"
fi

if [[ "$resource_set" == "all" || "$resource_set" == "profiles" ]]; then
    [[ -d "$profiles_source" ]] || {
        echo "Bundled ICC profiles are missing. Run prepare_bundled_resources.sh." >&2
        exit 1
    }
    mkdir -p "$destination_root/Profiles"
    find "$destination_root/Profiles" -maxdepth 1 -type f -delete
    ditto "$profiles_source" "$destination_root/Profiles"
fi
