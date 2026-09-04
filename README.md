# iPS2PDF

iPS2PDF converts files to PDF with a statically linked Ghostscript library. Its iOS and iPadOS interface uses SwiftUI; the MacOS app uses AppKit. On iOS, a file can be selected inside the app or sent to it through **Open with iPS2PDF**; selected PostScript text can also be handed to the lightweight Share Extension. On MacOS, files can be opened from Finder, dropped onto the app icon, or selected with **File > Open**. Every MacOS conversion gets an independent PDF document window.

Ghostscript never runs in either main app process. iOS delegates it to the existing ExtensionKit helper; MacOS embeds a private XPC service. The MacOS Quick Look extensions execute Ghostscript directly through the same bridge because they cannot use the app's XPC service. The app and the relevant helper stage exactly one current job in their shared App Group, while a FIFO coordinator serializes requests from multiple MacOS document windows. XPC carries control metadata, not document payloads.

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

The `GHOSTSCRIPT_ARCHIVE_PATH` build settings of the Ghostscript aggregate targets point to `Vendor/Ghostscript`. The build scripts resolve the single `*.tar.gz` archive in that directory, so Ghostscript upgrades only require replacing the archive.

The archive does not need to be unpacked manually and no unpacked Ghostscript tree belongs in the repository. `Build Ghostscript` extracts it into a disposable directory, creates a patched working copy of Ghostscript's official iOS build script, and publishes the iOS artifacts under `$(PROJECT_TEMP_DIR)/GhostscriptArtifacts/`. `Build Ghostscript MacOS` does the same with the upstream `toolbin/macos_build_uni_dylib.sh`: it copies and applies the small deterministic `Scripts/ghostscript_MacOS_static.patch`, builds static `arm64` and `x86_64` slices with the selected Xcode SDK and a MacOS 15 deployment target, then combines them into a universal `libgs.a`. The original `.tar.gz` remains unchanged.

Xcode input/output dependency analysis and the build scripts' content fingerprints reuse unchanged artifacts. Changing the archive, build script, patch, SDK, or deployment target rebuilds the affected variant; deleting Derived Data forces a complete rebuild.

The iOS `iPS2PDFSecurity` helper links the generated iOS `libgs.a` as before. Bundled Joboptions are installed in the iOS app, while bundled ICC profiles and Ghostscript runtime resources are installed only in `iPS2PDFSecurity.appex`. The app obtains the bundled profile catalogue from the helper over XPC and does not carry a second copy of the profile files. On MacOS, `GhostscriptRuntime.framework` alone links the universal `libgs.a`; the app, XPC service, Preview Extension, and Thumbnail Extension dynamically link that framework. The app embeds exactly one framework copy under `Contents/Frameworks`. All bundled Joboptions, ICC profiles, and Ghostscript definition files are installed only in the framework resources. The App Group contains only the current handoff and conversion job in `ShareInbox`, `ConversionInput`, and `ConversionOutput`. Persistent user Joboptions and ICC profiles remain in the main app's private Application Support directory. The Share Extension is iOS-only; the MacOS app does not embed it.

Open `iPS2PDF.xcodeproj` and select either the `iPS2PDF iOS` scheme for iOS/iPadOS or `iPS2PDF MacOS` for MacOS. The first build takes longer because it compiles Ghostscript; subsequent builds reuse the generated library.

The MacOS app and XPC service use the existing `group.de.cafe-megabyte.iPS2PDF` App Group. Their bundle identifiers and App Group access must be registered for the selected development team so Xcode can create valid development or distribution profiles. A code-signing identity is also required for an end-to-end sandboxed run.

## MacOS Quick Look

The Preview and Thumbnail Extensions declare only `com.adobe.postscript` and `com.adobe.encapsulated-postscript`. Both use the bundled `Normal.joboptions` and bundled ICC profiles from `GhostscriptRuntime.framework`; they do not access user profiles, user Joboptions, the App Group, or the XPC service.

