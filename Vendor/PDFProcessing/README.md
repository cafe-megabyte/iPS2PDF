# Native PDF editing

The macOS and iOS apps provide **Remove metadata** and **Compress PDF** on the
PDF information view. macOS also has **File → Compress PDF…**, using the active
PDF or a file picker. iOS uses SF Symbol buttons and a compression sheet.

Both operations work on private copies. The editing session owns immutable
original/current revisions, file-backed undo/redo, and the revision used by the
inspector, preview and export. Nothing overwrites the source document. A
compression candidate becomes the current revision only with **Use result**;
saving/exporting is explicit. Signature removal, changed protection and removed
attachments produce notices before the user saves the result.

## Processing architecture

`Sources/Shared/PDFProcessingRuntime/Native` contains the qpdf structural editor
and the native adapters for the vendored Hyper Compress/PDFium/jpegli code. qpdf
owns the document structure. PDFium decodes isolated image capsules and converts
colors; jpegli encodes JPEG and PDFium's fax encoder produces CCITT Group 4.
This does not redraw whole pages, use a web view/WASM, or pass PDFs through
Ghostscript. Existing embedded font programs are retained, including Standard
14 fonts; absent fonts are neither added nor reported as an error. The one
deliberate exception is the narrowly identified Pages CFF subset that stores a
vector signature under Apple Garamond: metadata cleanup changes its external
and internal names to Signature Font without changing the glyph program.

Requests use a separate versioned protocol in the existing macOS XPC / iOS
ExtensionKit helpers. Per-job private directories, leases, a shared engine gate,
cancellation, generation checks, deadlines and input/output/image limits keep
processing separate from the original document and from Ghostscript jobs. The
native runtime is a private macOS framework and a static iOS helper dependency.
Quick Look and thumbnail targets do not acquire this dependency.

Embedded font export preserves an existing PFB, TrueType or OpenType container.
A readable bare CFF 1 program is placed unchanged in a newly built `.otf`
container with metrics, names and every Unicode mapping that FreeType can
derive from its glyph names. CID and custom glyphs without a Unicode value stay
in the CFF glyph program. Both FreeType and Apple font services must reopen the
result before it is written. A malformed CFF that cannot be represented safely
keeps its honest `.cff` export instead of receiving an OpenType extension.

The linker first combines the native archives into a relocatable object, then
localizes implementation symbols with Apple's `nmedit`. Only the C interface
remains public. This prevents Ghostscript's copies of JPEG, Little CMS, FreeType
and other libraries from satisfying incompatible PDFium references. qpdf's own
libjpeg is namespaced separately.

## Metadata and conformity

A full rewrite removes Info/custom fields, document/page/object XMP, PieceInfo,
application history, content comments, nonfunctional annotation author/date
fields, JPEG EXIF/XMP/comments, supported JP2 XML/UUID/JPEG 2000 comments, and
JBIG2 comment/resolution metadata. Unreachable objects and incremental history
are omitted. Functional names/references, comment contents/replies, hidden/OCR
content, forms, tags, links, bookmarks and layers remain. Metadata-only editing
retains the decoded bytes of embedded files and ICC profiles. Font programs are
also retained except for the three equal-length names in the recognized Pages
signature subset described above. Technical data needed to interpret those
payloads is retained.

Metadata removal asks whether to preserve the declared conformity. The policy
retains/rebuilds only required identification fields for PDF/A-1–4, PDF/UA-1–2,
PDF/X-1a (2001/2003), PDF/X-3 (2002/2003), and PDF/X-4/4p. PDF/UA retains its
meaningful title; PDF/X gets a neutral title and fresh required dates/identity.
Required combined A/UA/X extension schemas are rebuilt. Conflicting, incomplete
or unsupported declarations produce an explanation; users can choose to
remove the declaration instead. This is **not a conformity validator** and does
not certify or repair the source document's complete standard compliance.

Compression always discards conformity and metadata and removes embedded files,
attachment actions and output profiles. ICC-dependent colors are converted
before profiles are removed. Invoice attachments receive an additional notice.
Supported authenticated encryption and permissions are retained; unsupported
protection may be removed with a notice. A missing/wrong opening password never
bypasses encryption. Digital signatures are cleared; ordinary printable
signature appearances are reused as vector content where possible.

## Compression policy and preview

`PDFCompressionPolicy.h` is the central policy table with English comments.
The UI exposes Gentle / Balanced / Strong, Color / Black & White, contrast or
threshold, and Paper cleanup. Fresh sessions default to Balanced, Color,
contrast 25, threshold 75 and paper cleanup 50. There is no JPEG 2000 output,
new Brotli, lossy JBIG2, dithering, font subsetting or image upscaling.

