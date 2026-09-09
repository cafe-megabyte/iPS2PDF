import AppKit
import PDFKit

@MainActor
enum MacOSPDFWindowSizing {
    struct Configuration {
        let initialContentSize: NSSize
        let minimumWindowSize: NSSize
        let pagePadding: NSSize
        let maximumContentHeightOnLargeDisplays: CGFloat
        let maximumScreenWidthFraction: CGFloat
    }

    static let convertedDocument = Configuration(
        initialContentSize: NSSize(width: 860, height: 700),
        minimumWindowSize: NSSize(width: 440, height: 360),
        pagePadding: NSSize(width: 80, height: 80),
        maximumContentHeightOnLargeDisplays: 980,
        maximumScreenWidthFraction: 0.92
    )

    static let signatureEditor = Configuration(
        initialContentSize: NSSize(width: 860, height: 700),
        minimumWindowSize: NSSize(width: 680, height: 500),
        pagePadding: NSSize(width: 100, height: 200),
        maximumContentHeightOnLargeDisplays: 980,
        maximumScreenWidthFraction: 0.92
    )

    static func prepare(
        _ window: NSWindow,
        forPDFAt url: URL,
        configuration: Configuration,
        centerAfterResizing: Bool = false
    ) {
        window.setContentSize(configuration.initialContentSize)
        window.minSize = configuration.minimumWindowSize
        resize(window, forFirstPageOf: url, configuration: configuration)
        if centerAfterResizing { window.center() }
    }

    static func resize(
        _ window: NSWindow,
        forFirstPageOf url: URL,
        configuration: Configuration
    ) {
        guard let document = PDFDocument(url: url),
              let firstPage = document.page(at: 0),
              let screen = window.screen ?? NSScreen.main
        else { return }

        let pageBounds = firstPage.bounds(for: .cropBox)
        guard pageBounds.width > 0, pageBounds.height > 0 else { return }

        let visibleFrame = screen.visibleFrame
        let currentTopLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        let contentFrame = window.contentRect(forFrameRect: window.frame)
        let frameInsetWidth = window.frame.width - contentFrame.width
        let frameInsetHeight = window.frame.height - contentFrame.height

        let availableFrameWidth = max(
            configuration.minimumWindowSize.width,
            visibleFrame.maxX - currentTopLeft.x
        )
        let availableFrameHeight = max(
            configuration.minimumWindowSize.height,
            currentTopLeft.y - visibleFrame.minY
        )
        let maximumFrameHeight = min(
            availableFrameHeight,
            configuration.maximumContentHeightOnLargeDisplays + frameInsetHeight
        )
        let maximumContentSize = NSSize(
            width: max(
                configuration.minimumWindowSize.width - frameInsetWidth,
                min(availableFrameWidth, visibleFrame.width * configuration.maximumScreenWidthFraction) - frameInsetWidth
            ),
            height: max(
                configuration.minimumWindowSize.height - frameInsetHeight,
                maximumFrameHeight - frameInsetHeight
            )
        )

        let availablePageWidth = maximumContentSize.width - configuration.pagePadding.width
        let availablePageHeight = maximumContentSize.height - configuration.pagePadding.height
        let scale = min(
            1.0,
            availablePageWidth / pageBounds.width,
            availablePageHeight / pageBounds.height
        )

        let targetContentSize = NSSize(
            width: min(
                maximumContentSize.width,
                max(
                    configuration.minimumWindowSize.width - frameInsetWidth,
                    pageBounds.width * scale + configuration.pagePadding.width
                )
            ),
            height: min(
                maximumContentSize.height,
                max(
                    configuration.minimumWindowSize.height - frameInsetHeight,
                    pageBounds.height * scale + configuration.pagePadding.height
                )
            )
        )
        setContentSizePreservingTopLeft(targetContentSize, for: window)
    }

    private static func setContentSizePreservingTopLeft(_ contentSize: NSSize, for window: NSWindow) {
        let currentTopLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        let targetFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize))
        let targetOrigin = NSPoint(
            x: currentTopLeft.x,
            y: currentTopLeft.y - targetFrame.height
        )
        window.setFrame(NSRect(origin: targetOrigin, size: targetFrame.size), display: true)
    }
}
