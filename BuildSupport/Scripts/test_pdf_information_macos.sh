#!/bin/bash
set -euo pipefail
# Run after building the macOS scheme. No provisioning profile is required for this smoke test.
# Usage: test_pdf_information_macos.sh <Debug products directory> <scratch directory>
products="${1:?Expected Debug products directory}"
scratch="${2:?Expected scratch directory}"
project="$(cd "$(dirname "$0")/../.." && pwd)"
mkdir -p "$scratch"
xcrun swiftc -swift-version 6 -F "$products" -framework GhostscriptRuntime \
    -Xlinker -rpath -Xlinker "$products" \
    "$project"/Sources/Shared/AppCore/PDFInspection/*.swift \
    "$project"/Sources/Shared/ICCMetadata/*.swift \
    "$project/Sources/Shared/GhostscriptRuntime/Resources/GhostscriptRuntimeResources.swift" \
    "$project/Sources/Targets/MacOSApp/MacOSPostScriptDestinationWriter.swift" \
    "$project/Sources/Targets/MacOSApp/MacOSPDFReportSharing.swift" \
    "$project/Tests/MacOS/PDFInformationSmoke.swift" -o "$scratch/pdf-information-smoke"
"$scratch/pdf-information-smoke" "$project/Tests/Unit/Fixtures"
