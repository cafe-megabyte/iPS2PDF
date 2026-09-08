import SwiftUI

struct CompressionOptionsEditor: View {
    @Binding var options: PDFCompressionOptions
    let isLevelEnabled: (PDFCompressionOptions.Level) -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack { levelPicker; colorPicker }
                VStack { levelPicker; colorPicker }
            }
            if options.colorMode == .blackAndWhite {
                HStack {
                    Text("Threshold")
                    Slider(
                        value: Binding(
                            get: { Double(options.threshold) },
                            set: { options.threshold = Int($0.rounded()) }
                        ),
                        in: 0...100, step: 1
                    )
                    .accessibilityLabel("Black and white threshold")
                    Text(options.threshold.formatted())
                        .monospacedDigit()
                        .frame(width: 32, alignment: .trailing)
                }
            } else {
                HStack {
                    Text("Contrast")
                    Slider(
                        value: Binding(
                            get: { Double(options.contrast) },
                            set: { options.contrast = Int($0.rounded()) }
                        ),
                        in: 0...100, step: 1
                    )
                    .accessibilityLabel("Color image contrast")
                    Text(options.contrast > 0 ? "+\(options.contrast.formatted())" : options.contrast.formatted())
                        .monospacedDigit()
                        .frame(width: 32, alignment: .trailing)
                }
            }
        }
    }

    private var levelPicker: some View {
        Picker("Compression", selection: $options.level) {
            ForEach(PDFCompressionOptions.Level.allCases, id: \.self) { level in
                Text(level.title).tag(level).disabled(!isLevelEnabled(level))
            }
        }
        .pickerStyle(.segmented)
        .frame(minWidth: 230)
        .disabled(options.colorMode == .blackAndWhite &&
                  PDFCompressionOptions.Level.allCases.filter(isLevelEnabled).count == 1)
    }

    private var colorPicker: some View {
        Picker("Color", selection: $options.colorMode) {
            ForEach(PDFCompressionOptions.ColorMode.allCases, id: \.self) {
                Text($0.title).tag($0)
            }
        }
        .pickerStyle(.segmented)
        .frame(minWidth: 130)
    }
}
