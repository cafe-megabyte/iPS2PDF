#!/bin/bash
# Build the native PDF runtime from the original upstream source archives.
# Xcode supplies every compiler, SDK and binary utility used below. The build
# performs no network access and never consults PATH for Homebrew tools.
set -euo pipefail

project="${SRCROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
vendor="$project/Vendor/PDFProcessing"
recipe_source="$project/BuildSupport/Scripts/PDFProcessing"
native_source="$project/Sources/Shared/PDFProcessingRuntime/Native"
project_temp="${PROJECT_TEMP_DIR:?PROJECT_TEMP_DIR is required}"
artifact_destination="${PDF_PROCESSING_ARTIFACT_DIR:?PDF_PROCESSING_ARTIFACT_DIR is required}"
platform="${PLATFORM_NAME:?PLATFORM_NAME is required}"
architectures="${ARCHS:?ARCHS is required}"

component_names=(
  HyperCompress QPDF QPDFLibJPEG PDFium JPEGLI JPEGLILibJPEG Highway
  ChromiumBuild Abseil Brotli Dragonbox FastFloat FreeType HarfBuzz ICU
  PDFiumLibJPEG Zlib
)
component_directories=(
  "$vendor/HyperCompress" "$vendor/QPDF" "$vendor/QPDFLibJPEG"
  "$vendor/PDFium" "$vendor/JPEGLI"
  "$vendor/JPEGLIDependencies/LibJPEG" "$vendor/Highway"
  "$vendor/PDFiumDependencies/ChromiumBuild"
  "$vendor/PDFiumDependencies/Abseil" "$vendor/PDFiumDependencies/Brotli"
  "$vendor/PDFiumDependencies/Dragonbox" "$vendor/PDFiumDependencies/FastFloat"
  "$vendor/PDFiumDependencies/FreeType" "$vendor/PDFiumDependencies/HarfBuzz"
  "$vendor/PDFiumDependencies/ICU" "$vendor/PDFiumDependencies/LibJPEG"
  "$vendor/PDFiumDependencies/Zlib"
)
archives=()

resolve_archive() {
  local name="$1" directory="$2" count archive
  if [[ ! -d "$directory" ]]; then
    echo "error: Missing $name source-archive directory: $directory" >&2
    exit 1
  fi
  count=$(/usr/bin/find "$directory" -maxdepth 1 -type f -name '*.tar.gz' | /usr/bin/wc -l | /usr/bin/tr -d ' ')
  if [[ "$count" == 0 ]]; then
    echo "error: No $name source archive matching *.tar.gz found in: $directory" >&2
    exit 1
  fi
  if [[ "$count" != 1 ]]; then
    echo "error: Multiple $name source archives matching *.tar.gz found in: $directory" >&2
    /usr/bin/find "$directory" -maxdepth 1 -type f -name '*.tar.gz' -print >&2
    exit 1
  fi
  archive=$(/usr/bin/find "$directory" -maxdepth 1 -type f -name '*.tar.gz' -print)
  if ! /usr/bin/tar -tf "$archive" >/dev/null; then
    echo "error: $name input is not an archive readable by macOS tar: $archive" >&2
    exit 1
  fi
  archives+=("$archive")
}