The Preview Extension returns a PDF containing every page. The Thumbnail Extension asks Ghostscript for page 1 only, then lets Core Graphics draw that PDF page at the requested thumbnail size. Both paths extract the effective `AutoPositionEPSFiles` value from the Joboptions. When it is `true`, the bridge adds `-dEPSCrop`, so EPS output respects its bounding box. The same extraction and bridge behavior applies to normal app conversions on iOS and MacOS.

## Joboptions editing

Joboptions are parsed and edited losslessly. The shared editor identifies values by nested PostScript key paths, preserves the source encoding and all bytes outside the changed value, and supports literal as well as hexadecimal strings. Composite controls such as page ranges, image compression and quality, image policies, PDF standards, and page-box rules are implemented once as UI-independent semantic changes.

Before conversion, one shared consistency engine computes the exact effective Joboptions and reports every proposed repair. Conversion never performs a second hidden adjustment. On iOS, edits and repairs are saved immediately. On MacOS, the AppKit Distiller-style editor writes to an isolated temporary working copy; **OK** commits it atomically and **Cancel** discards every staged edit and repair.

Missing Boolean values display Yes or No. Menus and numeric fields in Standards and Additional display concrete defaults rather than a disappearing “not set” option; profile menus use “None” for no explicit profile override. Missing free-text fields are empty, without a placeholder. Displaying or refreshing any of these values never inserts a key. User edits write explicit values, including empty strings. Standard-dependent defaults and every consistency repair come from `JoboptionsConsistencyEngine`; stored conflicting values remain visible and editable with a highlighted row.

