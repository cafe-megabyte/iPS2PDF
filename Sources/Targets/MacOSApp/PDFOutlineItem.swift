import AppKit

@MainActor
final class PDFOutlineItem: NSObject {
    let section: PDFInfoSection?
    let field: PDFInfoField?
    let children: [PDFOutlineItem]
    init(section: PDFInfoSection) { self.section = section; field = nil; children = section.fields.map(PDFOutlineItem.init(field:)) }
    init(field: PDFInfoField) { self.field = field; section = nil; children = [] }
}
