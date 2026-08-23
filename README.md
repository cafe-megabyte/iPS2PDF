# iPS2PDF

iPS2PDF is a SwiftUI app for iOS and iPadOS that converts files to PDF with a statically linked Ghostscript library. A file can be selected inside the app or sent to it through **Open with iPS2PDF**. Selected PostScript text can also be handed to the lightweight Share Extension, which opens the containing app and delegates conversion to its Ghostscript helper. The app copies the input into its temporary workspace, stages the active job in one shared App Group, validates the generated PDF with PDFKit, and presents it for viewing and sharing.

The input is intentionally not filtered by filename extension or content. Ghostscript decides whether a file can be processed.

## Building

Place exactly one Ghostscript source archive matching `*.tar.gz` in:

```text
Vendor/Ghostscript/
```

For example, the tested archive is:

```text
Vendor/Ghostscript/ghostscript-10.07.1.tar.gz
```

The `GHOSTSCRIPT_ARCHIVE_PATH` build setting of the `Build Ghostscript` target must point to that file. Update the setting when an upgrade changes the archive filename.

The archive does not need to be unpacked manually. The `Build Ghostscript` aggregate target extracts it into a disposable directory, creates a patched working copy of Ghostscript's official iOS build script, and publishes the static library, public headers, and PDF/A resources under `$(PROJECT_TEMP_DIR)/GhostscriptArtifacts/`. The main app's `iPS2PDFSecurity` helper depends on that aggregate target. Xcode input/output dependency analysis reuses unchanged artifacts on subsequent builds; changing the source archive or build script rebuilds them automatically. Simulator and device variants remain separate. Deleting the build folder still forces a complete rebuild.

The `iPS2PDFSecurity` Ghostscript helper links the generated `libgs.a` and installs the required Ghostscript resources in its bundle. The app, Share Extension, and Ghostscript helper use the same App Group. It contains only the current handoff and conversion job in `ShareInbox`, `ConversionInput`, and `ConversionOutput`; XPC carries control metadata, not document payloads. Persistent Joboptions and ICC profiles remain in the main app's private Application Support directory. The Share Extension neither links Ghostscript/PDFKit nor contains conversion settings or conversion resources; it only transfers text and activates the main app.

Open `iPS2PDF.xcodeproj`, select the `iPS2PDF` scheme and the desired iOS destination, then build with **Command-B**. The first build takes longer because it compiles Ghostscript; subsequent builds reuse the generated library.

## Tested configuration

- Ghostscript 10.07.1
- Xcode 27.0, build 27A5237l
- iPhone 17 Pro simulator with iOS 27.0
- Deployment target: iOS/iPadOS 26.0 or newer
- Ghostscript sample: `examples/colorcir.ps`
- Verified output: PDF 1.2, PDF 1.3, and PDF 1.4, validated with PDFKit

## License

The entire project—including the Swift app, C bridge, build and patcher scripts, and the integrated Ghostscript code—is licensed under the **GNU Affero General Public License, version 3 or later (AGPL-3.0-or-later)**.

Ghostscript and its included third-party components retain their original copyright, license notices, compatible exceptions, and additional terms as documented in the upstream source tree.
