import SwiftUI

struct PDFInfoSectionView: View {
    let section: PDFInfoSection
    let fontReveal: Int
    let noticeReveal: Int
    let canExport: Bool
    let export: (PDFExtractableResource) -> Void
    @State private var expanded: Bool
    init(section: PDFInfoSection, fontReveal: Int, noticeReveal: Int,
         canExport: Bool, export: @escaping (PDFExtractableResource) -> Void) {
        self.section = section
        self.fontReveal = fontReveal
        self.noticeReveal = noticeReveal
        self.canExport = canExport
        self.export = export
        let expandsInitially = section.category != .fonts && (section.initiallyExpanded || section.warning != nil)
        let expandsForFontWarning = section.category == .fonts && section.warning != nil && fontReveal > 0
        _expanded = State(initialValue: expandsInitially || expandsForFontWarning || section.id == "analysis-notices" && noticeReveal > 0)
    }
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12) {
                if let warning = section.warning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill").font(.subheadline.bold())
                }
                ForEach(section.fields) { field in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(field.label).font(.caption).foregroundStyle(.secondary)
                        Text(field.value).font(section.id == "xmp" ? .system(.footnote, design: .monospaced) : .body).textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, field.emphasis == nil ? 0 : 5)
                    .padding(.horizontal, field.emphasis == nil ? 0 : 7)
                    .background {
                        if let emphasis = field.emphasis {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(emphasis.backgroundColor)
                        }
                    }
                    .overlay {
                        if let emphasis = field.emphasis {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(emphasis.borderColor, lineWidth: 1)
                        }
                    }
                }
            }.padding(.top, 10)
        } label: {
            HStack {
                Text(section.title).font(.headline).foregroundStyle(.primary).textSelection(.enabled)
                Spacer()
                if let resource = section.resource {
                    Button { export(resource) } label: { Image(systemName: "square.and.arrow.up") }
                        .buttonStyle(.borderless)
                        .disabled(!canExport)
                        .accessibilityLabel(String.localizedStringWithFormat(String(localized: "Export %@"), resource.kind.accessibilityName))
                        .accessibilityHint(canExport ? "" : String(localized: "The PDF does not permit content copying."))
                }
            }
        }
        .padding(14)
        .background(section.warning == nil ? Color(uiColor: .secondarySystemGroupedBackground) : Color.orange.opacity(0.20), in: RoundedRectangle(cornerRadius: 12))
        .overlay { if section.warning != nil { RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.62), lineWidth: 1) } }
        .onChange(of: noticeReveal) { _, _ in if section.id == "analysis-notices" { expanded = true } }
        .onChange(of: fontReveal) { _, _ in if section.warning != nil { expanded = true } }
    }
}

private extension PDFInfoFieldEmphasis {
    var color: Color {
        switch self {
        case .standardDeclaration: .indigo
        case .warning: .orange
        }
    }

    var backgroundColor: Color {
        switch self {
        case .standardDeclaration: color.opacity(0.14)
        case .warning: color.opacity(0.20)
        }
    }

    var borderColor: Color {
        switch self {
        case .standardDeclaration: color.opacity(0.50)
        case .warning: color.opacity(0.62)
        }
    }

}
