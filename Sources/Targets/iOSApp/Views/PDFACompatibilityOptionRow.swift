import SwiftUI

struct PDFACompatibilityOptionRow: View {
    let compatibility: PDFACompatibility

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: compatibility.isHighlighted ? "star.fill" : "star")
                .foregroundStyle(compatibility.isHighlighted ? .red : .clear)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(compatibility.title)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)

                if let detail = compatibility.detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
            }

            Spacer(minLength: 8)
        }
        .contentShape(Rectangle())
    }
}
