import SwiftUI

struct SemanticDistillerEditor: View {
    let definition: DistillerOptionDefinition
    @ObservedObject var repository: JoboptionsRepository

    @ViewBuilder
    var body: some View {
        switch definition.semanticEditor {
        case .scalar:
            EmptyView()
        case .description:
            DescriptionEditor(repository: repository)
        case .deviceResolution:
            DeviceResolutionEditor(repository: repository)
        case .pageRange:
            PageRangeEditor(repository: repository)
        case .pageSize:
            PageSizeEditor(repository: repository)
        case let .downsampling(kind):
            DownsamplingEditor(kind: kind, repository: repository)
        case let .compression(kind):
            CompressionEditor(kind: kind, repository: repository)
        case let .imagePolicy(kind):
            ImagePolicyEditor(kind: kind, repository: repository)
        case .monoSmoothing:
            MonoSmoothingEditor(repository: repository)
        case .distillerOverrides:
            DistillerOverridesEditor(repository: repository)
        case .pdfXBoxes:
            PDFXBoxesEditor(repository: repository)
        case .standard, .companion:
            EmptyView()
        }
    }

    private struct DistillerOverridesEditor: View {
        @ObservedObject var repository: JoboptionsRepository

        var body: some View {
            Toggle(
                String(localized: "Allow PostScript files to override PDF settings"),
                isOn: Binding(
                    get: {
                        guard let document = repository.activeDocument else { return false }
                        return SemanticJoboptions.allowsDistillerOverrides(in: document)
                    },
                    set: { allows in
                        apply(
                            SemanticJoboptions.changeAllowsDistillerOverrides(allows),
                            repository: repository
                        )
                    }
                )
            )
        }
    }

