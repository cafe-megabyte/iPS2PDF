import AppKit

@MainActor
final class PDFInformationRowView: NSTableRowView {
    var isProblem = false
    var emphasis: PDFInfoFieldEmphasis?

    override func drawBackground(in dirtyRect: NSRect) {
        let effectiveEmphasis: PDFInfoFieldEmphasis? = isProblem ? .warning : emphasis
        guard let effectiveEmphasis else {
            super.drawBackground(in: dirtyRect)
            return
        }
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 6, yRadius: 6)
        effectiveEmphasis.backgroundColor.setFill()
        path.fill()
        effectiveEmphasis.borderColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

@MainActor
private extension PDFInfoFieldEmphasis {
    var color: NSColor {
        switch self {
        case .standardDeclaration: .systemIndigo
        case .warning: .systemOrange
        }
    }

    var backgroundColor: NSColor {
        switch self {
        case .standardDeclaration: color.withAlphaComponent(0.14)
        case .warning: MacOSPDFReportSharing.warningColor
        }
    }

    var borderColor: NSColor {
        switch self {
        case .standardDeclaration: color.withAlphaComponent(0.50)
        case .warning: color.withAlphaComponent(0.62)
        }
    }

}
