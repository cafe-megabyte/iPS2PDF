#!/bin/bash
set -euo pipefail

if [ "$#" -ne 4 ]; then
    echo "Usage: package_ghostscript_resources.sh <project-temp-dir> <source-archive> <base14-directory> <artifact-directory>" >&2
    exit 64
fi

project_temp_dir="$1"
source_archive="$2"
base14_directory="$3"
artifact_directory="$4"
script_directory="$(cd "$(dirname "$0")" && pwd)"
fingerprint_helpers="$script_directory/Shared/ghostscript_fingerprint.sh"

# shellcheck source=Shared/ghostscript_fingerprint.sh
source "$fingerprint_helpers"

if [ -z "$project_temp_dir" ] || [ -z "$artifact_directory" ]; then
    echo "Build and artifact directories must not be empty." >&2
    exit 65
fi

if [ ! -f "$source_archive" ]; then
    echo "Ghostscript source archive is missing: $source_archive" >&2
    exit 66
fi

base14_fonts=(
    Couri CouriBol CouriObl CouriBolObl
    Helve HelveBol HelveObl HelveBolObl
    TimesRom TimesBol TimesIta TimesBolIta
    Symbo ZapfDin
)

input_fingerprint="$({
    printf 'artifact_schema=ghostscript-resources-v1\n'
    printf 'pdfx_profile_rewrite=ISO Coated sb.icc->CoatedFOGRA39.icc\n'
    ghostscript_hash_file "$source_archive"
    ghostscript_hash_file "$0"
    ghostscript_hash_file "$fingerprint_helpers"
    ghostscript_hash_optional_directory "$base14_directory"
} | ghostscript_fingerprint)"

resources_directory="$artifact_directory/resources"
resources_stamp="$artifact_directory/resources.stamp"
existing_files=(
    "$resources_directory/PDFA_def.ps"
    "$resources_directory/PDFX_def.ps"
    "$resources_directory/srgb.icc"
    "$resources_directory/Resource/Init/gs_init.ps"
    "$resources_directory/Resource/Font/NimbusMonoPS-Regular"
)

can_reuse=true
for existing_file in "${existing_files[@]}"; do
    if [ ! -s "$existing_file" ]; then
        can_reuse=false
        break
    fi
done
if [ "$can_reuse" = true ] && ghostscript_stamp_contains_fingerprint "$resources_stamp" "$input_fingerprint"; then
    echo "Reusing Ghostscript resources at $resources_directory"
    exit 0
fi

