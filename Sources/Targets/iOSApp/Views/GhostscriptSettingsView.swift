import SwiftUI

struct GhostscriptSettingsView: View {
    @ObservedObject var settings: GhostscriptRuntimeSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Ghostscript") {
                    Toggle("Security limits", isOn: $settings.securityLimitsEnabled)
                    Text("Enabled by default: 15 minutes, 1 GB input and 2 GB output. Process isolation, SAFER, diagnostics and cancellation always remain active.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Toggle("Automatic random seed", isOn: Binding(
                        get: { settings.automaticRandomSeed },
                        set: { settings.setAutomaticRandomSeed($0) }
                    ))

                    if !settings.automaticRandomSeed {
                        LabeledContent("Seed") {
                            TextField(
                                "Seed",
                                value: Binding(
                                    get: { settings.manualRandomSeed },
                                    set: { settings.setManualRandomSeed($0) }
                                ),
                                formatter: Self.seedFormatter
                            )
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                        }
                        Text(Self.randomSeedRangeDescription)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Ghostscript")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private static let seedFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.allowsFloats = false
        formatter.minimum = NSNumber(value: PostScriptRandomSeedSettings.range.lowerBound)
        formatter.maximum = NSNumber(value: PostScriptRandomSeedSettings.range.upperBound)
        return formatter
    }()

    private static var randomSeedRangeDescription: String {
        String(
            format: String(localized: "Allowed range: %@ - %@"),
            seedFormatter.string(
                from: NSNumber(value: PostScriptRandomSeedSettings.range.lowerBound)
            ) ?? String(PostScriptRandomSeedSettings.range.lowerBound),
            seedFormatter.string(
                from: NSNumber(value: PostScriptRandomSeedSettings.range.upperBound)
            ) ?? String(PostScriptRandomSeedSettings.range.upperBound)
        )
    }
}
