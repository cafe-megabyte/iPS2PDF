import SwiftUI

struct PDFACompatibilityDropdown: View {
    let selectedCompatibility: PDFACompatibility
    let isDisabled: Bool
    let onSelect: (PDFACompatibility) -> Void

    var body: some View {
        Menu {
            ForEach(PDFACompatibility.allCases.reversed()) { compatibility in
                Button {
                    onSelect(compatibility)
                } label: {
                    menuItemTitle(for: compatibility)
                    if let detail = compatibility.detail {
                        Text(verbatim: detail)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(verbatim: selectedCompatibility.title)
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
    private func menuItemTitle(for compatibility: PDFACompatibility) -> some View {
        if compatibility.isHighlighted {
            Label {
                Text(verbatim: compatibility.title)
            } icon: {
                Image(systemName: "star.fill")
            }
        } else {
            Text(verbatim: compatibility.title)
        }
    }
}
