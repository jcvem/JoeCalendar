//
//  LocaleManager.swift
//  JoeCalendar
//
//  Created for JoeCalendar Phase 0 Foundation.
//  Handles device-default language detection, user preference overrides in UserDefaults,
//  and reactive locale updates across SwiftUI views.
//

import SwiftUI
import Combine

public enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case english = "en"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .system:
            return "System Default"
        case .english:
            return "English"
        case .traditionalChinese:
            return "繁體中文"
        case .japanese:
            return "日本語"
        }
    }
}

@MainActor
public final class LocaleManager: ObservableObject {
    public static let shared = LocaleManager()
    
    private let userDefaultsKey = "joecalendar_selected_locale_override"
    
    @Published public var selectedLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(selectedLanguage.rawValue, forKey: userDefaultsKey)
            updateEffectiveLocale()
        }
    }
    
    @Published public private(set) var effectiveLocale: Locale
    @Published public private(set) var effectiveLanguageCode: String
    
    private init() {
        let stored = UserDefaults.standard.string(forKey: userDefaultsKey) ?? AppLanguage.system.rawValue
        let initialLang = AppLanguage(rawValue: stored) ?? .system
        self.selectedLanguage = initialLang
        
        let detected = Self.resolveLanguageCode(for: initialLang)
        self.effectiveLanguageCode = detected
        self.effectiveLocale = Locale(identifier: detected)
    }
    
    private func updateEffectiveLocale() {
        let code = Self.resolveLanguageCode(for: selectedLanguage)
        self.effectiveLanguageCode = code
        self.effectiveLocale = Locale(identifier: code)
    }
    
    public static func resolveLanguageCode(for language: AppLanguage) -> String {
        switch language {
        case .english:
            return "en"
        case .traditionalChinese:
            return "zh-Hant"
        case .japanese:
            return "ja"
        case .system:
            let preferred = Locale.preferredLanguages.first ?? "en"
            if preferred.hasPrefix("zh-Hant") || preferred.hasPrefix("zh-TW") || preferred.hasPrefix("zh-HK") {
                return "zh-Hant"
            } else if preferred.hasPrefix("ja") {
                return "ja"
            } else if preferred.hasPrefix("zh") {
                return "zh-Hant"
            } else {
                return "en"
            }
        }
    }
    
    /// Helper to look up localized string manually when needed
    public func string(forKey key: String) -> String {
        if let path = Bundle.main.path(forResource: effectiveLanguageCode, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return NSLocalizedString(key, tableName: nil, bundle: bundle, value: key, comment: "")
        }
        return NSLocalizedString(key, comment: "")
    }
}

// MARK: - SwiftUI Extension for quick string localization

public extension Text {
    init(loc key: String) {
        self.init(LocalizedStringKey(key))
    }
}

public extension String {
    @MainActor
    func localized() -> String {
        LocaleManager.shared.string(forKey: self)
    }
}
