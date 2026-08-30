import AppKit

@MainActor
@main
final class MacOSAppDelegate: NSObject, NSApplicationDelegate {
    private var waitsForConversionBeforeTermination = false
    private var settingsWindowController: NSWindowController?

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
}
