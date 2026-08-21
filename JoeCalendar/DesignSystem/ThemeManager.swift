//
//  ThemeManager.swift
//  JoeCalendar
//
//  Created for JoeCalendar Theme Customization.
//  Manages user-selected Light / Dark / System theme preference.
//

import SwiftUI
import Combine

public enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark
    
    public var id: String { rawValue }
    
    public var titleKey: String {
        switch self {
        case .system:
            return "theme_system"
        case .light:
            return "theme_light"
        case .dark:
            return "theme_dark"
        }
    }
}

@MainActor
public final class ThemeManager: ObservableObject {
    public static let shared = ThemeManager()
    
    private let userDefaultsKey = "joecalendar_theme"
    
    @Published public var current: AppTheme {
        didSet {
            UserDefaults.standard.set(current.rawValue, forKey: userDefaultsKey)
        }
    }
    
    public var preferredScheme: ColorScheme? {
        switch current {
        case .light:
            return .light
        case .dark:
            return .dark
        case .system:
            return nil
        }
    }
    
    public init() {
        let stored = UserDefaults.standard.string(forKey: "joecalendar_theme") ?? AppTheme.system.rawValue
        self.current = AppTheme(rawValue: stored) ?? .system
    }
}