The runtime forwards pdfwrite device parameters such as `PDFACompatibilityPolicy`, `ProcessColorModel`, `BlendConversionStrategy`, and encryption values with `setpagedevice`, because `setdistillerparams` ignores those keys. Resolved output, graphics, image and text ICC paths use the same device interface (`GraphicICCProfile` maps to Ghostscript's `VectorICCProfile`). PDF/A policy defaults are supplied by the consistency engine rather than hardcoded in the C bridge. Preserved Adobe-only settings such as `DSCReportingLevel` are not assigned an invented Ghostscript default.

The **Additional** category contains an app-owned switch for embedding the selected output-intent ICC profile. The intent selection is the Joboptions value `PDFXOutputIntentProfile`, including for normal PDF and PDF/A; Ghostscript's separate `OutputICCProfile` remains the color-conversion output profile. Normal PDF and PDF/A honor the switch; PDF/X forces it on in the effective conversion snapshot without silently rewriting the stored Joboptions. The PDF/X output-condition identifier is derived from the selected printer profile when its ICC `targ` metadata provides a registered characterization reference; known bundled legacy profiles use explicit fallback mappings, and otherwise the effective identifier is the user's nonempty value or `Custom`. The Standards UI displays these effective values while only direct user edits and explicit consistency repairs modify the stored Joboptions. Ghostscript's PDF/X definition is patched per job with the effective identifier, optional condition and registry, profile display name, and a valid `Trapped` value.

## Project organization

All compiled product sources and app resources live under the single physical `Sources` directory. Xcode's navigator mirrors the physical hierarchy with folder-backed structural groups and blue, file-system-synchronized component folders:

```text
Sources/
├── Shared/
│   ├── AppCore/
│   │   ├── Conversion/
│   │   ├── Incoming/
│   │   ├── Joboptions/
│   │   ├── Models/
│   │   └── Storage/
│   ├── GhostscriptClient/
│   ├── GhostscriptRuntime/
│   │   ├── GhostscriptBridge/
│   │   ├── Profiles/
│   │   ├── RequestHandling/
│   │   └── Resources/
│   ├── IPC/
│   ├── MacOSGhostscriptRuntime/
│   └── Resources/
└── Targets/
    ├── iOSApp/
    │   └── AppUI/
    ├── iOSShareExtension/
    ├── iOSGhostscriptExtension/
    ├── MacOSApp/
    │   └── Settings/
    ├── MacOSGhostscriptRuntime/
    ├── MacOSGhostscriptXPC/
    ├── MacOSQuickLookPreview/
    └── MacOSThumbnailExtension/
BuildSupport/
└── Targets/        # Info.plist and entitlements, not target members
Tests/
├── Unit/
└── Integration/
```

`Sources`, `Shared`, `AppCore`, `GhostscriptRuntime`, `IPC`, `Resources`, `Targets`, and `Tests` are stable structural groups backed by the corresponding directories. Their synchronized child folders are the build-membership units: additions and moves inside one of these blue folders follow the file system automatically. Selecting such a folder in Xcode's File inspector shows its complete target membership. Adding a new component requires adding one new synchronized folder reference; adding files below an existing component does not modify the project file.

The shared component memberships are intentionally folder-granular:

| Component | Consumers |
| --- | --- |
| `AppCore/Conversion`, `Incoming`, `Models` | iOS app, MacOS app, unit tests |
| `AppCore/Joboptions` | iOS app, MacOS app, Quick Look, Thumbnail, unit tests |
| `AppCore/Storage`, `GhostscriptClient`, `Resources/App` | iOS app, MacOS app |
| `Targets/iOSApp/AppUI` | iOS app |
| `Targets/MacOSApp/Settings` | MacOS app |
| `GhostscriptRuntime/GhostscriptBridge` | iOS Ghostscript extension, MacOS runtime framework |
| `GhostscriptRuntime/Profiles` | iOS Ghostscript extension, MacOS XPC, Quick Look, Thumbnail |
| `GhostscriptRuntime/RequestHandling` | iOS Ghostscript extension, MacOS XPC |
| `GhostscriptRuntime/Resources` | both apps, iOS Ghostscript extension, MacOS XPC, Quick Look, Thumbnail |
| `IPC/AppGroup` | both apps, Share/Ghostscript helpers, unit tests |
| `IPC/GhostscriptControl` | both apps and their Ghostscript helpers |
| `IPC/iOSShare` | iOS app, Share extension, unit tests |
| `IPC/MacOSXPC` | MacOS app, MacOS XPC |
| `MacOSGhostscriptRuntime` | Quick Look, Thumbnail |

Targets reference only the synchronized component folders they compile. The project uses neither source-name include/exclude filters, synchronized-folder membership exceptions, nor per-file source memberships. Each synchronized folder has exactly one place in the navigator, so Xcode does not need a `Recovered References` group. Each Swift file contains at most one top-level nominal type. Project-owned platform names consistently use `MacOS`; Apple-defined tokens such as `#if os(macOS)`, `SDKROOT = macosx`, and `MACOSX_DEPLOYMENT_TARGET` retain Apple's spelling.

The project remains in the Xcode 26 project format and does not use Xcode 27-only synchronized-folder object types.

## Tested configuration

- Ghostscript 10.07.1
- Project compatibility: Xcode 26
- Deployment target: iOS/iPadOS 26.0 or newer
- MacOS deployment target: MacOS 15.0 or newer
- MacOS architectures: Apple silicon (`arm64`) and Intel (`x86_64`)
- MacOS XPC service launch and request/reply handshake verified in a separate process
- MacOS Preview Extension: all-page PDF output for PostScript and EPS
- MacOS Thumbnail Extension: first-page output with EPS bounding-box cropping
- Ghostscript sample: `examples/colorcir.ps`
- Verified output: PDF 1.2, PDF 1.3, and PDF 1.4, validated with PDFKit

## License

The entire project—including the Swift app, C bridge, build and patcher scripts, and the integrated Ghostscript code—is licensed under the **GNU Affero General Public License, version 3 or later (AGPL-3.0-or-later)**.

Ghostscript and its included third-party components retain their original copyright, license notices, compatible exceptions, and additional terms as documented in the upstream source tree.
