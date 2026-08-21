#!/bin/bash

set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
joboptions_source="${1:-/Users/admin/Desktop/Distiller Joboptions}"
profiles_source="${2:-/Users/admin/Desktop/Profiles}"
resource_root="$project_dir/BundledResources"
joboptions_destination="$resource_root/Joboptions"
profiles_destination="$resource_root/Profiles"

if [[ ! -d "$joboptions_source" || ! -d "$profiles_source" ]]; then
    echo "The Distiller Joboptions and Profiles source folders are required." >&2
    exit 1
fi

mkdir -p "$joboptions_destination" "$profiles_destination"
find "$joboptions_destination" -maxdepth 1 -type f -name '*.joboptions' -delete
find "$profiles_destination" -maxdepth 1 -type f \( -name '*.icc' -o -name '*.icm' \) -delete

sanitizer_directory="$(mktemp -d "${TMPDIR:-/tmp}/ips2pdf-sanitizer.XXXXXX")"
trap 'rm -rf "$sanitizer_directory"' EXIT
cp "$project_dir/Scripts/sanitize_joboptions.swift" "$sanitizer_directory/main.swift"
xcrun swiftc \
    "$project_dir/Shared/JoboptionsModels.swift" \
    "$project_dir/Shared/LosslessJoboptionsDocument.swift" \
    "$sanitizer_directory/main.swift" \
    -o "$sanitizer_directory/sanitize_joboptions"

while IFS= read -r -d '' source_file; do
    source_name="$(basename "$source_file")"
    if [[ "$source_name" == "Standard.joboptions" ]]; then
        destination_name="Normal.joboptions"
    else
        destination_name="$source_name"
    fi

    # Point edits keep useful comments/formatting while removing application
    # metadata and ensuring both font arrays are genuinely empty.
    "$sanitizer_directory/sanitize_joboptions" \
        "$source_file" \
        "$joboptions_destination/$destination_name"
done < <(find "$joboptions_source" -maxdepth 1 -type f -name '*.joboptions' -print0 | sort -z)

while IFS= read -r -d '' source_file; do
    cp -p "$source_file" "$profiles_destination/$(basename "$source_file")"
done < <(find "$profiles_source" -maxdepth 1 -type f \( -name '*.icc' -o -name '*.icm' \) -print0 | sort -z)

joboptions_count="$(find "$joboptions_destination" -maxdepth 1 -type f -name '*.joboptions' | wc -l | tr -d ' ')"
profile_count="$(find "$profiles_destination" -maxdepth 1 -type f \( -name '*.icc' -o -name '*.icm' \) | wc -l | tr -d ' ')"

if [[ "$joboptions_count" -lt 1 || "$profile_count" -ne 58 ]]; then
    echo "Unexpected resource count: $joboptions_count Joboptions, $profile_count profiles." >&2
    exit 1
fi

echo "Prepared $joboptions_count Joboptions and $profile_count ICC profiles."
