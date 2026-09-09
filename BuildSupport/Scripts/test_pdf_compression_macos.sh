#!/bin/bash
set -euo pipefail
scratch="${1:?Expected scratch directory}"
project="$(cd "$(dirname "$0")/../.." && pwd)"
mkdir -p "$scratch"
pdf_layout_sources=()
while IFS= read -r pdf_layout_source; do
    pdf_layout_sources+=("$pdf_layout_source")
done < <(rg --files "$project/Sources/Shared/AppCore" -g '*.swift' -g '!JoboptionsRepository.swift' | sort)
xcrun swiftc -swift-version 6 \
    "${pdf_layout_sources[@]}" \
    "$project"/Sources/Shared/ICCMetadata/*.swift \
    "$project"/Sources/Shared/PDFProcessingClient/*.swift \
    "$project"/Sources/Shared/GhostscriptClient/*.swift \
    "$project"/Sources/Shared/IPC/AppGroup/*.swift \
    "$project"/Sources/Shared/IPC/GhostscriptControl/*.swift \
    "$project"/Sources/Shared/IPC/PDFProcessing/*.swift \
    "$project"/Sources/Shared/IPC/MacOSXPC/*.swift \
    "$project/Sources/Targets/MacOSApp/MacOSGhostscriptService.swift" \
    "$project/Sources/Targets/MacOSApp/MacOSPDFReportSharing.swift" \
    "$project/Tests/MacOS/PDFCompressionSessionSmoke.swift" \
    -o "$scratch/PDFCompressionSessionSmoke"
"$scratch/PDFCompressionSessionSmoke" "$project/Tests/Unit/Fixtures"
