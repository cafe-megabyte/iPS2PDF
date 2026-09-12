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
    private var startWindowController: MacOSStartWindowController?
    private var startWindowMenuItem: NSMenuItem?
    private var settingsWindowController: NSWindowController?
    private var joboptionsEditorWindowController: NSWindowController?
    private var joboptionsManagementWindowController: NSWindowController?
    private var pdfLicensesWindowController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? MacOSDocumentWorkspace.clearStaleDirectories()
        JoboptionsEditingSession.cleanupStaleDirectories()
        try? PDFInspectionInput.clearStaleDirectories()
        try? AppGroupWorkspace.clearStaleDataPreservingShareInbox()
        installStartWindowMenuItem()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard NSDocumentController.shared.documents.isEmpty,
                  !NSApp.windows.contains(where: \.isVisible)
            else { return }
            self?.showStartWindow(nil)
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            showStartWindow(nil)
        }
        return true
    }

    @IBAction func showStartWindow(_ sender: Any?) {
        if startWindowController == nil {
            startWindowController = MacOSStartWindowController(
                model: MacOSApplicationModel.shared,
                onEditJoboptions: { [weak self] in
                    self?.showJoboptionsEditor()
                },
                onManageJoboptions: { [weak self] in
                    self?.showJoboptionsManagement()
                },
                onShowGhostscriptSettings: { [weak self] in
                    self?.showSettings(nil)
                }
            )
        }
        startWindowController?.present()
    }

    @IBAction func openFile(_ sender: Any?) {
        MacOSApplicationModel.shared.presentOpenPanel()
    }

    @IBAction func openConversionDocument(_ sender: Any?) {
        MacOSApplicationModel.shared.presentOpenPanel(purpose: .conversion)
    }

    @IBAction func openPostScriptConversion(_ sender: Any?) {
        MacOSApplicationModel.shared.postScriptExportController.presentOpenPanel()
    }

    @IBAction func exportCurrentAsPostScript(_ sender: Any?) {
        MacOSApplicationModel.shared.postScriptExportController.exportCurrent()
    }

    @IBAction func encryptPostScript(_ sender: Any?) {
        MacOSApplicationModel.shared.postScriptEncryptionController.presentOpenPanel(
            parentWindow: NSApp.keyWindow
        )
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
            runtimeSettings: MacOSApplicationModel.shared.runtimeSettings
        )
        let window = NSWindow(contentViewController: viewController)
        window.title = String(localized: "Ghostscript settings")
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
        if menuItem.action == #selector(openPostScriptConversion(_:)) {
            return !MacOSApplicationModel.shared.postScriptExportController.isProcessing
        }
        if menuItem.action == #selector(exportCurrentAsPostScript(_:)) {
            return MacOSApplicationModel.shared.postScriptExportController.canExportCurrent
        }
        if menuItem.action == #selector(encryptPostScript(_:)) {
            return MacOSApplicationModel.shared.postScriptEncryptionController.canPresent
        }
        guard menuItem.action == #selector(prepareContainerReset(_:)) else { return true }
        return MacOSApplicationModel.shared.activeConversionCount == 0
    }

    private func installStartWindowMenuItem() {
        guard startWindowMenuItem == nil, let menu = NSApp.windowsMenu else { return }
        let item = NSMenuItem(
            title: String(localized: "Show Start Window"),
            action: #selector(showStartWindow(_:)),
            keyEquivalent: ""
        )
        item.target = self
        menu.insertItem(item, at: 0)
        menu.insertItem(.separator(), at: 1)
        startWindowMenuItem = item
    }

    private func showJoboptionsEditor() {
        guard let parentWindow = startWindowController?.window else { return }
        if let window = joboptionsEditorWindowController?.window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let repository = MacOSApplicationModel.shared.joboptionsRepository
        do {
            let session = try JoboptionsEditingSession(repository: repository)
            let viewController = MacOSDistillerEditorViewController(
                session: session,
                repository: repository
            )
            let window = NSWindow(contentViewController: viewController)
            window.title = String.localizedStringWithFormat(
                String(localized: "PDF settings: %@"),
                repository.activeName
            )
            window.setContentSize(NSSize(width: 900, height: 670))
            window.minSize = NSSize(width: 760, height: 560)
            window.styleMask = [.titled, .closable, .resizable]
            window.isReleasedWhenClosed = false

            joboptionsEditorWindowController = NSWindowController(window: window)
            viewController.onFinish = { [weak self, weak parentWindow, weak window] commits in
                guard let self else { return }
                if commits {
                    try session.commit()
                } else {
                    session.cancel()
                }
                if let window, let parentWindow {
                    parentWindow.endSheet(window)
                }
                joboptionsEditorWindowController = nil
            }
            parentWindow.beginSheet(window)
        } catch {
            present(error, asSheetFor: parentWindow)
        }
    }

    private func showJoboptionsManagement() {
        guard let parentWindow = startWindowController?.window else { return }
        if let window = joboptionsManagementWindowController?.window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let viewController = MacOSJoboptionsManagementViewController(
            repository: MacOSApplicationModel.shared.joboptionsRepository
        )
        let window = NSWindow(contentViewController: viewController)
        window.title = String(localized: "Manage Joboptions")
        window.setContentSize(NSSize(width: 700, height: 520))
        window.minSize = NSSize(width: 620, height: 430)
        window.styleMask = [.titled, .closable, .resizable]
        window.isReleasedWhenClosed = false

        joboptionsManagementWindowController = NSWindowController(window: window)
        viewController.onFinish = { [weak self, weak parentWindow, weak window] in
            guard let self else { return }
            if let window, let parentWindow {
                parentWindow.endSheet(window)
            }
            joboptionsManagementWindowController = nil
        }
        parentWindow.beginSheet(window)
    }

    private func present(_ error: Error, asSheetFor parentWindow: NSWindow) {
        NSAlert(error: error).beginSheetModal(for: parentWindow)
    }
}