artifact_parent="$(dirname "$artifact_directory")"
xcode_temp_root="$project_temp_dir"
case "$project_temp_dir" in
    */Build/Intermediates.noindex/*)
        xcode_temp_root="${project_temp_dir%%/Build/Intermediates.noindex/*}/Build/Intermediates.noindex"
        ;;
esac
scratch_parent="$xcode_temp_root/iPS2PDFGhostscriptBuilds"

mkdir -p "$artifact_parent" "$scratch_parent"
work_directory="$(mktemp -d "$scratch_parent/GhostscriptResources.XXXXXX")"
staged_resources_directory="$(mktemp -d "$artifact_parent/.resources.stage.XXXXXX")"

cleanup() {
    if [ -n "${work_directory:-}" ] && [ -d "$work_directory" ]; then
        rm -rf -- "$work_directory"
    fi
    if [ -n "${staged_resources_directory:-}" ] && [ -d "$staged_resources_directory" ]; then
        rm -rf -- "$staged_resources_directory"
    fi
}
trap cleanup EXIT

extraction_directory="$work_directory/extracted"
mkdir -p "$extraction_directory"

if ! tar -xzf "$source_archive" -C "$extraction_directory"; then
    echo "Could not extract $source_archive." >&2
    exit 67
fi

shopt -s dotglob nullglob
extracted_entries=("$extraction_directory"/*)
shopt -u dotglob nullglob

if [ "${#extracted_entries[@]}" -eq 1 ] && [ -d "${extracted_entries[0]}" ]; then
    upstream_root="${extracted_entries[0]}"
else
    upstream_root="$extraction_directory"
fi

pdfa_definition="$upstream_root/lib/PDFA_def.ps"
pdfx_definition="$upstream_root/lib/PDFX_def.ps"
srgb_profile="$upstream_root/iccprofiles/srgb.icc"
ghostscript_resource_directory="$upstream_root/Resource"

for required_file in "$pdfa_definition" "$pdfx_definition" "$srgb_profile"; do
    if [ ! -f "$required_file" ]; then
        echo "Missing required Ghostscript resource input: $required_file" >&2
        exit 68
    fi
done
if [ ! -d "$ghostscript_resource_directory/Init" ] || [ ! -d "$ghostscript_resource_directory/Font" ]; then
    echo "Missing required Ghostscript Resource tree: $ghostscript_resource_directory" >&2
    exit 68
fi

mkdir -p "$staged_resources_directory/resources"
install -m 0644 "$pdfa_definition" "$staged_resources_directory/resources/PDFA_def.ps"
sed 's/ISO Coated sb\.icc/CoatedFOGRA39.icc/g' \
    "$pdfx_definition" > "$staged_resources_directory/resources/PDFX_def.ps"
install -m 0644 "$srgb_profile" "$staged_resources_directory/resources/srgb.icc"
ditto "$ghostscript_resource_directory" "$staged_resources_directory/resources/Resource"

usable_base14_count=0
missing_base14_fonts=()
for font in "${base14_fonts[@]}"; do
    if [ -s "$base14_directory/$font.pfb" ]; then
        usable_base14_count=$((usable_base14_count + 1))
    else
        missing_base14_fonts+=("$font.pfb")
    fi
done
if [ "$usable_base14_count" -eq "${#base14_fonts[@]}" ]; then
    for font in "${base14_fonts[@]}"; do
        install -m 0644 "$base14_directory/$font.pfb" "$staged_resources_directory/resources/Resource/Font/$font.pfb"
    done
    cat > "$staged_resources_directory/resources/Resource/Init/Fontmap.iPS2PDF" <<'EOF'
/Courier (Couri.pfb) ;
/Courier-Bold (CouriBol.pfb) ;
/Courier-Oblique (CouriObl.pfb) ;
/Courier-BoldOblique (CouriBolObl.pfb) ;
/Helvetica (Helve.pfb) ;
/Helvetica-Bold (HelveBol.pfb) ;
/Helvetica-Oblique (HelveObl.pfb) ;
/Helvetica-BoldOblique (HelveBolObl.pfb) ;
/Times-Roman (TimesRom.pfb) ;
/Times-Bold (TimesBol.pfb) ;
/Times-Italic (TimesIta.pfb) ;
/Times-BoldItalic (TimesBolIta.pfb) ;
/Symbol (Symbo.pfb) ;
/ZapfDingbats (ZapfDin.pfb) ;
EOF
    cat > "$staged_resources_directory/resources/Resource/Init/Fontmap" <<'EOF'
(Fontmap.GS) .runlibfile
(Fontmap.iPS2PDF) .runlibfile
EOF
else
    echo "Found $usable_base14_count of ${#base14_fonts[@]} usable local Base 14 fonts; using Ghostscript bundled fonts." >&2
    if [ "${#missing_base14_fonts[@]}" -gt 0 ]; then
        echo "Missing or empty local Base 14 fonts: ${missing_base14_fonts[*]}" >&2
    fi
fi

xattr -cr "$staged_resources_directory/resources" 2>/dev/null || true

{
    printf 'artifact_schema=ghostscript-resources-v1\n'
    printf 'source_archive=%s\n' "$source_archive"
    printf 'base14_directory=%s\n' "$base14_directory"
    printf 'input_fingerprint=%s\n' "$input_fingerprint"
} > "$staged_resources_directory/resources.stamp"

mkdir -p "$artifact_directory"
rm -rf -- "$resources_directory"
ditto "$staged_resources_directory/resources" "$resources_directory"
install -m 0644 "$staged_resources_directory/resources.stamp" "$resources_stamp"
staged_resources_directory=""

echo "Packaged Ghostscript resources at $resources_directory"
