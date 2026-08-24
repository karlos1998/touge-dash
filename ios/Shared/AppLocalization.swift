import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    static let defaultsKey = "tougeDash.language"

    case system
    case polish
    case english

    var id: Self { self }

    var title: String {
        switch self {
        case .system: localized("Systemowy")
        case .polish: localized("Polski")
        case .english: localized("Angielski")
        }
    }

    var locale: Locale {
        switch self {
        case .system: .autoupdatingCurrent
        case .polish: Locale(identifier: "pl")
        case .english: Locale(identifier: "en")
        }
    }

    fileprivate var localizationCode: String? {
        switch self {
        case .system: nil
        case .polish: "pl"
        case .english: "en"
        }
    }

    fileprivate static var selected: AppLanguage {
        guard let storedValue = UserDefaults.standard.string(forKey: defaultsKey) else {
            return .system
        }
        return AppLanguage(rawValue: storedValue) ?? .system
    }
}

@inline(__always)
func localized(_ key: String) -> String {
    let language = AppLanguage.selected
    guard
        let code = language.localizationCode,
        let path = Bundle.main.path(forResource: code, ofType: "lproj"),
        let bundle = Bundle(path: path)
    else {
        return Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    return bundle.localizedString(forKey: key, value: key, table: nil)
}