    private struct DescriptionEditor: View {
        @ObservedObject var repository: JoboptionsRepository
        @State private var draft = ""
        @State private var baseline = ""

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "Description"))
                TextField(String(localized: "Description"), text: $draft, axis: .vertical)
                    .lineLimit(2...5)
                if draft != baseline {
                    Button(String(localized: "Apply description"), action: commit)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .onAppear(perform: reload)
            .onChange(of: repository.activeRecord?.id) { _, _ in reload() }
        }

        private func reload() {
            guard let document = repository.activeDocument else { return }
            draft = SemanticJoboptions.description(in: document) ?? ""
            baseline = draft
        }

        private func commit() {
            guard let document = repository.activeDocument else { return }
            guard apply(
                SemanticJoboptions.changeDescription(to: draft, in: document),
                repository: repository
            ) else { return }
            reload()
        }
    }

    private struct DeviceResolutionEditor: View {
        @ObservedObject var repository: JoboptionsRepository
        @State private var x = ""
        @State private var y = ""
        @State private var baselineX = ""
        @State private var baselineY = ""

        var body: some View {
            HStack {
                TextField(String(localized: "X"), text: $x)
                    .keyboardType(.numberPad)
                Text(String(localized: "×"))
                TextField(String(localized: "Y"), text: $y)
                    .keyboardType(.numberPad)
                Text(String(localized: "dpi"))
                if x != baselineX || y != baselineY {
                    Button(String(localized: "Apply")) {
                        guard let xValue = Int(x), let yValue = Int(y),
                              apply(
                                  SemanticJoboptions.changeDeviceResolution(x: xValue, y: yValue),
                                  repository: repository
                              )
                        else { return }
                        reload()
                    }
                }
            }
            .onAppear(perform: reload)
            .onChange(of: repository.activeRecord?.id) { _, _ in reload() }
        }

        private func reload() {
            guard let document = repository.activeDocument,
                  let resolution = SemanticJoboptions.deviceResolution(in: document)
            else {
                x = ""
                y = ""
                baselineX = ""
                baselineY = ""
                return
            }
            x = Self.numberText(resolution.x)
            y = Self.numberText(resolution.y)
            baselineX = x
            baselineY = y
        }

        private static func numberText(_ value: Double) -> String {
            value.rounded() == value ? String(Int(value)) : String(value)
        }
    }

    private struct PageRangeEditor: View {
        @ObservedObject var repository: JoboptionsRepository
        @State private var mode = "all"
        @State private var start = "1"
        @State private var end = "1"
        @State private var baselineMode = "all"
        @State private var baselineStart = "1"
        @State private var baselineEnd = "1"

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Picker(String(localized: "Pages"), selection: $mode) {
                    Text(String(localized: "All pages")).tag("all")
                    Text(String(localized: "Page range")).tag("range")
                    if mode == "custom" {
                        Text(String(localized: "Custom (preserved)")).tag("custom")
                    }
                }
                .pickerStyle(.segmented)
                HStack {
                    TextField(String(localized: "From"), text: $start)
                        .keyboardType(.numberPad)
                    TextField(String(localized: "To"), text: $end)
                        .keyboardType(.numberPad)
                }
                .disabled(mode != "range")
                if isDirty {
                    Button(String(localized: "Apply"), action: commit)
                        .buttonStyle(.bordered)
                }
            }
            .onAppear(perform: reload)
            .onChange(of: repository.activeRecord?.id) { _, _ in reload() }
        }

        private func reload() {
            guard let document = repository.activeDocument else { return }
            switch SemanticJoboptions.pageSelection(in: document) {
            case .all:
                mode = "all"
            case let .range(first, last):
                mode = "range"
                start = String(first)
                end = String(last)
            case .custom:
                mode = "custom"
            }
            baselineMode = mode
            baselineStart = start
            baselineEnd = end
        }

        private func commit() {
            let selection: SemanticJoboptions.PageSelection
            if mode == "all" {
                selection = .all
            } else if mode == "range", let first = Int(start), let last = Int(end) {
                selection = .range(start: first, end: last)
            } else {
                return
            }
            guard apply(
                SemanticJoboptions.changePageSelection(selection),
                repository: repository
            ) else { return }
            reload()
        }

        private var isDirty: Bool {
            mode != baselineMode || start != baselineStart || end != baselineEnd
        }
    }

    private struct PageSizeEditor: View {
        @ObservedObject var repository: JoboptionsRepository
        @State private var unit: SemanticJoboptions.MeasurementUnit = .points
        @State private var width = ""
        @State private var height = ""
        @State private var baselineWidthInPoints: Double?
        @State private var baselineHeightInPoints: Double?

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Picker(String(localized: "Unit"), selection: unitBinding) {
                    Text(String(localized: "Points")).tag(SemanticJoboptions.MeasurementUnit.points)
                    Text(String(localized: "Inches")).tag(SemanticJoboptions.MeasurementUnit.inches)
                    Text(String(localized: "Millimeters")).tag(SemanticJoboptions.MeasurementUnit.millimeters)
                }
                HStack {
                    TextField(String(localized: "Width"), text: $width)
                        .keyboardType(.decimalPad)
                    Text(String(localized: "×"))
                    TextField(String(localized: "Height"), text: $height)
                        .keyboardType(.decimalPad)
                }
                if isDirty {
                    Button(String(localized: "Apply")) {
                        guard let widthValue = parsed(width),
                              let heightValue = parsed(height),
                              apply(
                                  SemanticJoboptions.changePageSize(
                                      width: widthValue,
                                      height: heightValue,
                                      unit: unit
                                  ),
                                  repository: repository
                              )
                        else { return }
                        reload()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .onAppear(perform: reload)
            .onChange(of: repository.activeRecord?.id) { _, _ in reload() }
        }

        private func reload() {
            guard let document = repository.activeDocument,
                  let size = SemanticJoboptions.pageSize(in: document)
            else {
                width = ""
                height = ""
                unit = .points
                baselineWidthInPoints = nil
                baselineHeightInPoints = nil
                return
            }
            width = String(size.widthInPoints)
            height = String(size.heightInPoints)
            unit = .points
            baselineWidthInPoints = size.widthInPoints
            baselineHeightInPoints = size.heightInPoints
        }

        private var unitBinding: Binding<SemanticJoboptions.MeasurementUnit> {
            Binding(
                get: { unit },
                set: { newUnit in
                    convert(from: unit, to: newUnit)
                    unit = newUnit
                }
            )
        }

        private var isDirty: Bool {
            guard let widthValue = parsed(width),
                  let heightValue = parsed(height),
                  let baselineWidthInPoints,
                  let baselineHeightInPoints
            else { return false }
            let tolerance = 0.01
            return abs(widthValue * unit.pointsPerUnit - baselineWidthInPoints) > tolerance
                || abs(heightValue * unit.pointsPerUnit - baselineHeightInPoints) > tolerance
        }

        private func convert(
            from oldUnit: SemanticJoboptions.MeasurementUnit,
            to newUnit: SemanticJoboptions.MeasurementUnit
        ) {
            guard let oldWidth = parsed(width), let oldHeight = parsed(height) else { return }
            width = String(format: "%.4f", oldWidth * oldUnit.pointsPerUnit / newUnit.pointsPerUnit)
            height = String(format: "%.4f", oldHeight * oldUnit.pointsPerUnit / newUnit.pointsPerUnit)
        }

        private func parsed(_ value: String) -> Double? {
            Double(value.replacingOccurrences(of: ",", with: "."))
        }
    }

    private struct DownsamplingEditor: View {
        let kind: SemanticJoboptions.ImageKind
        @ObservedObject var repository: JoboptionsRepository
        @State private var mode = "off"
        @State private var resolution = ""
        @State private var threshold = ""
        @State private var baselineMode = "off"
        @State private var baselineResolution = ""
        @State private var baselineThreshold = ""

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Picker(String(localized: "Downsampling"), selection: $mode) {
                    Text(String(localized: "Off")).tag("off")
                    Text(String(localized: "Average")).tag("Average")
                    Text(String(localized: "Bicubic")).tag("Bicubic")
                    Text(String(localized: "Subsample")).tag("Subsample")
                    if mode == "custom" {
                        Text(String(localized: "Custom (preserved)")).tag("custom")
                    }
                }
                HStack {
                    TextField(String(localized: "Resolution"), text: $resolution)
                        .keyboardType(.numberPad)
                    TextField(String(localized: "For images above"), text: $threshold)
                        .keyboardType(.decimalPad)
                }
                .disabled(mode == "off" || mode == "custom")
                if isDirty {
                    Button(String(localized: "Apply"), action: commit)
                        .buttonStyle(.bordered)
                }
            }
            .onAppear(perform: reload)
            .onChange(of: repository.activeRecord?.id) { _, _ in reload() }
        }

        private func reload() {
            guard let document = repository.activeDocument else { return }
            switch SemanticJoboptions.downsampling(in: document, kind: kind) {
            case .off:
                mode = "off"
            case let .configured(selectedMode, selectedResolution, selectedThreshold):
                mode = selectedMode.rawValue
                resolution = String(selectedResolution)
                threshold = String(selectedThreshold)
            case .custom:
                mode = "custom"
            }
            baselineMode = mode
            baselineResolution = resolution
            baselineThreshold = threshold
        }

        private func commit() {
            if mode == "off" {
                guard apply(
                    SemanticJoboptions.changeDownsampling(
                        kind: kind,
                        enabled: false,
                        mode: .bicubic,
                        resolution: 300,
                        threshold: 1.5
                    ),
                    repository: repository
                ) else { return }
                reload()
                return
            }
            guard let selectedMode = SemanticJoboptions.DownsamplingMode(rawValue: mode),
                  let resolutionValue = Int(resolution),
                  let thresholdValue = Double(threshold.replacingOccurrences(of: ",", with: "."))
            else { return }
            guard apply(
                SemanticJoboptions.changeDownsampling(
                    kind: kind,
                    enabled: true,
                    mode: selectedMode,
                    resolution: resolutionValue,
                    threshold: thresholdValue
                ),
                repository: repository
            ) else { return }
            reload()
        }

        private var isDirty: Bool {
            mode != baselineMode
                || resolution != baselineResolution
                || threshold != baselineThreshold
        }
    }

    private struct CompressionEditor: View {
        let kind: SemanticJoboptions.ImageKind
        @ObservedObject var repository: JoboptionsRepository
        @State private var compression = "custom"
        @State private var quality = "custom"
        @State private var baselineCompression = "custom"
        @State private var baselineQuality = "custom"

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Picker(String(localized: "Compression"), selection: $compression) {
                    if kind != .monochrome {
                        Text(String(localized: "Automatic (JPEG)")).tag("automaticJPEG")
                        Text(String(localized: "JPEG")).tag("jpeg")
                        Text(String(localized: "JPEG 2000")).tag("jpeg2000")
                    }
                    Text(String(localized: "Flate")).tag("flate")
                    if kind == .monochrome {
                        Text(String(localized: "CCITT Group 4")).tag("ccitt")
                        Text(String(localized: "Run Length")).tag("runLength")
                    }
                    Text(String(localized: "Off")).tag("off")
                    if compression == "custom" {
                        Text(String(localized: "Custom (preserved)")).tag("custom")
                    }
                }
                if kind != .monochrome {
                    Picker(String(localized: "Image quality"), selection: $quality) {
                        Text(String(localized: "Minimum")).tag("minimum")
                        Text(String(localized: "Low")).tag("low")
                        Text(String(localized: "Medium")).tag("medium")
                        Text(String(localized: "High")).tag("high")
                        Text(String(localized: "Maximum")).tag("maximum")
                        if quality == "custom" {
                            Text(String(localized: "Custom (preserved)")).tag("custom")
                        }
                    }
                }
                if isDirty {
                    Button(String(localized: "Apply"), action: commit)
                        .buttonStyle(.bordered)
                }
            }
            .onAppear(perform: reload)
            .onChange(of: repository.activeRecord?.id) { _, _ in reload() }
        }

        private func reload() {
            guard let document = repository.activeDocument else { return }
            let configuration = SemanticJoboptions.imageCompression(in: document, kind: kind)
            compression = Self.compressionName(configuration.compression)
            quality = Self.qualityName(configuration.quality)
            baselineCompression = compression
            baselineQuality = quality
        }

        private func commit() {
            guard let selectedCompression = compressionValue else { return }
            let selectedQuality: SemanticJoboptions.ImageQuality?
            switch quality {
            case "minimum": selectedQuality = .minimum
            case "low": selectedQuality = .low
            case "medium": selectedQuality = .medium
            case "high": selectedQuality = .high
            case "maximum": selectedQuality = .maximum
            default: selectedQuality = nil
            }
            guard apply(
                SemanticJoboptions.changeCompression(
                    kind: kind,
                    compression: selectedCompression,
                    quality: selectedQuality
                ),
                repository: repository
            ) else { return }
            reload()
        }

        private var isDirty: Bool {
            compression != baselineCompression
                || (kind != .monochrome && quality != baselineQuality)
        }

        private var compressionValue: SemanticJoboptions.ImageCompression? {
            switch compression {
            case "automaticJPEG": .automaticJPEG
            case "jpeg": .jpeg
            case "flate": .flate
            case "jpeg2000": .jpeg2000
            case "ccitt": .ccittGroup4
            case "runLength": .runLength
            case "off": .off
            default: nil
            }
        }

        private static func compressionName(_ value: SemanticJoboptions.ImageCompression) -> String {
            switch value {
            case .automaticJPEG: "automaticJPEG"
            case .jpeg: "jpeg"
            case .flate: "flate"
            case .jpeg2000: "jpeg2000"
            case .ccittGroup4: "ccitt"
            case .runLength: "runLength"
            case .off: "off"
            case .custom: "custom"
            }
        }

        private static func qualityName(_ value: SemanticJoboptions.ImageQuality?) -> String {
            switch value {
            case .minimum: "minimum"
            case .low: "low"
            case .medium: "medium"
            case .high: "high"
            case .maximum: "maximum"
            case .custom, nil: "custom"
            }
        }
    }

    private struct ImagePolicyEditor: View {
        let kind: SemanticJoboptions.ImageKind
        @ObservedObject var repository: JoboptionsRepository
        @State private var minimum = ""
        @State private var policy = "OK"
        @State private var baselineMinimum = ""
        @State private var baselinePolicy = "OK"

        var body: some View {
            HStack {
                TextField(String(localized: "Minimum resolution"), text: $minimum)
                    .keyboardType(.numberPad)
                Picker(String(localized: "Policy"), selection: $policy) {
                    Text(String(localized: "Ignore")).tag("OK")
                    Text(String(localized: "Warning")).tag("Warning")
                    Text(String(localized: "Error")).tag("Error")
                    if !["OK", "Warning", "Error"].contains(policy) {
                        Text(String(localized: "Custom (preserved)")).tag(policy)
                    }
                }
                if isDirty {
                    Button(String(localized: "Apply"), action: commit)
                }
            }
            .onAppear(perform: reload)
            .onChange(of: repository.activeRecord?.id) { _, _ in reload() }
        }

        private func reload() {
            guard let document = repository.activeDocument else { return }
            let configuration = SemanticJoboptions.imagePolicy(in: document, kind: kind)
            minimum = configuration.minimumResolution.map(String.init) ?? ""
            policy = configuration.policy?.rawValue ?? "custom"
            baselineMinimum = minimum
            baselinePolicy = policy
        }

        private func commit() {
            guard let minimumValue = Int(minimum),
                  let selectedPolicy = SemanticJoboptions.ImagePolicy(rawValue: policy)
            else { return }
            guard apply(
                SemanticJoboptions.changeImagePolicy(
                    kind: kind,
                    minimumResolution: minimumValue,
                    policy: selectedPolicy
                ),
                repository: repository
            ) else { return }
            reload()
        }

        private var isDirty: Bool {
            minimum != baselineMinimum || policy != baselinePolicy
        }
    }

    private struct MonoSmoothingEditor: View {
        @ObservedObject var repository: JoboptionsRepository
        @State private var selection = "custom"
        @State private var baselineSelection = "custom"

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Picker(String(localized: "Smooth monochrome images"), selection: $selection) {
                    Text(String(localized: "Off")).tag("off")
                    Text(String(localized: "2 bit")).tag("2")
                    Text(String(localized: "4 bit")).tag("4")
                    Text(String(localized: "8 bit")).tag("8")
                    if selection == "custom" {
                        Text(String(localized: "Custom (preserved)")).tag("custom")
                    }
                }
                if selection != baselineSelection {
                    Button(String(localized: "Apply"), action: commit)
                        .buttonStyle(.bordered)
                }
            }
            .onAppear(perform: reload)
            .onChange(of: repository.activeRecord?.id) { _, _ in reload() }
        }

        private func commit() {
            let configuration: SemanticJoboptions.MonoSmoothingConfiguration
            if selection == "off" {
                configuration = .off
            } else if let depth = Int(selection) {
                configuration = .depth(depth)
            } else {
                return
            }
            guard apply(
                SemanticJoboptions.changeMonoSmoothing(configuration),
                repository: repository
            ) else { return }
            reload()
        }

        private func reload() {
            guard let document = repository.activeDocument else { return }
            switch SemanticJoboptions.monoSmoothing(in: document) {
            case .off:
                selection = "off"
            case let .depth(depth):
                selection = String(depth)
            case .custom:
                selection = "custom"
            }
            baselineSelection = selection
        }
    }

    private struct PDFXBoxesEditor: View {
        @ObservedObject var repository: JoboptionsRepository
        @State private var trimMode = "custom"
        @State private var bleedMode = "custom"
        @State private var trimOffsets = ["0", "0", "0", "0"]
        @State private var bleedOffsets = ["0", "0", "0", "0"]
        @State private var baselineTrimMode = "custom"
        @State private var baselineBleedMode = "custom"
        @State private var baselineTrimOffsets = ["0", "0", "0", "0"]
        @State private var baselineBleedOffsets = ["0", "0", "0", "0"]

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Picker(String(localized: "If trim box is missing"), selection: $trimMode) {
                    Text(String(localized: "Report an error")).tag("error")
                    Text(String(localized: "Set from media box with offsets")).tag("media")
                    if trimMode == "custom" { Text(String(localized: "Custom (preserved)")).tag("custom") }
                }
                offsetFields(values: $trimOffsets)
                    .disabled(trimMode != "media")
                Picker(String(localized: "If bleed box is missing"), selection: $bleedMode) {
                    Text(String(localized: "Set to media box")).tag("media")
                    Text(String(localized: "Set from trim box with offsets")).tag("trim")
                    if bleedMode == "custom" { Text(String(localized: "Custom (preserved)")).tag("custom") }
                }
                offsetFields(values: $bleedOffsets)
                    .disabled(bleedMode != "trim")
                if isDirty {
                    Button(String(localized: "Apply"), action: commit)
                        .buttonStyle(.bordered)
                }
            }
            .onAppear(perform: reload)
            .onChange(of: repository.activeRecord?.id) { _, _ in reload() }
        }

        private func offsetFields(values: Binding<[String]>) -> some View {
            HStack {
                ForEach(0..<4, id: \.self) { index in
                    TextField(Self.offsetLabel(index), text: values[index])
                        .keyboardType(.decimalPad)
                }
            }
        }

        private func reload() {
            guard let document = repository.activeDocument else { return }
            let rules = SemanticJoboptions.pdfXBoxRules(in: document)
            switch rules.trim {
            case .error:
                trimMode = "error"
            case let .mediaBox(offsets):
                trimMode = "media"
                trimOffsets = offsets.map { String($0) }
            case .trimBox, .custom:
                trimMode = "custom"
            }
            switch rules.bleed {
            case .mediaBox:
                bleedMode = "media"
            case let .trimBox(offsets):
                bleedMode = "trim"
                bleedOffsets = offsets.map { String($0) }
            case .error, .custom:
                bleedMode = "custom"
            }
            baselineTrimMode = trimMode
            baselineBleedMode = bleedMode
            baselineTrimOffsets = trimOffsets
            baselineBleedOffsets = bleedOffsets
        }

        private func commit() {
            let trim: SemanticJoboptions.PDFXBoxRule
            if trimMode == "error" {
                trim = .error
            } else if trimMode == "media", let values = Self.offsetValues(trimOffsets) {
                trim = .mediaBox(offsets: values)
            } else {
                trim = .custom
            }
            let bleed: SemanticJoboptions.PDFXBoxRule
            if bleedMode == "media" {
                bleed = .mediaBox(offsets: [0, 0, 0, 0])
            } else if bleedMode == "trim", let values = Self.offsetValues(bleedOffsets) {
                bleed = .trimBox(offsets: values)
            } else {
                bleed = .custom
            }
            guard apply(
                SemanticJoboptions.changePDFXBoxRules(trim: trim, bleed: bleed),
                repository: repository
            ) else { return }
            reload()
        }

        private var isDirty: Bool {
            trimMode != baselineTrimMode
                || bleedMode != baselineBleedMode
                || trimOffsets != baselineTrimOffsets
                || bleedOffsets != baselineBleedOffsets
        }

        private static func offsetValues(_ values: [String]) -> [Double]? {
            let converted = values.compactMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
            return converted.count == 4 ? converted : nil
        }

        private static func offsetLabel(_ index: Int) -> String {
            switch index {
            case 0: String(localized: "Left")
            case 1: String(localized: "Right")
            case 2: String(localized: "Top")
            default: String(localized: "Bottom")
            }
        }
    }

    @discardableResult
    private static func apply(
        _ changeSet: JoboptionsChangeSet,
        repository: JoboptionsRepository
    ) -> Bool {
        do {
            try repository.apply(changeSet)
            return true
        } catch {
            repository.lastError = error.localizedDescription
            return false
        }
    }
}
