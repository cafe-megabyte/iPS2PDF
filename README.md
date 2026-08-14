# iPS2PDF

iPS2PDF is a SwiftUI app for iOS and iPadOS that converts files to PDF with a statically linked Ghostscript library. A file can be selected inside the app or sent to it through **Open with iPS2PDF**. The app copies the input into its temporary workspace, converts it as PDF 1.2, 1.3, or 1.4, validates the result with PDFKit, and presents it for viewing and sharing.

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

The archive does not need to be unpacked manually. When `Vendor/Ghostscript/upstream/` is missing or empty, the Xcode build phase finds the archive, extracts its top-level source directory as `upstream`, creates a patched working copy of Ghostscript's official iOS build script, and builds the required static library. Simulator and device artifacts are kept separate and are reused based on their existence.

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
