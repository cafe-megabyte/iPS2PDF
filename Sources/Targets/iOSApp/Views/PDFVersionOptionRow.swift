import SwiftUI

struct PDFVersionOptionRow: View {
    let version: PDFVersion
    let showsSelection: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: version.isHighlighted ? "star.fill" : "star")
                .foregroundStyle(version.isHighlighted ? .red : .clear)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(version.title)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)

                if let detail = version.detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
            }

            Spacer(minLength: 8)

            if showsSelection {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
    }
}
