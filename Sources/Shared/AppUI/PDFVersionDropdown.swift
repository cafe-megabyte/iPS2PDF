import SwiftUI

struct PDFVersionDropdown: View {
    let selectedVersion: PDFVersion
    let isDisabled: Bool
    let onSelect: (PDFVersion) -> Void

    var body: some View {
        Menu {
            ForEach(PDFVersion.allCases.reversed()) { version in
                Button {
                    onSelect(version)
                } label: {
                    menuItemTitle(for: version)
                    if let detail = version.detail {
                        Text(verbatim: detail)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(verbatim: selectedVersion.title)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    @ViewBuilder
    private func menuItemTitle(for version: PDFVersion) -> some View {
        if version.isHighlighted {
            Label {
                Text(verbatim: version.title)
            } icon: {
                Image(systemName: "star.fill")
            }
        } else {
            Text(verbatim: version.title)
        }
    }
}
