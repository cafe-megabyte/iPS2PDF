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
        case .fontSubsetting:
            FontSubsettingEditor(repository: repository)
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
            Picker(
                String(localized: "Allow PostScript files to override PDF settings"),
                selection: selection
            ) {
                Text(DistillerOptionCatalog.localizedChoice("False")).tag("false")
                Text(DistillerOptionCatalog.localizedChoice("True")).tag("true")
            }
            .pickerStyle(.menu)
        }

        private var selection: Binding<String> {
            Binding(
                get: {
                    let locked = JoboptionsRuntimeDefaults.booleanValue(
                        forKey: "LockDistillerParams",
                        in: repository.activeDocument
                    )
                    return locked ? "false" : "true"
                },
                set: { value in
                    apply(
                        SemanticJoboptions.changeAllowsDistillerOverrides(value == "true"),
                        repository: repository
                    )
                }
            )
        }
    }

    private struct FontSubsettingEditor: View {
        @ObservedObject var repository: JoboptionsRepository

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Picker(String(localized: "Subset embedded fonts"), selection: subsetSelection) {
                    Text(DistillerOptionCatalog.localizedChoice("False")).tag("false")
                    Text(DistillerOptionCatalog.localizedChoice("True")).tag("true")
                }
                .pickerStyle(.menu)

                HStack {
                    Text(String(localized: "Subset fonts below"))
                    TextField("", value: percentage, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 72)
                    Text("%")
                }
            }
        }

        private var subsetSelection: Binding<String> {
            Binding(
                get: {
                    JoboptionsRuntimeDefaults.booleanValue(
                        forKey: "SubsetFonts",
                        in: repository.activeDocument
                    ) ? "true" : "false"
                },
                set: { value in
                    updateBoolean(
                        path: "/SubsetFonts",
                        value: value == "true",
                        repository: repository
                    )
                }
            )
        }

        private var percentage: Binding<Int> {
            Binding(
                get: {
                    guard let value = repository.activeDocument?
                        .value(forKey: "MaxSubsetPct")?.numberValue,
                          value.rounded() == value,
                          (1...100).contains(Int(value))
                    else { return JoboptionsRuntimeDefaults.maxSubsetPercentage }
                    return Int(value)
                },
                set: { value in
                    guard (1...100).contains(value) else { return }
                    updateNumber(path: "/MaxSubsetPct", number: value, repository: repository)
                }
            )
        }
    }

    private struct DescriptionEditor: View {
        @ObservedObject var repository: JoboptionsRepository
        @State private var draft = ""

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "Description"))
                TextField("", text: editedDraft, axis: .vertical)
                    .lineLimit(2...5)
            }
            .onAppear(perform: reload)
            .onChange(of: repository.activeDocument?.data) { _, _ in reload() }
        }

        private var editedDraft: Binding<String> {
            Binding(get: { draft }, set: { value in
                draft = value
                guard let document = repository.activeDocument else { return }
                apply(
                    SemanticJoboptions.changeDescription(to: value, in: document),
                    repository: repository
                )
            })
        }

        private func reload() {
            guard let document = repository.activeDocument else { return }
            draft = SemanticJoboptions.description(in: document) ?? ""
        }
    }

    private struct DeviceResolutionEditor: View {
        @ObservedObject var repository: JoboptionsRepository
        @State private var x = ""
        @State private var y = ""

        var body: some View {
            HStack {
                TextField(String(localized: "X"), text: $x)
                    .keyboardType(.numberPad)
                    .invalidDraftStyle(!x.isEmpty && !isValid(x))
                Text(String(localized: "×"))
                TextField(String(localized: "Y"), text: $y)
                    .keyboardType(.numberPad)
                    .invalidDraftStyle(!y.isEmpty && !isValid(y))
                Text(String(localized: "dpi"))
            }
            .onAppear(perform: reload)
            .onChange(of: repository.activeDocument?.data) { _, _ in reload() }
            .onChange(of: x) { _, _ in commit() }
            .onChange(of: y) { _, _ in commit() }
        }

        private func reload() {
            let values = arrayTexts(repository.activeDocument?.value(forKey: "HWResolution"), count: 2)
            x = values[0]
            y = values[1]
        }

        private func isValid(_ text: String) -> Bool {
            Int(text).map { (1...9_600).contains($0) } == true
        }

        private func commit() {
            guard let xValue = Int(x), let yValue = Int(y),
                  (1...9_600).contains(xValue), (1...9_600).contains(yValue)
            else { return }
            apply(
                SemanticJoboptions.changeDeviceResolution(x: xValue, y: yValue),
                repository: repository
            )
        }
    }

    private struct PageRangeEditor: View {
        @ObservedObject var repository: JoboptionsRepository
        @State private var mode = "custom"
        @State private var start = ""
        @State private var end = ""

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Picker(String(localized: "Pages"), selection: $mode) {
                    Text(String(localized: "All pages")).tag("all")
                    Text(String(localized: "Page range")).tag("range")
                    if mode == "custom" {
                        Text(customTitle).tag("custom")
                    }
                }
                .pickerStyle(.segmented)
                HStack {
                    TextField(String(localized: "From"), text: $start)
                        .keyboardType(.numberPad)
                        .invalidDraftStyle(!start.isEmpty && Int(start).map { $0 >= 1 } != true)
                    TextField(String(localized: "To"), text: $end)
                        .keyboardType(.numbersAndPunctuation)
                        .invalidDraftStyle(!end.isEmpty && Int(end).map { $0 == -1 || $0 >= 1 } != true)
                }
            }
            .onAppear(perform: reload)
            .onChange(of: repository.activeDocument?.data) { _, _ in reload() }
            .onChange(of: mode) { _, value in commitMode(value) }
            .onChange(of: start) { _, value in
                guard let number = Int(value), number >= 1 else { return }
                updateNumber(path: "/StartPage", number: number, repository: repository)
            }
            .onChange(of: end) { _, value in
                guard let number = Int(value), number == -1 || number >= 1 else { return }
                updateNumber(path: "/EndPage", number: number, repository: repository)
            }
        }

        private var customTitle: String {
            String.localizedStringWithFormat(String(localized: "Custom: %@"), "\(start) … \(end)")
        }

        private func reload() {
            guard let document = repository.activeDocument else { return }
            let rawStart = document.value(forKey: "StartPage")
            let rawEnd = document.value(forKey: "EndPage")
            start = rawStart?.textualValue ?? rawStart?.postScript ?? ""
            end = rawEnd?.textualValue ?? rawEnd?.postScript ?? ""
            switch SemanticJoboptions.pageSelection(in: document) {
            case .all: mode = "all"
            case .range: mode = "range"
            case .custom: mode = "custom"
            }
        }

        private func commitMode(_ selected: String) {
            if selected == "all" {
                apply(SemanticJoboptions.changePageSelection(.all), repository: repository)
            } else if selected == "range" {
                let first = max(Int(start) ?? 1, 1)
                let last = max(Int(end) ?? first, first)
                apply(
                    SemanticJoboptions.changePageSelection(.range(start: first, end: last)),
                    repository: repository
                )
            }
        }
    }

    private struct PageSizeEditor: View {
        @ObservedObject var repository: JoboptionsRepository
        @State private var unit: SemanticJoboptions.MeasurementUnit = .points
        @State private var width = ""
        @State private var height = ""

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
                        .invalidDraftStyle(!width.isEmpty && parsed(width).map { $0 > 0 } != true)
                    Text(String(localized: "×"))
                    TextField(String(localized: "Height"), text: $height)
                        .keyboardType(.decimalPad)
                        .invalidDraftStyle(!height.isEmpty && parsed(height).map { $0 > 0 } != true)
                }
            }
            .onAppear(perform: reload)
            .onChange(of: repository.activeDocument?.data) { _, _ in reload() }
            .onChange(of: width) { _, _ in commit() }
            .onChange(of: height) { _, _ in commit() }
        }

        private var unitBinding: Binding<SemanticJoboptions.MeasurementUnit> {
            Binding(
                get: { unit },
                set: { newUnit in
                    convert(from: unit, to: newUnit)
                    unit = newUnit
                    commit()
                }
            )
        }

        private func reload() {
            guard let document = repository.activeDocument else { return }
            if let size = SemanticJoboptions.pageSize(in: document) {
                width = String(size.widthInPoints / unit.pointsPerUnit)
                height = String(size.heightInPoints / unit.pointsPerUnit)
            } else {
                let values = arrayTexts(document.value(forKey: "PageSize"), count: 2)
                width = values[0]
                height = values[1]
            }
        }

        private func commit() {
            guard let widthValue = parsed(width), let heightValue = parsed(height),
                  widthValue > 0, heightValue > 0
            else { return }
            apply(
                SemanticJoboptions.changePageSize(
                    width: widthValue, height: heightValue, unit: unit
                ),
                repository: repository
            )
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
        @State private var mode = "custom"
        @State private var resolution = ""
        @State private var threshold = ""

        private var prefix: String { kind.rawValue }

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Picker(String(localized: "Downsampling"), selection: $mode) {
                    Text(String(localized: "Off")).tag("off")
                    ForEach(SemanticJoboptions.DownsamplingMode.allCases, id: \.rawValue) { value in
                        Text(DistillerOptionCatalog.localizedChoice(value.rawValue)).tag(value.rawValue)
                    }
                    if mode == "custom" {
                        Text(customTitle).tag("custom")
                    }
                }
                HStack {
                    TextField(String(localized: "Resolution"), text: $resolution)
                        .keyboardType(.numberPad)
                        .invalidDraftStyle(!resolution.isEmpty && Int(resolution).map { (1...9_600).contains($0) } != true)
                    TextField(String(localized: "For images above"), text: $threshold)
                        .keyboardType(.decimalPad)
                        .invalidDraftStyle(!threshold.isEmpty && parsedThreshold.map { (1...10).contains($0) } != true)
                }
            }
            .onAppear(perform: reload)
            .onChange(of: repository.activeDocument?.data) { _, _ in reload() }
            .onChange(of: mode) { _, value in commitMode(value) }
            .onChange(of: resolution) { _, value in
                guard let number = Int(value), (1...9_600).contains(number) else { return }
                updateNumber(path: "/\(prefix)ImageResolution", number: number, repository: repository)
            }
            .onChange(of: threshold) { _, value in
                guard let number = Double(value.replacingOccurrences(of: ",", with: ".")),
                      (1...10).contains(number)
                else { return }
                updateNumber(path: "/\(prefix)ImageDownsampleThreshold", number: number, original: value, repository: repository)
            }
        }

        private var parsedThreshold: Double? {
            Double(threshold.replacingOccurrences(of: ",", with: "."))
        }

        private var customTitle: String {
            let raw = repository.activeDocument?.value(forKey: "\(prefix)ImageDownsampleType")
            let text = raw?.textualValue ?? raw?.postScript ?? String(localized: "Not set")
            return String.localizedStringWithFormat(String(localized: "Custom: %@"), text)
        }

        private func reload() {
            guard let document = repository.activeDocument else { return }
            let rawResolution = document.value(forKey: "\(prefix)ImageResolution")
            let rawThreshold = document.value(forKey: "\(prefix)ImageDownsampleThreshold")
            resolution = rawResolution?.textualValue ?? rawResolution?.postScript ?? ""
            threshold = rawThreshold?.textualValue ?? rawThreshold?.postScript ?? ""
            switch SemanticJoboptions.downsampling(in: document, kind: kind) {
            case .off: mode = "off"
            case let .configured(selected, _, _): mode = selected.rawValue
            case .custom: mode = "custom"
            }
        }

        private func commitMode(_ selected: String) {
            if selected == "off" {
                apply(JoboptionsChangeSet([
                    JoboptionsChange("/Downsample\(prefix)Images", .boolean(false))
                ]), repository: repository)
            } else if let value = SemanticJoboptions.DownsamplingMode(rawValue: selected) {
                apply(JoboptionsChangeSet([
                    JoboptionsChange("/Downsample\(prefix)Images", .boolean(true)),
                    JoboptionsChange("/\(prefix)ImageDownsampleType", .name(value.rawValue))
                ]), repository: repository)
            }
        }
    }

    private struct CompressionEditor: View {
        let kind: SemanticJoboptions.ImageKind
        @ObservedObject var repository: JoboptionsRepository
        @State private var compression = "custom"
        @State private var quality = "custom"
        @State private var jpxQuality = ""

        private var prefix: String { kind.rawValue }

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
                        Text(customCompressionTitle).tag("custom")
                    }
                }
                if kind != .monochrome && compression != "jpeg2000" {
                    Picker(String(localized: "Image quality"), selection: $quality) {
                        Text(String(localized: "Minimum")).tag("minimum")
                        Text(String(localized: "Low")).tag("low")
                        Text(String(localized: "Medium")).tag("medium")
                        Text(String(localized: "High")).tag("high")
                        Text(String(localized: "Maximum")).tag("maximum")
                        if quality == "custom" {
                            Text(customQualityTitle).tag("custom")
                        }
                    }
                } else if compression == "jpeg2000" {
                    LabeledContent(String(localized: "Image quality")) {
                        TextField("", text: $jpxQuality)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .invalidDraftStyle(!jpxQuality.isEmpty && parsedJPXQuality.map { (0...100).contains($0) } != true)
                    }
                }
            }
            .onAppear(perform: reload)
            .onChange(of: repository.activeDocument?.data) { _, _ in reload() }
            .onChange(of: compression) { _, _ in commitCompression() }
            .onChange(of: quality) { _, _ in commitCompression() }
            .onChange(of: jpxQuality) { _, value in
                guard let number = Double(value.replacingOccurrences(of: ",", with: ".")),
                      (0...100).contains(number)
                else { return }
                updateNumber(
                    path: "/JPEG2000\(prefix)ImageDict /Quality",
                    number: number,
                    original: value,
                    repository: repository
                )
            }
        }

        private var parsedJPXQuality: Double? {
            Double(jpxQuality.replacingOccurrences(of: ",", with: "."))
        }

        private var customCompressionTitle: String {
            let parts = [
                repository.activeDocument?.value(forKey: "Encode\(prefix)Images")?.postScript,
                repository.activeDocument?.value(forKey: "AutoFilter\(prefix)Images")?.postScript,
                repository.activeDocument?.value(forKey: "\(prefix)ImageFilter")?.postScript
            ].compactMap { $0 }.joined(separator: ", ")
            return String.localizedStringWithFormat(
                String(localized: "Custom: %@"),
                parts.isEmpty ? String(localized: "Not set") : parts
            )
        }

        private var customQualityTitle: String {
            String.localizedStringWithFormat(
                String(localized: "Custom: %@"),
                activeQualityText ?? String(localized: "Not set")
            )
        }

        private var activeQualityText: String? {
            guard let document = repository.activeDocument else { return nil }
            let path = compression == "automaticJPEG"
                ? "/\(prefix)ACSImageDict /QFactor"
                : "/\(prefix)ImageDict /QFactor"
            let value = document.value(forPath: path)
            return value?.textualValue ?? value?.postScript
        }

        private func reload() {
            guard let document = repository.activeDocument else { return }
            let configuration = SemanticJoboptions.imageCompression(in: document, kind: kind)
            compression = Self.compressionName(configuration.compression)
            quality = Self.qualityName(configuration.quality)
            let rawJPX = document.value(forPath: "/JPEG2000\(prefix)ImageDict /Quality")
            jpxQuality = rawJPX?.textualValue ?? rawJPX?.postScript ?? ""
        }

        private func commitCompression() {
            guard let selectedCompression = compressionValue else { return }
            apply(
                SemanticJoboptions.changeCompression(
                    kind: kind,
                    compression: selectedCompression,
                    quality: qualityValue
                ),
                repository: repository
            )
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

        private var qualityValue: SemanticJoboptions.ImageQuality? {
            switch quality {
            case "minimum": .minimum
            case "low": .low
            case "medium": .medium
            case "high": .high
            case "maximum": .maximum
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
        @State private var policy = "__not_set__"

        private var prefix: String { kind.rawValue }

        var body: some View {
            HStack {
                TextField("", text: $minimum)
                    .keyboardType(.numberPad)
                    .invalidDraftStyle(!minimum.isEmpty && Int(minimum).map { (1...9_600).contains($0) } != true)
                Picker(String(localized: "Policy"), selection: $policy) {
                    if policy == "__not_set__" {
                        Text(String(localized: "Not set")).tag("__not_set__")
                    } else if SemanticJoboptions.ImagePolicy(rawValue: policy) == nil {
                        Text(String.localizedStringWithFormat(
                            String(localized: "Custom: %@"), policy
                        )).tag(policy)
                    }
                    Text(String(localized: "Ignore")).tag("OK")
                    Text(String(localized: "Warning")).tag("Warning")
                    Text(String(localized: "Error")).tag("Error")
                }
            }
            .onAppear(perform: reload)
            .onChange(of: repository.activeDocument?.data) { _, _ in reload() }
            .onChange(of: minimum) { _, value in
                guard let number = Int(value), (1...9_600).contains(number) else { return }
                updateNumber(path: "/\(prefix)ImageMinResolution", number: number, repository: repository)
            }
            .onChange(of: policy) { _, value in
                guard SemanticJoboptions.ImagePolicy(rawValue: value) != nil else { return }
                apply(JoboptionsChangeSet([
                    JoboptionsChange("/\(prefix)ImageMinResolutionPolicy", .name(value))
                ]), repository: repository)
            }
        }

        private func reload() {
            guard let document = repository.activeDocument else { return }
            let rawMinimum = document.value(forKey: "\(prefix)ImageMinResolution")
            let rawPolicy = document.value(forKey: "\(prefix)ImageMinResolutionPolicy")
            minimum = rawMinimum?.textualValue ?? rawMinimum?.postScript ?? ""
            policy = rawPolicy?.textualValue ?? rawPolicy?.postScript ?? "__not_set__"
        }
    }

    private struct MonoSmoothingEditor: View {
        @ObservedObject var repository: JoboptionsRepository
        @State private var selection = "custom"

        var body: some View {
            Picker(String(localized: "Smooth monochrome images"), selection: $selection) {
                Text(String(localized: "Off")).tag("off")
                Text(String(localized: "2 bit")).tag("2")
                Text(String(localized: "4 bit")).tag("4")
                Text(String(localized: "8 bit")).tag("8")
                if selection == "custom" {
                    Text(customTitle).tag("custom")
                }
            }
            .onAppear(perform: reload)
            .onChange(of: repository.activeDocument?.data) { _, _ in reload() }
            .onChange(of: selection) { _, value in
                if value == "off" {
                    apply(SemanticJoboptions.changeMonoSmoothing(.off), repository: repository)
                } else if let depth = Int(value) {
                    apply(SemanticJoboptions.changeMonoSmoothing(.depth(depth)), repository: repository)
                }
            }
        }

        private var customTitle: String {
            let enabled = repository.activeDocument?.value(forKey: "AntiAliasMonoImages")?.postScript
                ?? String(localized: "Not set")
            let depth = repository.activeDocument?.value(forKey: "MonoImageDepth")?.postScript
                ?? String(localized: "Not set")
            return String.localizedStringWithFormat(
                String(localized: "Custom: %@"), "\(enabled), \(depth)"
            )
        }

        private func reload() {
            guard let document = repository.activeDocument else { return }
            switch SemanticJoboptions.monoSmoothing(in: document) {
            case .off: selection = "off"
            case let .depth(depth): selection = String(depth)
            case .custom: selection = "custom"
            }
        }
    }

    private struct PDFXBoxesEditor: View {
        @ObservedObject var repository: JoboptionsRepository
        @State private var trimMode = "custom"
        @State private var bleedMode = "custom"
        @State private var trimOffsets = ["", "", "", ""]
        @State private var bleedOffsets = ["", "", "", ""]

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Picker(String(localized: "If trim box is missing"), selection: trimSelection) {
                    Text(String(localized: "Report an error")).tag("error")
                    Text(String(localized: "Set from media box with offsets")).tag("media")
                    if trimMode == "custom" { Text(trimCustomTitle).tag("custom") }
                }
                offsetFields(values: trimOffsetSelection)
                Picker(String(localized: "If bleed box is missing"), selection: bleedSelection) {
                    Text(String(localized: "Set to media box")).tag("media")
                    Text(String(localized: "Set from trim box with offsets")).tag("trim")
                    if bleedMode == "custom" { Text(bleedCustomTitle).tag("custom") }
                }
                offsetFields(values: bleedOffsetSelection)
            }
            .onAppear(perform: reload)
            .onChange(of: repository.activeDocument?.data) { _, _ in reload() }
        }

        private var trimSelection: Binding<String> {
            Binding(get: { trimMode }, set: { value in
                trimMode = value
                if value == "error" {
                    updateBoolean(path: "/PDFXNoTrimBoxError", value: true, repository: repository)
                } else if value == "media" {
                    updateBoolean(path: "/PDFXNoTrimBoxError", value: false, repository: repository)
                }
            })
        }

        private var bleedSelection: Binding<String> {
            Binding(get: { bleedMode }, set: { value in
                bleedMode = value
                if value == "media" {
                    updateBoolean(path: "/PDFXSetBleedBoxToMediaBox", value: true, repository: repository)
                } else if value == "trim" {
                    updateBoolean(path: "/PDFXSetBleedBoxToMediaBox", value: false, repository: repository)
                }
            })
        }

        private var trimOffsetSelection: Binding<[String]> {
            Binding(get: { trimOffsets }, set: { values in
                trimOffsets = values
                updateOffsets(path: "/PDFXTrimBoxToMediaBoxOffset", texts: values)
            })
        }

        private var bleedOffsetSelection: Binding<[String]> {
            Binding(get: { bleedOffsets }, set: { values in
                bleedOffsets = values
                updateOffsets(path: "/PDFXBleedBoxToTrimBoxOffset", texts: values)
            })
        }

        private var trimCustomTitle: String {
            customBooleanTitle(key: "PDFXNoTrimBoxError")
        }

        private var bleedCustomTitle: String {
            customBooleanTitle(key: "PDFXSetBleedBoxToMediaBox")
        }

        private func customBooleanTitle(key: String) -> String {
            String.localizedStringWithFormat(
                String(localized: "Custom: %@"),
                repository.activeDocument?.value(forKey: key)?.postScript ?? String(localized: "Not set")
            )
        }

        private func offsetFields(values: Binding<[String]>) -> some View {
            HStack {
                ForEach(0..<4, id: \.self) { index in
                    TextField(Self.offsetLabel(index), text: values[index])
                        .keyboardType(.decimalPad)
                        .invalidDraftStyle(
                            !values.wrappedValue[index].isEmpty
                                && Self.number(values.wrappedValue[index]) == nil
                        )
                }
            }
        }

        private func reload() {
            guard let document = repository.activeDocument else { return }
            trimOffsets = arrayTexts(JoboptionsConsistencyEngine.displayValue(
                forKey: "PDFXTrimBoxToMediaBoxOffset", in: document,
                context: repository.consistencyAnalysisContext
            ), count: 4)
            bleedOffsets = arrayTexts(JoboptionsConsistencyEngine.displayValue(
                forKey: "PDFXBleedBoxToTrimBoxOffset", in: document,
                context: repository.consistencyAnalysisContext
            ), count: 4)
            let rules = JoboptionsConsistencyEngine.pdfXBoxRulesForDisplay(
                in: document, context: repository.consistencyAnalysisContext
            )
            switch rules.trim {
            case .error: trimMode = "error"
            case .mediaBox: trimMode = "media"
            case .trimBox, .custom: trimMode = "custom"
            }
            switch rules.bleed {
            case .mediaBox: bleedMode = "media"
            case .trimBox: bleedMode = "trim"
            case .error, .custom: bleedMode = "custom"
            }
        }

        private func updateOffsets(path: String, texts: [String]) {
            let values = texts.compactMap(Self.number)
            guard values.count == 4 else { return }
            apply(JoboptionsChangeSet([
                JoboptionsChange(
                    path,
                    .array(zip(values, texts).map { value, text in
                        .number(value, original: text.replacingOccurrences(of: ",", with: "."))
                    })
                )
            ]), repository: repository)
        }

        private static func number(_ text: String) -> Double? {
            Double(text.replacingOccurrences(of: ",", with: "."))
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

    private static func arrayTexts(_ value: JoboptionsValue?, count: Int) -> [String] {
        guard let value else { return Array(repeating: "", count: count) }
        guard case let .array(values) = value else {
            return [value.postScript] + Array(repeating: "", count: max(0, count - 1))
        }
        return (0..<count).map { index in
            guard values.indices.contains(index) else { return "" }
            return values[index].textualValue ?? values[index].postScript
        }
    }

    private static func updateNumber(
        path: String,
        number: Int,
        repository: JoboptionsRepository
    ) {
        updateNumber(path: path, number: Double(number), original: String(number), repository: repository)
    }

    private static func updateNumber(
        path: String,
        number: Double,
        original: String,
        repository: JoboptionsRepository
    ) {
        apply(JoboptionsChangeSet([
            JoboptionsChange(
                path,
                .number(number, original: original.replacingOccurrences(of: ",", with: "."))
            )
        ]), repository: repository)
    }

    private static func updateBoolean(
        path: String,
        value: Bool,
        repository: JoboptionsRepository
    ) {
        apply(JoboptionsChangeSet([
            JoboptionsChange(path, .boolean(value))
        ]), repository: repository)
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
