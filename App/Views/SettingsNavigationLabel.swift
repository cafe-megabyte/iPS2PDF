import SwiftUI

struct SettingsNavigationLabel: View {
    let title: Text
    let systemImage: String

    init(_ titleKey: LocalizedStringKey, systemImage: String) {
        self.title = Text(titleKey)
        self.systemImage = systemImage
    }

    init(verbatim title: String, systemImage: String) {
        self.title = Text(title)
        self.systemImage = systemImage
    }

    var body: some View {
        Label {
            title
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(Color(uiColor: UIColor.appTint))
        }
    }
}