| Target | Gentle | Balanced | Strong |
| --- | ---: | ---: | ---: |
| Color scan PPI | 225 | 140 | 110 |
| Monochrome PPI | 600 | 450 | 300 |
| JPEG quality | 20 | 40 | 60 |

The policy assumes scans/documents. Higher color resolution deliberately uses
stronger JPEG quantization, while lower resolution keeps more sample quality so
both losses are not maximized at once. Resolution follows the minimum effective
placement PPI across both axes and all uses, including nested forms and repeated
images. Color output chooses the smaller of JPEG and RGB Flate. Monochrome
images use genuine one-bit CCITT Group 4; technical masks keep the depth needed
for transparency. Text/strokes become black, pure white knockouts stay white,
and vector fills follow the threshold.

Paper cleanup zero uses the ordinary single-image path and performs no extra
analysis. Higher values build a Leptonica illumination model from a thumbnail
whose longest side is at most 512 pixels. Dark and chromatic foreground is
excluded from that paper model. A local threshold field distinguishes print
from broad shadows and folds by local contrast. At the default 50, correction
and one-bit foreground separation use their balanced strengths; larger values
classify more nearly neutral content for the monochrome layer. The user can optionally select a
52-point screen area in the original preview. The fixed screen size means that
zooming into a page gives a more precise paper sample. Up to three dominant
light paper colors are learned from that area, while dark ink is rejected; the
sample can apply to the whole document or one page and can be reset to Automatic.
Suitable color scans become a form containing a sparse color image at the
selected preset resolution and a neutral foreground selector at up to 300 ppi,
stored as one-bit CCITT Group 4. The original page content streams are retained,
so visible and invisible/OCR text remains PDF text. Full image samples are
decoded, normalized, resampled and encoded through bounded row buffers and
file-backed intermediates on both macOS and iOS.

Each option change invalidates the old size and candidate immediately. A short
coalescing delay prepares the visible page using the whole document's image
placement analysis; a complete PDF follows after about 400 ms. Only the current
complete result has an adoptable size. Even a larger result is offered explicitly,
since mandatory metadata/attachment/profile removal must not silently fall back
to the original. macOS/wide iPad compare synchronized page, zoom and scroll;
compact screens toggle between original and result.

Some color structures intentionally fail with an explanation instead of losing
content: profiled transparency/shadings/patterns, overprint, colored Type 3 glyphs
whose programs must remain unchanged, conflicting inherited form/image color
contexts, special non-painting colorants, unavailable external output profiles,
color-key/preblended/embedded JPX alpha masks, and unsupported technical masks.
Advanced JPX box structures and indefinite-length JBIG2 metadata also require
additional handling. The source remains intact on these failures. These are
explicit implementation limits, not silent conversions or whole-page fallbacks.

## Xcode build from vendored sources

The project build requires only a full Xcode installation with the requested
SDKs. It performs no network access, invokes no Homebrew program, downloads no
tool and installs nothing. Tested with Xcode 27 Beta 6 (27A5252f). This does not
establish compatibility with earlier Xcode releases. Deployment targets are
macOS 15 and iOS 26; target SDK libraries provide zlib, libxml2 and Accelerate.

`Vendor/PDFProcessing` contains original upstream `.tar.gz` source archives and
no compiled libraries or object files. Each component has its own directory.
Like the existing Ghostscript build, Xcode passes directory paths rather than
archive filenames. The build accepts exactly one `*.tar.gz` in each component
directory, so an upstream archive can be replaced without changing an Xcode
setting or script constant. The human-readable download inventory is
`Vendor/SOURCE_ARCHIVES.md`.

`BuildSupport/Scripts/build_pdf_for_xcode.sh` extracts the archives below
`PROJECT_TEMP_DIR`, applies the checked-in text patch and invokes the accompanying
Makefile. It uses `xcrun` to select Apple clang, clang++, ld, libtool, nmedit and
lipo. The archive contents, build recipe, native wrapper sources, SDK, compiler,
platform and architecture form the cache key. These hashes select reusable build
artifacts; they are not a fixed checksum allowlist. Replacing an archive therefore
invalidates the matching cache automatically. V8, XFA and Skia are disabled;
existing Brotli data remains decodable.

Third-party compiler and archiver output uses the same diagnostic rewrite as
the existing Ghostscript build: upstream `warning:` labels remain visible as
`warn:` in the raw log but do not become issues in Xcode's navigator. The
iPS2PDF native sources use a separate, unfiltered compile rule, and the normal
Xcode warning settings remain enabled for all project-owned C, C++ and Swift
sources. App Intents metadata extraction is skipped because the project has no
App Intents sources or shortcut metadata.

