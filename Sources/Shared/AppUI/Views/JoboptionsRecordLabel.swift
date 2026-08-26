import SwiftUI

struct JoboptionsRecordLabel: View {
    let record: JoboptionsRecord
    let isActive: Bool

    var body: some View {
        HStack {
            if record.isBundled {
                Image(systemName: "shippingbox.fill")
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "person.crop.circle")
                    .foregroundStyle(.tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(record.name)
                    .foregroundStyle(.primary)
                if record.isBundled {
                    Text("Bundled · read-only")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("User · editable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
    }
}
