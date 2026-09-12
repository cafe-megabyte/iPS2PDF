import AppKit
import SwiftUI

@MainActor
final class MacOSStartWindowController: NSWindowController {
    init(
        model: MacOSApplicationModel,
        onEditJoboptions: @escaping () -> Void,
        onManageJoboptions: @escaping () -> Void,
        onShowGhostscriptSettings: @escaping () -> Void
    ) {
        let initialContentSize = NSSize(width: 400, height: 830)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        let rootView = MacOSStartView(
            repository: model.joboptionsRepository,
            onEditJoboptions: onEditJoboptions,
            onManageJoboptions: onManageJoboptions,
            onShowGhostscriptSettings: onShowGhostscriptSettings,
            onShowPDFInfo: { [weak window] in
                MacOSPDFInfoWindowController.openPanel(parentWindow: window)
            },
            onOpenFile: { [weak window] in
                model.presentOpenPanel(
                    purpose: .conversion,
                    parentWindow: window
                )
            },
            onOpenPostScriptFile: { [weak window] in
                model.postScriptExportController.presentOpenPanel(
                    parentWindow: window
                )
            },
            onEncryptPostScriptFile: { [weak window] in
                model.postScriptEncryptionController.presentOpenPanel(
                    parentWindow: window
                )
            }
        )

        window.title = "iPS2PDF"
        window.contentViewController = NSHostingController(rootView: rootView)
        window.setContentSize(initialContentSize)
        window.minSize = NSSize(width: 620, height: 680)
        window.isReleasedWhenClosed = false
        window.isExcludedFromWindowsMenu = true
        window.center()
        window.setFrameAutosaveName("iPS2PDFStartWindow.large")

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func present() {
        guard let window else { return }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
