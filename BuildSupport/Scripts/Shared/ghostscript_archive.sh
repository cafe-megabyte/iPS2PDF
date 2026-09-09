#!/bin/bash

# Resolve the Ghostscript source input used by Xcode build phases.

ghostscript_resolve_source_archive() {
    local source_input="$1"

    if [ -f "$source_input" ]; then
        printf '%s\n' "$source_input"
        return 0
    fi

    if [ ! -d "$source_input" ]; then
        echo "Ghostscript source archive input is missing: $source_input" >&2
        return 1
    fi

    local archives=()
    while IFS= read -r -d '' archive; do
        archives+=("$archive")
    done < <(find "$source_input" -maxdepth 1 -type f -name '*.tar.gz' -print0 | sort -z)

    case "${#archives[@]}" in
        1)
            printf '%s\n' "${archives[0]}"
            ;;
        0)
            echo "No Ghostscript source archive matching *.tar.gz found in: $source_input" >&2
            return 1
            ;;
        *)
            echo "Multiple Ghostscript source archives matching *.tar.gz found in: $source_input" >&2
            printf '  %s\n' "${archives[@]}" >&2
            return 1
            ;;
    esac
}
