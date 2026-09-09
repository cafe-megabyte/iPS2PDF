#!/bin/bash
set -euo pipefail
# The immutable editing model and the actual PDF inspector run without a UI,
# signing identity, simulator, or Ghostscript build.
scratch="${1:?Expected an explicit scratch directory}"
project="$(cd "$(dirname "$0")/../.." && pwd)"
mkdir -p "$scratch"
pdf_test_architecture="$(uname -m)"
xcrun swiftc -swift-version 6 -parse-as-library -target "${pdf_test_architecture}-apple-macos15" \
    "$project"/Sources/Shared/AppCore/PDFInspection/*.swift \
    "$project"/Sources/Shared/ICCMetadata/*.swift \
    "$project"/Sources/Shared/AppCore/PDFProcessing/*.swift \
    "$project"/Sources/Shared/IPC/PDFProcessing/*.swift \
    "$project/Sources/Shared/IPC/AppGroup/AppGroup.swift" \
    "$project/Tests/MacOS/PDFEditingSessionSmoke.swift" \
    -o "$scratch/PDFEditingSessionSmoke"
"$scratch/PDFEditingSessionSmoke" "$project/Tests/Unit/Fixtures"
