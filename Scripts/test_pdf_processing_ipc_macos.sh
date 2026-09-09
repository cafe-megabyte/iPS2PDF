#!/bin/bash
set -euo pipefail
scratch="${1:?Expected a scratch directory}"
frameworks="${2:?Expected built macOS frameworks directory}"
project="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$scratch"
xcrun swiftc -swift-version 6 -parse-as-library -target "$(uname -m)-apple-macos15" \
    -module-cache-path "$scratch/ModuleCache" \
    -F "$frameworks" -framework PDFProcessingRuntime -Xlinker -rpath -Xlinker "$frameworks" \
    "$project"/Sources/Shared/AppCore/PDFInspection/*.swift \
    "$project"/Sources/Shared/ICCMetadata/*.swift \
    "$project"/Sources/Shared/IPC/PDFProcessing/*.swift \
    "$project"/Sources/Shared/IPC/MacOSXPC/*.swift \
    "$project/Sources/Shared/IPC/AppGroup/AppGroup.swift" \
    "$project/Sources/Shared/IPC/GhostscriptControl/GhostscriptExtensionEnvelope.swift" \
    "$project/Sources/Shared/PDFProcessingRuntime/RequestHandling/PDFNativeControl.swift" \
    "$project/Sources/Shared/PDFProcessingRuntime/RequestHandling/PDFNativeRequestLease.swift" \
    "$project/Sources/Shared/PDFProcessingRuntime/RequestHandling/PDFProcessingRequestHandler.swift" \
    "$project/Tests/MacOS/PDFProcessingIPCSmoke.swift" -o "$scratch/PDFProcessingIPCSmoke"
"$scratch/PDFProcessingIPCSmoke" "$project/Tests/Unit/Fixtures" \
    "$project/BundledResources/Signature/SignatureFont-Dummy.otf"