```sh
xcodebuild -project iPS2PDF.xcodeproj -scheme 'iPS2PDF MacOS' \
  -configuration Release -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build
xcodebuild -project iPS2PDF.xcodeproj -scheme 'iPS2PDF iOS' \
  -configuration Release -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

## Acceptance evidence

Native tests cover font-program preservation at all three levels, missing
fonts, inline images, repeated image PPI, one-bit Group 4 at odd widths and
threshold endpoints, identical full/page-preview image payloads, ICC conversion,
invoice/attachment action cleanup, black text/white knockouts, default form
appearances, and metadata/container round trips with identical decoded pixels.
Structural tests cover hidden content, forms/tags/comments/replies, embedded
file/profile payloads, minimal A/UA/X metadata, signature appearances, encrypted
full rewrites and wrong/empty/Unicode passwords. Failure tests check exclusive
output, cancellation, time/size limits and partial-file cleanup. The isolation
proof also links and runs with the project's actual Ghostscript archive.

Swift tests exercise immutable input, atomic inspector replacement, undo/redo,
stale asynchronous page/full results, frozen compression input, larger candidates,
concurrent edits, password retention and real helper wire encoding/decoding.
The macOS PDFKit view test checks synchronized page/zoom/scroll and usable compact
viewports with actual PDFs. PDFKit and independent Poppler rendering verify
signature appearances and processed PDFs.

The private desktop test `Fremen.pdf` was 1,491,412 bytes, including a 1,468,004-byte
compressed ISO Coated v2 output profile. Color compression produced **17,478
bytes (98.83% smaller)**; black-and-white produced **17,459 bytes**. Both contain
no ICC, Info or XMP. Page boxes and all non-color content operators are identical;
rendering preserves the vector geometry and white lettering. The dark color
changes slightly through actual color conversion. Metadata-only with PDF/X-4
retained produces **1,488,386 bytes** and retains the exact decoded ICC bytes.
The original file's SHA-256 is unchanged. This private PDF is not a repository
fixture or source-package content.

Source builds cover macOS arm64/x86_64, iOS arm64 and simulator arm64. Earlier
native proofs ran on Apple Silicon and under Rosetta. The final native suite and
macOS UI tests run on Apple Silicon. iOS compilation does not establish physical
phone/tablet acceptance: the attempted simulator startup stalled and was stopped.
The helper contract test uses the real codec/handler/native runtime in one
process; it does not claim an end-to-end test of a launched XPC service.

Useful entry points are `test_pdf_editing_macos.sh`,
`test_pdf_processing_ipc_macos.sh`,
`test_pdf_compression_macos.sh`, `test_pdf_compression_view_macos.sh`, and
`test_pdf_information_layout_macos.sh`; their arguments specify scratch paths
and, when needed, built native frameworks or synthetic native fixture outputs.

## Measured Release bundle sizes

Unsigned Release builds of both complete apps succeeded on 2026-09-06. Logical
file sizes exclude duplicate framework symlinks and include existing Ghostscript
and app resources:

| Product | Bytes | Decimal MB |
| --- | ---: | ---: |
| Complete universal macOS app (Apple Silicon + Intel) | 204,203,415 | 204.2 |
| New universal macOS PDF framework, including notices | 25,920,315 | 25.9 |
| Its Apple Silicon executable slice | 5,345,288 | 5.3 |
| Its Intel executable slice | 20,347,184 | 20.3 |
| Complete iOS arm64 app | 146,702,290 | 146.7 |

The iOS helper statically contains both Ghostscript and PDF processing; its
34,008,872-byte executable is not the size increase from this change. Native
PDF notices occupy 208,372 bytes. These are local, uncompressed bundle sizes,
not estimates of Apple's compressed/thinned TestFlight downloads. Vendored
source archives, extracted source, objects and intermediate libraries are not
copied into either app. Build intermediates remain below Xcode's build directory.

## Licenses and corresponding source

The Xcode source build collects 22 components' exact license texts and copyright
notices from the extracted archives. Missing required notices fail the build.
The generated `source-archives.txt` records the selected filenames and content
hashes. These resources are available from the compression view's Licenses
button, the macOS app menu and iOS advanced settings. Existing Ghostscript
notices remain required and unchanged.

Hyper Compress retains its AGPLv3 license; each dependency retains its own
license/notices, and the app's existing AGPL license remains unchanged. The
[AGPLv3 text](https://www.gnu.org/licenses/agpl-3.0.html) is authoritative. The
published repository contains the upstream source archives, the complete Apple
build recipe, the PDFium patch and the native iPS2PDF sources needed to reproduce
the runtime. A binary release must provide the matching corresponding source.
The build scripts do not publish or upload an app.
