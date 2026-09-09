#!/bin/bash
set -euo pipefail
pdf_resources="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
mkdir -p "$pdf_resources"
ditto "$PDF_PROCESSING_ARTIFACT_DIR/PDFProcessingLicenses" "$pdf_resources/PDFProcessingLicenses"
if [[ "$PLATFORM_NAME" == "macosx" ]]; then
    pdf_headers="$TARGET_BUILD_DIR/$PUBLIC_HEADERS_FOLDER_PATH"
    mkdir -p "$pdf_headers"
    cp "$SRCROOT/Sources/Targets/MacOSPDFProcessingRuntime/PDFProcessingRuntime.h" "$pdf_headers/"
    cp "$PDF_PROCESSING_ARTIFACT_DIR/include/PDFProcessingBridge.h" "$pdf_headers/"
fi
