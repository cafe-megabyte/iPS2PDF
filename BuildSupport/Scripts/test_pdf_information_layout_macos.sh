#!/bin/bash
set -euo pipefail
# Run sequentially, without a simulator. Uses the production AppKit view unchanged.
scratch="${1:?Expected scratch directory}"
project="$(cd "$(dirname "$0")/../.." && pwd)"
app="$scratch/PDFInformationLayoutSmoke.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>org.ips2pdf.tests.layout</string><key>CFBundleExecutable</key><string>PDFInformationLayoutSmoke</string><key>CFBundleName</key><string>PDF Information Layout Smoke</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
cp "$project/Tests/Unit/Fixtures/Review/many-incomplete-pages.pdf" "$app/Contents/Resources/"
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
    "$project/Sources/Targets/MacOSApp/MacOSPDFInfoWindowController.swift" \
    "$project/Sources/Targets/MacOSApp/MacOSPDFInfoViewController.swift" \
    "$project/Sources/Targets/MacOSApp/PDFInformationRowView.swift" \
    "$project/Sources/Targets/MacOSApp/PDFOutlineItem.swift" \
    "$project/Sources/Targets/MacOSApp/PDFResourceExportButton.swift" \
    "$project/Sources/Targets/MacOSApp/MacOSPDFCompressionWindowController.swift" \
    "$project/Tests/MacOS/PDFInformationLayoutSmoke.swift" \
    -o "$app/Contents/MacOS/PDFInformationLayoutSmoke"
codesign --force --sign - "$app"
"$app/Contents/MacOS/PDFInformationLayoutSmoke" "$scratch/layout.png" "${2:-}"
