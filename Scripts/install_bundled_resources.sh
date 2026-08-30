#!/bin/bash

set -euo pipefail

source_root="${1:?Bundled resource root is required}"
destination_root="${2:?Bundle resource destination is required}"
resource_set="${3:-all}"

joboptions_source="$source_root/Joboptions"
profiles_source="$source_root/Profiles"

copy_matching_files() {
    local source_directory="$1"
    local destination_directory="$2"
    shift 2

    rm -rf -- "$destination_directory"
    mkdir -p "$destination_directory"

    while IFS= read -r -d '' file; do
        install -m 0644 "$file" "$destination_directory/$(basename "$file")"
    done < <(find "$source_directory" -maxdepth 1 -type f "$@" -print0 | sort -z)

    xattr -cr "$destination_directory" 2>/dev/null || true
}

case "$resource_set" in
    all|joboptions|profiles) ;;
    *) echo "Resource set must be all, joboptions, or profiles." >&2; exit 1 ;;
esac

# Keep build products aligned with the selected target role.
if [[ "$resource_set" == "joboptions" ]]; then
    rm -rf -- "$destination_root/Profiles"
elif [[ "$resource_set" == "profiles" ]]; then
    rm -rf -- "$destination_root/Joboptions"
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
    copy_matching_files "$joboptions_source" "$destination_root/Joboptions" -name "*.joboptions"
    printf 'installed_resource_set=joboptions\n' > "$destination_root/Joboptions/.install.stamp"
fi

if [[ "$resource_set" == "all" || "$resource_set" == "profiles" ]]; then
    [[ -d "$profiles_source" ]] || {
        echo "Bundled ICC profiles are missing. Run prepare_bundled_resources.sh." >&2
        exit 1
    }
    [[ -s "$profiles_source/Generic CMYK Profile.icc" ]] || {
        echo "Bundled Generic CMYK Profile.icc is missing. Run prepare_bundled_resources.sh." >&2
        exit 1
    }
    copy_matching_files "$profiles_source" "$destination_root/Profiles" \( -name "*.icc" -o -name "*.icm" \)
    printf 'installed_resource_set=profiles\n' > "$destination_root/Profiles/.install.stamp"
fi
