import SwiftUI

struct FrontConversionView: View {
    @ObservedObject var repository: JoboptionsRepository
    let selectedPDFVersion: PDFVersion
    let isPDFVersionConstrained: Bool
    let selectedPDFACompatibility: PDFACompatibility
    let controlsAreDisabled: Bool
    let controlsAppearDisabled: Bool
    let onSelectPDFVersion: (PDFVersion) -> Void
    let onSelectPDFACompatibility: (PDFACompatibility) -> Void
    let onShowSettings: () -> Void
    let onManageJoboptions: (() -> Void)?
    let onShowPDFInfo: () -> Void
    let onOpenFile: () -> Void
    let onOpenPostScriptFile: () -> Void
    let onEncryptPostScriptFile: () -> Void
    let onShowGhostscriptSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(verbatim: "iPS2PDF")
                    .font(.headline)
                HStack {
                    Spacer()
                    Button(action: onShowGhostscriptSettings) {
                        Image(systemName: "gearshape")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Ghostscript settings")
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tools")
                            .font(.largeTitle.weight(.bold))
                        Text("Choose a task.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    analysisCard
                    conversionCard
                    postScriptCard
                }
                .frame(maxWidth: 520, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .background(Color.appGroupedBackground.ignoresSafeArea())
        .allowsHitTesting(!controlsAreDisabled)
    }

    private var analysisCard: some View {
        toolButton(
            title: LocalizedStringResource("Open PDF…"),
            subtitle: LocalizedStringResource("Information & Tools"),
            systemImage: "doc.text.magnifyingglass",
            action: onShowPDFInfo
        )
        .background(Color.appSecondaryGroupedBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
    }

    private var conversionCard: some View {
        VStack(spacing: 0) {
            toolButton(
                title: LocalizedStringResource("Convert to PDF…"),
                subtitle: LocalizedStringResource("PostScript · EPS · PDF → PDF"),
                systemImage: "arrow.down.doc",
                action: onOpenFile
            )

            Divider()
                .padding(.leading, 18)

            Text("Conversion options")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 7)

            joboptionsRow

            Divider()
                .padding(.leading, 18)

            optionRow(LocalizedStringResource("pdf_version")) {
                PDFVersionDropdown(
                    selectedVersion: selectedPDFVersion,
                    isDisabled: controlsAppearDisabled || isPDFVersionConstrained,
                    onSelect: onSelectPDFVersion
                )
                .saturation(isPDFVersionConstrained ? 0 : 1)
            }

            Divider()
                .padding(.leading, 18)

            optionRow(LocalizedStringResource("pdfa_compatibility")) {
                PDFACompatibilityDropdown(
                    selectedCompatibility: selectedPDFACompatibility,
                    isDisabled: controlsAppearDisabled,
                    onSelect: onSelectPDFACompatibility
                )
            }
        }
        .background(Color.appSecondaryGroupedBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
    }

    private var postScriptCard: some View {
        VStack(spacing: 0) {
            toolButton(
                title: LocalizedStringResource("Convert to PS…"),
                subtitle: LocalizedStringResource("PDF · EPS · PostScript → PostScript"),
                systemImage: "doc.badge.arrow.up",
                action: onOpenPostScriptFile
            )

            Divider()
                .padding(.leading, 18)

            Button(action: onEncryptPostScriptFile) {
                HStack(spacing: 12) {
                    Image(systemName: "lock.doc")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.tint)
                        .frame(width: 38, height: 38)
                        .background(Color.appTint.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Text("Encrypt PostScript…")
                        .font(.body)
                        .foregroundStyle(.primary)

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, minHeight: 64)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(controlsAppearDisabled)
        }
        .background(Color.appSecondaryGroupedBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
    }

    private var joboptionsRow: some View {
        HStack(spacing: 10) {
            Text("Joboptions")
                .layoutPriority(1)

            Spacer(minLength: 8)

            JoboptionsDropdown(
                repository: repository,
                isDisabled: controlsAppearDisabled,
                onManage: onManageJoboptions
            )

            Divider()
                .frame(height: 32)

            Button(action: onShowSettings) {
                Image(systemName: "pencil")
                    .font(.body.weight(.medium))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .disabled(controlsAppearDisabled)
            .accessibilityLabel("Edit selected Joboptions")
            .help("Edit selected Joboptions")
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .frame(minHeight: 60)
    }

    private func optionRow<Control: View>(
        _ title: LocalizedStringResource,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .layoutPriority(1)
            Spacer(minLength: 8)
            control()
        }
        .padding(.leading, 18)
        .padding(.trailing, 14)
        .frame(minHeight: 60)
    }

    private func toolButton(
        title: LocalizedStringResource,
        subtitle: LocalizedStringResource,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(.tint)
                    .frame(width: 58, height: 58)
                    .background(Color.appTint.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .multilineTextAlignment(.leading)
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(controlsAppearDisabled)
    }
}
