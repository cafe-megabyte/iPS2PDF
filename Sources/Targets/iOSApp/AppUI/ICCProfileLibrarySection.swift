import SwiftUI

struct ICCProfileLibrarySection: View {
    @ObservedObject var repository: JoboptionsRepository
    @State private var showsImporter = false

    var body: some View {
        Section("ICC profiles") {
            LabeledContent("Available") {
                Text("\(repository.profiles.count)")
                    .foregroundStyle(.secondary)
            }
            ForEach(repository.profiles) { profile in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading) {
                        Text(profile.name)
                        Text("\(profile.profileClass) · \(profile.colorSpace) → \(profile.connectionSpace)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: profile.isBundled ? "shippingbox.fill" : "person.crop.circle")
                        .foregroundStyle(.secondary)
                    if !profile.isBundled {
                        Button(role: .destructive) {
                            do { try repository.deleteProfile(profile) }
                            catch { repository.lastError = error.localizedDescription }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            Button("Import ICC Profile…", systemImage: "square.and.arrow.down") {
                showsImporter = true
            }
        }
        .fileImporter(
            isPresented: $showsImporter,
            allowedContentTypes: [.iccProfileFile, .data],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let url = try result.get().first else { return }
                try repository.importProfile(from: url)
            } catch {
                repository.lastError = error.localizedDescription
            }
        }
    }
}
