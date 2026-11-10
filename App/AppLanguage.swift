import Foundation

/// Interface language chosen in Settings (requirement DS-3).
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case portuguese = "pt-BR"

    static let storageKey = "appLanguage"

    var id: String { rawValue }

    var locale: Locale {
        switch self {
        case .system: .autoupdatingCurrent
        case .english, .portuguese: Locale(identifier: rawValue)
        }
    }
}
