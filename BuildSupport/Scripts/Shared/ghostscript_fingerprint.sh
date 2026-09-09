#!/bin/bash

# Shared helpers for deterministic Ghostscript build fingerprints.

ghostscript_sha256() {
    shasum -a 256 "$@" | awk '{ print $1; }'
}

ghostscript_hash_file() {
    local path="$1"

    if [ ! -f "$path" ]; then
        echo "Missing fingerprint input file: $path" >&2
        return 1
    fi

    printf 'file\t%s\t%s\n' "$path" "$(ghostscript_sha256 "$path")"
}

ghostscript_hash_optional_file() {
    local path="$1"

    if [ -f "$path" ]; then
        ghostscript_hash_file "$path"
    else
        printf 'missing-file\t%s\n' "$path"
    fi
}

ghostscript_hash_directory() {
    local path="$1"

    if [ ! -d "$path" ]; then
        echo "Missing fingerprint input directory: $path" >&2
        return 1
    fi

    (
        cd "$path"
        find . -type f ! -name '.*' ! -path '*/.*' -print | LC_ALL=C sort | while IFS= read -r relative_path; do
            relative_path="${relative_path#./}"
            printf 'dir-file\t%s/%s\t%s\n' "$path" "$relative_path" "$(ghostscript_sha256 "$relative_path")"
        done
    )
}

ghostscript_hash_optional_directory() {
    local path="$1"

    if [ -d "$path" ]; then
        ghostscript_hash_directory "$path"
    else
        printf 'missing-directory\t%s\n' "$path"
    fi
}

ghostscript_fingerprint() {
    shasum -a 256 | awk '{ print $1; }'
}

ghostscript_stamp_contains_fingerprint() {
    local stamp="$1"
    local fingerprint="$2"

    grep -qx "input_fingerprint=$fingerprint" "$stamp" 2>/dev/null
}
