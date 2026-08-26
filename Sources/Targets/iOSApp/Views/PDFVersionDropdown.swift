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
                        Text(detail)
                    }
                }
            }
        } label: {
            HStack(spacing: 10) {
                PDFVersionOptionRow(version: selectedVersion, showsSelection: false)

                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .disabled(isDisabled)
    }

    @ViewBuilder
    private func menuItemTitle(for version: PDFVersion) -> some View {
        if version.isHighlighted {
            Label(version.title, systemImage: "star.fill")
        } else {
            Text(version.title)
        }
    }
}
