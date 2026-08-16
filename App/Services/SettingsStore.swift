import Foundation

final class SettingsStore {
    private enum Key {
        static let pdfVersion = "pdfVersion"
        static let pdfaCompatibility = "pdfaCompatibility"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var pdfVersion: PDFVersion {
        get {
            guard let rawValue = defaults.string(forKey: Key.pdfVersion),
                  let version = PDFVersion(rawValue: rawValue)
            else {
                defaults.set(PDFVersion.v13.rawValue, forKey: Key.pdfVersion)
                return .v13
            }
            return version
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.pdfVersion)
        }
    }

    var pdfaCompatibility: PDFACompatibility {
        get {
            guard let rawValue = defaults.string(forKey: Key.pdfaCompatibility),
                  let compatibility = PDFACompatibility(rawValue: rawValue)
            else {
                defaults.set(PDFACompatibility.none.rawValue, forKey: Key.pdfaCompatibility)
                return .none
            }
            return compatibility
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.pdfaCompatibility)
        }
    }
}
