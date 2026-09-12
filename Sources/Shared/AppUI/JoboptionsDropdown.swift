import SwiftUI

struct JoboptionsDropdown: View {
    @ObservedObject var repository: JoboptionsRepository
    let isDisabled: Bool
    let onManage: (() -> Void)?

    var body: some View {
        Menu {
            ForEach(userRecords.reversed()) { record in
                recordButton(record)
            }
            menuHeader(LocalizedStringResource("User"))

            ForEach(otherBundledRecords.reversed()) { record in
                recordButton(record)
            }
            if normalRecord != nil, !otherBundledRecords.isEmpty {
                Divider()
            }
            if let normalRecord {
                recordButton(normalRecord)
            }
            menuHeader(LocalizedStringResource("Bundled"))

            if let onManage {
                Divider()
                Button("Manage Joboptions...", systemImage: "folder") {
                    onManage()
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(verbatim: repository.activeName)
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

    private func menuHeader(_ title: LocalizedStringResource) -> some View {
        Text(title)
            .foregroundStyle(.secondary)
    }

    private func recordButton(_ record: JoboptionsRecord) -> some View {
        Button {
            do { try repository.activate(record) }
            catch { repository.lastError = error.localizedDescription }
        } label: {
            if repository.activeRecord?.id == record.id {
                Label {
                    Text(verbatim: record.name)
                } icon: {
                    Image(systemName: "checkmark")
                }
            } else {
                Text(verbatim: record.name)
            }
        }
    }
}
