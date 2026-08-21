#!/bin/sh

set -eu

output_path=${1:?"missing output path"}
output_directory=$(dirname "$output_path")
temporary_path="${output_path}.tmp.$$"

mkdir -p "$output_directory"
trap 'rm -f "$temporary_path"' EXIT HUP INT TERM

printf '#define BUILD_NUMBER_VALUE %s\n' "$(date '+%Y%m%d.%H%M%S')" > "$temporary_path"
mv -f "$temporary_path" "$output_path"

trap - EXIT HUP INT TERM
