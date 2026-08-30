import SwiftUI

struct JoboptionsDropdown: View {
    @ObservedObject var repository: JoboptionsRepository
    let isDisabled: Bool

    var body: some View {
        Menu {
            ForEach(userRecords.reversed()) { record in
                recordButton(record)
            }
            menuHeader("User")

            ForEach(otherBundledRecords.reversed()) { record in
                recordButton(record)
            }
            if normalRecord != nil, !otherBundledRecords.isEmpty {
                Divider()
            }
            if let normalRecord {
                recordButton(normalRecord)
            }
            menuHeader("Bundled")
        } label: {
            HStack(spacing: 10) {
                Image(systemName: repository.activeRecord?.isBundled == true ? "shippingbox.fill" : "person.crop.circle")
                    .frame(width: 22)
                Text(repository.activeName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .disabled(isDisabled)
        .allowsHitTesting(!isDisabled && repository.isReady)
    }

    private var bundledRecords: [JoboptionsRecord] {
        repository.records.filter(\.isBundled)
    }

    private var normalRecord: JoboptionsRecord? {
        bundledRecords.first { $0.name == "Normal" }
    }

    private var otherBundledRecords: [JoboptionsRecord] {
        bundledRecords.filter { $0.name != "Normal" }
    }

    private var userRecords: [JoboptionsRecord] {
        repository.records.filter { !$0.isBundled }
    }

    private func menuHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .foregroundStyle(.secondary)
    }

    private func recordButton(_ record: JoboptionsRecord) -> some View {
        Button {
            do { try repository.activate(record) }
            catch { repository.lastError = error.localizedDescription }
        } label: {
            Text(repository.activeRecord?.id == record.id ? "✓ \(record.name)" : record.name)
        }
    }
}
