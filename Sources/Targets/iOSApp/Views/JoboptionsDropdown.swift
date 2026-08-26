import SwiftUI

struct JoboptionsDropdown: View {
    @ObservedObject var repository: JoboptionsRepository
    let isDisabled: Bool

    var body: some View {
        Menu {
            Section("Bundled") {
                ForEach(repository.records.filter(\.isBundled)) { record in
                    recordButton(record)
                }
            }
            Section("User") {
                ForEach(repository.records.filter { !$0.isBundled }) { record in
                    recordButton(record)
                }
            }
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
        .disabled(isDisabled || !repository.isReady)
    }

    private func recordButton(_ record: JoboptionsRecord) -> some View {
        Button {
            do { try repository.activate(record) }
            catch { repository.lastError = error.localizedDescription }
        } label: {
            if repository.activeRecord?.id == record.id {
                Label(record.name, systemImage: "checkmark")
            } else {
                Text(record.name)
            }
        }
    }
}
