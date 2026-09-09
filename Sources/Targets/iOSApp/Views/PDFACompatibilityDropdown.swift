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
                        Text(detail)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selectedCompatibility.title)
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
            Label(compatibility.title, systemImage: "star.fill")
        } else {
            Text(compatibility.title)
        }
    }
}