for ((index=0; index<${#component_names[@]}; ++index)); do
  resolve_archive "${component_names[$index]}" "${component_directories[$index]}"
done

content_hash() {
  /usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{print $1}'
}

# Archive hashes are cache keys, never an allowlist. Replacing the single file
# in any component directory automatically selects and rebuilds that source.
fingerprint_file=$(/usr/bin/mktemp "${TMPDIR:-/tmp}/ips2pdf-pdf-fingerprint.XXXXXX")
trap '/bin/rm -f "$fingerprint_file"' EXIT
for ((index=0; index<${#archives[@]}; ++index)); do
  printf '%s %s\n' "${component_names[$index]}" "$(content_hash "${archives[$index]}")" >> "$fingerprint_file"
done
printf '%s %s\n' "BuildSupport/Scripts/build_pdf_for_xcode.sh" \
  "$(content_hash "$project/BuildSupport/Scripts/build_pdf_for_xcode.sh")" >> "$fingerprint_file"
/usr/bin/find "$recipe_source" "$native_source" -type f -print | /usr/bin/sort | while IFS= read -r file; do
  printf '%s %s\n' "${file#$project/}" "$(content_hash "$file")"
done >> "$fingerprint_file"
source_key=$(content_hash "$fingerprint_file")

source_parent="$project_temp/PDFProcessingSources"
source_root="$source_parent/${source_key:0:20}"
/bin/mkdir -p "$source_parent"

extract_archive() {
  local archive="$1" destination="$2" strip="$3"
  /bin/mkdir -p "$destination"
  if [[ "$strip" == 1 ]]; then
    /usr/bin/tar -xf "$archive" -C "$destination" --strip-components 1
  else
    /usr/bin/tar -xf "$archive" -C "$destination"
  fi
}

prepare_sources() {
  local temporary="$1" pdfium hyper
  /bin/mkdir -p "$temporary/sources"

  extract_archive "${archives[0]}" "$temporary/sources/hyper" 1
  extract_archive "${archives[1]}" "$temporary/sources/qpdf" 1
  extract_archive "${archives[2]}" "$temporary/sources/qpdf-jpeg" 1
  extract_archive "${archives[3]}" "$temporary/sources/pdfium" 0
  extract_archive "${archives[4]}" "$temporary/sources/jpegli" 1

  extract_archive "${archives[5]}" \
    "$temporary/sources/jpegli/third_party/libjpeg-turbo" 1
  /bin/rm -rf "$temporary/sources/jpegli/third_party/highway"
  extract_archive "${archives[6]}" "$temporary/sources/jpegli/third_party/highway" 1

  pdfium="$temporary/sources/pdfium"
  extract_archive "${archives[7]}" "$pdfium/build" 0
  extract_archive "${archives[8]}" "$pdfium/third_party/abseil-cpp" 0
  extract_archive "${archives[9]}" "$pdfium/third_party/brotli" 0
  extract_archive "${archives[10]}" "$pdfium/third_party/dragonbox/src" 0
  extract_archive "${archives[11]}" "$pdfium/third_party/fast_float/src" 0
  extract_archive "${archives[12]}" "$pdfium/third_party/freetype/src" 0
  extract_archive "${archives[13]}" "$pdfium/third_party/harfbuzz/src" 0
  extract_archive "${archives[14]}" "$pdfium/third_party/icu" 0
  extract_archive "${archives[15]}" "$pdfium/third_party/libjpeg_turbo" 0
  extract_archive "${archives[16]}" "$pdfium/third_party/zlib" 0

  # Hyper Compress's public archive does not include all PDFium API changes
  # required by its adapter. Keep those text changes as an ordinary patch and
  # apply them with the patch utility supplied by macOS.
  /usr/bin/patch -s -d "$pdfium" -p1 < "$recipe_source/pdfium-hyper-apple.patch"

  hyper="$temporary/sources/hyper/core"
  /bin/cp "$hyper/src/fpdf_compress.cpp" "$hyper/src/hyper_type1_wrap.cc" \
    "$hyper/src/hyper_jbig2_wrap.cc" "$hyper/src/hyper_generic_cmyk_icc.h" \
    "$pdfium/fpdfsdk/"
  /bin/cp "$hyper/include/fpdf_compress.h" "$pdfium/public/fpdf_compress.h"
  /usr/bin/sed \
    -e 's@core/fxcodec/jbig2/JBig2_DocumentContext\.h@core/fxcodec/jbig2/jbig2_document_context.h@' \
    -e 's@third_party/harfbuzz-ng/src/src/@third_party/harfbuzz/src/src/@g' \
    "$pdfium/fpdfsdk/fpdf_compress.cpp" > "$pdfium/fpdfsdk/fpdf_compress.cpp.ips2pdf"
  /bin/mv "$pdfium/fpdfsdk/fpdf_compress.cpp.ips2pdf" "$pdfium/fpdfsdk/fpdf_compress.cpp"
  for dependency in afdko jbig2enc leptonica; do
    /bin/rm -rf "$pdfium/third_party/$dependency"
    /usr/bin/ditto "$hyper/third_party/$dependency" "$pdfium/third_party/$dependency"
  done

  /usr/bin/ditto "$recipe_source" "$temporary/recipes"
  /usr/bin/ditto "$native_source" "$temporary/sources/native"
  /bin/mkdir -p "$temporary/generated/qpdf/qpdf" \
    "$temporary/generated/qpdf-jpeg" "$temporary/generated/jpegli"
  /bin/cp "$temporary/recipes/Config/qpdf-config.h" \
    "$temporary/generated/qpdf/qpdf/qpdf-config.h"
  /bin/cp "$temporary/recipes/Config/qpdf-jconfig.h" \
    "$temporary/generated/qpdf-jpeg/jconfig.h"
  /bin/cp "$temporary/recipes/Config/qpdf-jconfigint.h" \
    "$temporary/generated/qpdf-jpeg/jconfigint.h"
  /bin/cp "$temporary/recipes/Config/qpdf-jversion.h" \
    "$temporary/generated/qpdf-jpeg/jversion.h"
  /bin/cp "$temporary/recipes/Config/jpegli-jconfig.h" \
    "$temporary/generated/jpegli/jconfig.h"
  /bin/cp "$temporary/sources/jpegli/third_party/libjpeg-turbo/jpeglib.h" \
    "$temporary/sources/jpegli/third_party/libjpeg-turbo/jmorecfg.h" \
    "$temporary/sources/jpegli/third_party/libjpeg-turbo/jerror.h" \
    "$temporary/generated/jpegli/"

  for required in \
    "$pdfium/public/fpdfview.h" "$pdfium/fpdfsdk/fpdf_compress.cpp" \
    "$pdfium/third_party/icu/source/common/unicode/utypes.h" \
    "$temporary/sources/qpdf/include/qpdf/QPDF.hh" \
    "$temporary/sources/jpegli/lib/jpegli/encode.cc" \
    "$temporary/generated/jpegli/jpeglib.h" \
    "$temporary/generated/jpegli/jmorecfg.h" \
    "$temporary/generated/jpegli/jerror.h" \
    "$temporary/sources/jpegli/third_party/highway/hwy/highway.h"; do
    if [[ ! -f "$required" ]]; then
      echo "error: Extracted source layout is incompatible with the iPS2PDF recipe: $required" >&2
      exit 1
    fi
  done

  {
    echo "Source archives used by this build"
    echo
    for ((index=0; index<${#archives[@]}; ++index)); do
      printf '%-18s  %s  %s\n' "${component_names[$index]}" \
        "$(content_hash "${archives[$index]}")" "$(basename "${archives[$index]}")"
    done
  } > "$temporary/source-archives.txt"
  printf '%s\n' "$source_key" > "$temporary/.ready"
}

source_lock="$source_parent/.${source_key:0:20}.lock"
if [[ ! -f "$source_root/.ready" ]]; then
  attempts=0
  while ! /bin/mkdir "$source_lock" 2>/dev/null; do
    if [[ -f "$source_root/.ready" ]]; then break; fi
    attempts=$((attempts + 1))
    if (( attempts > 900 )); then
      echo "error: Timed out waiting for another PDF source extraction" >&2
      exit 1
    fi
    /bin/sleep 1
  done
  if [[ ! -f "$source_root/.ready" ]]; then
    temporary=$(/usr/bin/mktemp -d "$source_parent/.prepare.XXXXXX")
    cleanup_prepare() { /bin/rm -rf "$temporary" "$source_lock"; }
    trap 'cleanup_prepare; /bin/rm -f "$fingerprint_file"' EXIT
    echo "Preparing native PDF sources from Vendor archives…"
    prepare_sources "$temporary"
    /bin/mv "$temporary" "$source_root"
    /bin/rmdir "$source_lock"
    trap '/bin/rm -f "$fingerprint_file"' EXIT
  fi
fi

case "$platform" in
  macosx)
    sdk=macosx
    deployment="${MACOSX_DEPLOYMENT_TARGET:-15.0}"
    link_platform=macos
    ;;
  iphoneos)
    sdk=iphoneos
    deployment="${IPHONEOS_DEPLOYMENT_TARGET:-26.0}"
    link_platform=ios
    ;;
  iphonesimulator)
    sdk=iphonesimulator
    deployment="${IPHONEOS_DEPLOYMENT_TARGET:-26.0}"
    link_platform=ios-simulator
    ;;
  *)
    echo "error: Unsupported PDF processing platform: $platform" >&2
    exit 1
    ;;
esac

sdk_root=$(/usr/bin/xcrun --sdk "$sdk" --show-sdk-path)
compiler=$(/usr/bin/xcrun --sdk "$sdk" --find clang)
compiler_version=$("$compiler" --version)
sdk_version=$(/usr/bin/xcrun --sdk "$sdk" --show-sdk-version)
jobs=$(/usr/sbin/sysctl -n hw.logicalcpu 2>/dev/null || echo 4)
# Several Xcode targets may build concurrently. Six compiler processes keeps
# this large source build responsive and avoids excessive peak memory use.
if (( jobs > 6 )); then jobs=6; fi
if (( jobs < 1 )); then jobs=1; fi

verify_slice() {
  local archive="$1" expected actual
  expected=$(/usr/bin/mktemp "${TMPDIR:-/tmp}/ips2pdf-pdf-symbols-expected.XXXXXX")
  actual=$(/usr/bin/mktemp "${TMPDIR:-/tmp}/ips2pdf-pdf-symbols-actual.XXXXXX")
  /usr/bin/sort -u "$recipe_source/Config/public-symbols.txt" > "$expected"
  /usr/bin/xcrun nm -gU "$archive" | /usr/bin/awk 'NF >= 3 { print $NF }' | \
    /usr/bin/sort -u > "$actual"
  if ! /usr/bin/cmp -s "$expected" "$actual"; then
    echo "error: Native PDF archive exports differ from the public bridge" >&2
    /usr/bin/diff -u "$expected" "$actual" >&2 || true
    /bin/rm -f "$expected" "$actual"
    exit 1
  fi
  if /usr/bin/xcrun nm -u "$archive" | /usr/bin/awk '{ print $NF }' | \
      /usr/bin/grep -Eq '^_Cr_z_'; then
    echo "error: Native PDF archive has unresolved bundled zlib symbols" >&2
    /bin/rm -f "$expected" "$actual"
    exit 1
  fi
  /bin/rm -f "$expected" "$actual"
}

slices=()
for architecture in $architectures; do
  case "$architecture" in arm64|x86_64) ;; *)
    echo "error: Unsupported PDF processing architecture: $architecture" >&2
    exit 1
  esac
  if [[ "$platform" == iphonesimulator ]]; then
    target_triple="$architecture-apple-ios$deployment-simulator"
  elif [[ "$platform" == iphoneos ]]; then
    target_triple="$architecture-apple-ios$deployment"
  else
    target_triple="$architecture-apple-macos$deployment"
  fi
  tool_key=$(printf '%s\n%s\n%s\n%s\n%s\n' "$source_key" "$compiler_version" \
    "$sdk_root" "$sdk_version" "$target_triple" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}')
  build_key="$platform-$architecture-${tool_key:0:16}"
  slice="$source_root/build/$build_key/output/libPDFProcessingNative.a"
  slice_lock="$source_root/.build-$build_key.lock"
  if [[ ! -f "$slice" ]]; then
    attempts=0
    while ! /bin/mkdir "$slice_lock" 2>/dev/null; do
      if [[ -f "$slice" ]]; then break; fi
      attempts=$((attempts + 1))
      if (( attempts > 3600 )); then
        echo "error: Timed out waiting for another native PDF build" >&2
        exit 1
      fi
      /bin/sleep 1
    done
    if [[ ! -f "$slice" ]]; then
      echo "Building native PDF runtime for $platform/$architecture with Xcode clang…"
      if ! /usr/bin/make --no-print-directory -C "$source_root" -f recipes/Makefile \
        -j "$jobs" PLATFORM_KEY="$build_key" SDK="$sdk" ARCH="$architecture" \
        TARGET_TRIPLE="$target_triple" LINK_PLATFORM="$link_platform" \
        DEPLOYMENT_TARGET="$deployment" all; then
        /bin/rmdir "$slice_lock"
        exit 1
      fi
      /bin/rmdir "$slice_lock"
    fi
  else
    echo "Reusing native PDF runtime for $platform/$architecture"
  fi
  # Xcode 26 requires the input before the operation. Xcode 27 also accepts
  # this canonical ordering, while its more permissive operation-first form
  # is rejected by the older lipo.
  /usr/bin/xcrun lipo "$slice" -verify_arch "$architecture"
  verify_slice "$slice"
  slices+=("$slice")
done

collect_licenses() {
  local root="$1" destination="$2" pdfium="$1/sources/pdfium"
  /bin/mkdir -p "$destination"
  /bin/cp "$root/recipes/Config/components.json" "$destination/components.json"
  /bin/cp "$root/recipes/Config/ACKNOWLEDGMENTS.txt" "$destination/ACKNOWLEDGMENTS.txt"
  /bin/cp "$root/source-archives.txt" "$destination/source-archives.txt"
  /bin/cp "$root/sources/hyper/LICENSE" "$destination/00-Hyper-Compress-LICENSE"
  /bin/cp "$root/sources/hyper/NOTICE.md" "$destination/00-Hyper-Compress-NOTICE.md"
  /bin/cp "$pdfium/LICENSE" "$destination/01-PDFium-LICENSE"
  /bin/cp "$pdfium/third_party/agg23/copying" "$destination/02-AGG-2.3-copying"
  /bin/cp "$pdfium/third_party/freetype/src/LICENSE.TXT" "$destination/03-FreeType-LICENSE.TXT"
  /bin/cp "$pdfium/third_party/freetype/src/docs/FTL.TXT" "$destination/03-FreeType-FTL.TXT"
  /bin/cp "$pdfium/third_party/lcms/LICENSE" "$destination/04-Little-CMS-LICENSE"
  /bin/cp "$pdfium/third_party/libopenjpeg/LICENSE" "$destination/05-OpenJPEG-LICENSE"
  /bin/cp "$pdfium/third_party/libjpeg_turbo/LICENSE.md" "$destination/06-Chromium-libjpeg-turbo-LICENSE.md"
  /bin/cp "$pdfium/third_party/libjpeg_turbo/LICENSE.md.chromium" "$destination/06-Chromium-libjpeg-turbo-LICENSE.md.chromium"
  /bin/cp "$pdfium/third_party/libjpeg_turbo/README.ijg" "$destination/06-Chromium-libjpeg-turbo-README.ijg"
  /bin/cp "$pdfium/third_party/abseil-cpp/LICENSE" "$destination/07-Abseil-LICENSE"
  /bin/cp "$pdfium/third_party/brotli/LICENSE" "$destination/08-Brotli-LICENSE"
  /bin/cp "$pdfium/third_party/dragonbox/src/LICENSE-Boost" "$destination/09-Dragonbox-LICENSE-Boost"
  /bin/cp "$pdfium/third_party/fast_float/src/LICENSE-MIT" "$destination/10-fast_float-LICENSE-MIT"
  /bin/cp "$pdfium/third_party/harfbuzz/src/COPYING" "$destination/11-HarfBuzz-COPYING"
  /bin/cp "$pdfium/third_party/icu/LICENSE" "$destination/12-ICU-LICENSE"
  /bin/cp "$pdfium/third_party/jbig2enc/COPYING" "$destination/13-jbig2enc-COPYING"
  /bin/cp "$pdfium/third_party/leptonica/leptonica-license.txt" "$destination/14-Leptonica-leptonica-license.txt"
  /bin/cp "$pdfium/third_party/zlib/LICENSE" "$destination/15-Chromium-zlib-LICENSE"
  /bin/cp "$root/sources/jpegli/LICENSE" "$destination/16-jpegli-LICENSE"
  /bin/cp "$root/sources/jpegli/third_party/highway/LICENSE" "$destination/17-Highway-LICENSE"
  /bin/cp "$root/sources/qpdf/LICENSE.txt" "$destination/18-qpdf-qpdf-LICENSE.txt"
  /bin/cp "$root/sources/qpdf-jpeg/LICENSE.md" "$destination/19-qpdf-libjpeg-turbo-libjpeg-turbo-LICENSE.md"
  /bin/cp "$root/sources/qpdf-jpeg/README.ijg" "$destination/19-qpdf-libjpeg-turbo-libjpeg-turbo-README.ijg"
  {
    /usr/bin/find "$pdfium/third_party/afdko" -type f \( -name '*.h' -o -name '*.c' -o -name '*.cpp' \) -print | \
      /usr/bin/sort | while IFS= read -r file; do /usr/bin/sed -n '1,35p' "$file" | \
      /usr/bin/grep -i copyright || true; done | /usr/bin/sed 's@^[[:space:]/*]*@@' | /usr/bin/sort -u
    echo
    /bin/cat "$pdfium/third_party/abseil-cpp/LICENSE"
  } > "$destination/20-AFDKO-LICENSE.txt"
  /bin/cp "$root/sources/jpegli/third_party/libjpeg-turbo/LICENSE.md" \
    "$destination/21-jpegli-libjpeg-turbo-LICENSE.md"
  /bin/cp "$root/sources/jpegli/third_party/libjpeg-turbo/README.ijg" \
    "$destination/21-jpegli-libjpeg-turbo-README.ijg"
}

artifact_parent=$(dirname "$artifact_destination")
/bin/mkdir -p "$artifact_parent"
stage=$(/usr/bin/mktemp -d "$artifact_parent/.PDFProcessingArtifacts.XXXXXX")
cleanup_stage() { /bin/rm -rf "$stage"; }
trap 'cleanup_stage; /bin/rm -f "$fingerprint_file"' EXIT
if (( ${#slices[@]} == 1 )); then
  /bin/cp "${slices[0]}" "$stage/libPDFProcessingNative.a"
else
  /usr/bin/xcrun lipo "${slices[@]}" -create -output "$stage/libPDFProcessingNative.a"
fi
/bin/mkdir -p "$stage/include"
/bin/cp "$native_source/PDFProcessingBridge.h" "$stage/include/PDFProcessingBridge.h"
/bin/cat > "$stage/include/module.modulemap" <<'EOF'
module PDFProcessingNative {
  header "PDFProcessingBridge.h"
  export *
}
EOF
collect_licenses "$source_root" "$stage/PDFProcessingLicenses"
printf 'source-key: %s\nplatform: %s\narchitectures: %s\nsdk: %s\n' \
  "$source_key" "$platform" "$architectures" "$sdk_version" > "$stage/build-receipt.txt"
/bin/rm -rf "$artifact_destination"
/bin/mv "$stage" "$artifact_destination"
trap '/bin/rm -f "$fingerprint_file"' EXIT
echo "Built native PDF artifacts at $artifact_destination"
