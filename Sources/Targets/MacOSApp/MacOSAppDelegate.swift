import AppKit
import Darwin
import SwiftUI

@MainActor
@main
final class MacOSAppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private static let resetContainerBundleIdentifiers = [
        "de.cafe-megabyte.iPS2PDF.MacOS",
        "de.cafe-megabyte.iPS2PDF.MacOS.Thumbnail",
        "de.cafe-megabyte.iPS2PDF.MacOS.QuickLook"
    ]

    private var waitsForConversionBeforeTermination = false
    private var settingsWindowController: NSWindowController?
    private var pdfLicensesWindowController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? MacOSDocumentWorkspace.clearStaleDirectories()
        JoboptionsEditingSession.cleanupStaleDirectories()
        try? AppGroupWorkspace.clearStaleDataPreservingShareInbox()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard NSDocumentController.shared.documents.isEmpty,
                  NSApp.keyWindow == nil
            else { return }
            MacOSApplicationModel.shared.presentOpenPanel()
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    @IBAction func openFile(_ sender: Any?) {
        MacOSApplicationModel.shared.presentOpenPanel()
    }

    @IBAction func openConversionDocument(_ sender: Any?) {
        MacOSApplicationModel.shared.presentOpenPanel(purpose: .conversion)
    }

    @IBAction func openPDFInformation(_ sender: Any?) {
        MacOSPDFInfoWindowController.openPanel()
    }
    @IBAction func compressPDF(_ sender: Any?) {
        MacOSPDFCompressionWindowController.openPanel()
    }
    @IBAction func showPDFProcessingLicenses(_ sender: Any?) {
        if let window = pdfLicensesWindowController?.window { window.makeKeyAndOrderFront(nil); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 620),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = String(localized: "PDF processing licenses")
        window.contentViewController = NSHostingController(rootView: PDFProcessingLicensesView(closeAction: { [weak window] in window?.close() }))
        window.isReleasedWhenClosed = false
        pdfLicensesWindowController = NSWindowController(window: window)
        window.center()
        pdfLicensesWindowController?.showWindow(nil)
    }

    @IBAction func showSettings(_ sender: Any?) {
        if let window = settingsWindowController?.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let viewController = MacOSSettingsViewController(
            repository: MacOSApplicationModel.shared.joboptionsRepository
        )
        let window = NSWindow(contentViewController: viewController)
        window.title = String(localized: "Settings")
        window.setContentSize(NSSize(width: 500, height: viewController.view.fittingSize.height))
        window.minSize = window.frame.size
        window.styleMask.formUnion([.titled, .closable, .miniaturizable])
        window.isReleasedWhenClosed = false

        let controller = NSWindowController(window: window)
        settingsWindowController = controller
        window.center()
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @IBAction func prepareContainerReset(_ sender: Any?) {
        guard MacOSApplicationModel.shared.activeConversionCount == 0 else {
            NSSound.beep()
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Reset iPS2PDF?")
        alert.informativeText = String(
            localized: "Finder will open and select the three iPS2PDF container folders. Move them to the Trash to reset the app and both extensions. iPS2PDF will quit before you delete them."
        )
        alert.addButton(withTitle: String(localized: "Show in Finder and Quit"))
        alert.addButton(withTitle: String(localized: "Cancel"))

        guard alert.runModal() == .alertFirstButtonReturn,
              let homeDirectory = getpwuid(getuid()).map({ String(cString: $0.pointee.pw_dir) })
        else { return }

        let containersDirectory = URL(fileURLWithPath: homeDirectory, isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Containers", isDirectory: true)
        let containerURLs = Self.resetContainerBundleIdentifiers.map {
            containersDirectory.appendingPathComponent($0, isDirectory: true)
        }

        NSWorkspace.shared.activateFileViewerSelecting(containerURLs)
        NSApp.terminate(nil)
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        MacOSApplicationModel.shared.openDocuments(at: urls)
        sender.reply(toOpenOrPrint: .success)
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let model = MacOSApplicationModel.shared
        guard model.activeConversionCount > 0 else { return .terminateNow }
        guard !waitsForConversionBeforeTermination else { return .terminateLater }

        waitsForConversionBeforeTermination = true
        model.performWhenConversionsFinish { [weak self, weak sender] in
            guard let self, let sender else { return }
            waitsForConversionBeforeTermination = false
            sender.reply(toApplicationShouldTerminate: false)
            DispatchQueue.main.async {
                sender.terminate(nil)
            }
        }
        return .terminateLater
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(prepareContainerReset(_:)) else { return true }
        return MacOSApplicationModel.shared.activeConversionCount == 0
    }
}
