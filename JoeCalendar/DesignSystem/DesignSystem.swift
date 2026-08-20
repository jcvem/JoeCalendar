//
//  DesignSystem.swift
//  JoeCalendar
//
//  Created for JoeCalendar Phase 0 Foundation.
//  Japanese-calm aesthetic inspired by TimeTree:
//  - High whitespace
//  - Rounded cards
//  - Soft shadows
//  - Single restrained accent (Muted Japanese Indigo)
//  - Pastel group color palette
//  - CJK-friendly humanist typography
//

import SwiftUI

// MARK: - Color Tokens

public enum AppColor {
    // Canvas & Paper (Dynamic light/dark)
    public static let paper = Color(light: Color(hex: 0xFAFAF8), dark: Color(hex: 0x121417))
    public static let surface = Color(light: Color(hex: 0xFFFFFF), dark: Color(hex: 0x1C1F24))
    public static let surfaceSubtle = Color(light: Color(hex: 0xF4F4F1), dark: Color(hex: 0x24282F))
    
    // Inks (Typography & Icons)
    public static let inkPrimary = Color(light: Color(hex: 0x1E232A), dark: Color(hex: 0xF5F6F8))
    public static let inkSecondary = Color(light: Color(hex: 0x667080), dark: Color(hex: 0xA0A8B5))
    public static let inkTertiary = Color(light: Color(hex: 0x9EA8B6), dark: Color(hex: 0x6E7683))
    public static let inkBorder = Color(light: Color(hex: 0xECEBE6), dark: Color(hex: 0x2E3238))
    public static let inkBorderSubtle = Color(light: Color(hex: 0xF2F2EE), dark: Color(hex: 0x25282D))
    
    // Single Restrained Accent (Japanese Indigo / Slate Teal: #2D5D72)
    public static let accent = Color(light: Color(hex: 0x2D5D72), dark: Color(hex: 0x5D93A8))
    public static let accentLight = Color(light: Color(hex: 0xEDF4F7), dark: Color(hex: 0x1E313B))
    
    // Alert / Status
    public static let success = Color(light: Color(hex: 0x4B8365), dark: Color(hex: 0x6BA888))
    public static let warning = Color(light: Color(hex: 0xD9822B), dark: Color(hex: 0xE59B4C))
    public static let destructive = Color(light: Color(hex: 0xC84D4D), dark: Color(hex: 0xDF6E6E))
    
    // Pastel Palette for Friend Groups (Calm Japanese Traditional Hues)
    public enum GroupPastel: String, CaseIterable, Identifiable {
        case sage = "Sage"           // 青磁 (Seiji)
        case sakura = "Sakura"       // 桜 (Sakura / Peach)
        case mist = "Mist"           // 露草 (Tsuyukusa / Mist Blue)
        case yamabuki = "Yamabuki"   // 山吹 (Yamabuki / Warm Amber)
        case wisteria = "Wisteria"   // 藤 (Fuji / Slate Lavender)
        case matcha = "Matcha"       // 抹茶 (Matcha / Leaf)
        case sand = "Sand"           // 砂 (Suna / Warm Beige)
        case akane = "Akane"         // 茜 (Akane / Soft Coral)
        
        public var id: String { rawValue }
        
        public var color: Color {
            switch self {
            case .sage:     return Color(hex: 0x8DA399)
            case .sakura:   return Color(hex: 0xE8A598)
            case .mist:     return Color(hex: 0x8EAEC4)
            case .yamabuki: return Color(hex: 0xE5B869)
            case .wisteria: return Color(hex: 0xA39BC4)
            case .matcha:   return Color(hex: 0x9CB380)
            case .sand:     return Color(hex: 0xD3B89D)
            case .akane:    return Color(hex: 0xDD8C78)
            }
        }
        
        public var bgSubtle: Color {
            color.opacity(0.16)
        }
        
        public var hexString: String {
            switch self {
            case .sage:     return "#8DA399"
            case .sakura:   return "#E8A598"
            case .mist:     return "#8EAEC4"
            case .yamabuki: return "#E5B869"
            case .wisteria: return "#A39BC4"
            case .matcha:   return "#9CB380"
            case .sand:     return "#D3B89D"
            case .akane:    return "#DD8C78"
            }
        }
    }
}

// MARK: - Spacing Scale

public enum AppSpacing {
    /// 2 pt
    public static let xxs: CGFloat = 2
    /// 4 pt
    public static let xs: CGFloat = 4
    /// 8 pt
    public static let sm: CGFloat = 8
    /// 12 pt
    public static let md: CGFloat = 12
    /// 16 pt
    public static let lg: CGFloat = 16
    /// 20 pt
    public static let xl: CGFloat = 20
    /// 24 pt
    public static let xxl: CGFloat = 24
    /// 32 pt
    public static let xxxl: CGFloat = 32
    /// 48 pt
    public static let huge: CGFloat = 48
}

// MARK: - Radius Scale

public enum AppRadius {
    /// 4 pt
    public static let xs: CGFloat = 4
    /// 8 pt
    public static let sm: CGFloat = 8
    /// 12 pt
    public static let md: CGFloat = 12
    /// 16 pt - Default card radius
    public static let lg: CGFloat = 16
    /// 20 pt - Sheet / large card radius
    public static let xl: CGFloat = 20
    /// 28 pt - Modal corner radius
    public static let xxl: CGFloat = 28
    /// 999 pt - Pill / Tag radius
    public static let full: CGFloat = 999
}

// MARK: - Shadow Tokens

public enum AppShadow {
    /// Ultra-soft Japanese ambient shadow
    public static let subtle = ShadowStyle(
        color: Color.black.opacity(0.04),
        radius: 8,
        x: 0,
        y: 2
    )
    
    /// Elevated card / floating sheet shadow
    public static let floating = ShadowStyle(
        color: Color.black.opacity(0.08),
        radius: 16,
        x: 0,
        y: 6
    )
    
    public struct ShadowStyle {
        public let color: Color
        public let radius: CGFloat
        public let x: CGFloat
        public let y: CGFloat
    }
}

// MARK: - Typography (Humanist Sans + CJK Fallback)

public enum AppTypography {
    public static func largeTitle() -> Font {
        .system(size: 32, weight: .bold, design: .default)
    }
    
    public static func title1() -> Font {
        .system(size: 26, weight: .bold, design: .default)
    }
    
    public static func title2() -> Font {
        .system(size: 20, weight: .semibold, design: .default)
    }
    
    public static func title3() -> Font {
        .system(size: 17, weight: .semibold, design: .default)
    }
    
    public static func headline() -> Font {
        .system(size: 15, weight: .semibold, design: .default)
    }
    
    public static func body() -> Font {
        .system(size: 15, weight: .regular, design: .default)
    }
    
    public static func bodyMedium() -> Font {
        .system(size: 15, weight: .medium, design: .default)
    }
    
    public static func callout() -> Font {
        .system(size: 14, weight: .regular, design: .default)
    }
    
    public static func subheadline() -> Font {
        .system(size: 13, weight: .medium, design: .default)
    }
    
    public static func footnote() -> Font {
        .system(size: 12, weight: .regular, design: .default)
    }
    
    public static func caption() -> Font {
        .system(size: 11, weight: .regular, design: .default)
    }
    
    public static func captionMedium() -> Font {
        .system(size: 11, weight: .medium, design: .default)
    }
}

// MARK: - View Modifiers

public struct PaperCardModifier: ViewModifier {
    public var cornerRadius: CGFloat
    public var padding: CGFloat
    public var withBorder: Bool
    
    public init(
        cornerRadius: CGFloat = AppRadius.lg,
        padding: CGFloat = AppSpacing.lg,
        withBorder: Bool = true
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.withBorder = withBorder
    }
    
    public func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(AppColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(withBorder ? AppColor.inkBorder : Color.clear, lineWidth: 1)
            )
            .shadow(
                color: AppShadow.subtle.color,
                radius: AppShadow.subtle.radius,
                x: AppShadow.subtle.x,
                y: AppShadow.subtle.y
            )
    }
}

public extension View {
    func paperCard(
        cornerRadius: CGFloat = AppRadius.lg,
        padding: CGFloat = AppSpacing.lg,
        withBorder: Bool = true
    ) -> some View {
        modifier(PaperCardModifier(cornerRadius: cornerRadius, padding: padding, withBorder: withBorder))
    }
}

// MARK: - Button Styles

public struct TimeTreePrimaryButtonStyle: ButtonStyle {
    public var isCompact: Bool = false
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.headline())
            .foregroundColor(.white)
            .padding(.vertical, isCompact ? AppSpacing.sm : AppSpacing.md)
            .padding(.horizontal, AppSpacing.lg)
            .frame(maxWidth: isCompact ? nil : .infinity)
            .background(AppColor.accent)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

public struct TimeTreeSecondaryButtonStyle: ButtonStyle {
    public var isCompact: Bool = false
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.headline())
            .foregroundColor(AppColor.accent)
            .padding(.vertical, isCompact ? AppSpacing.sm : AppSpacing.md)
            .padding(.horizontal, AppSpacing.lg)
            .frame(maxWidth: isCompact ? nil : .infinity)
            .background(AppColor.accentLight)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            .opacity(configuration.isPressed ? 0.82 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

public struct TimeTreeCapsuleButtonStyle: ButtonStyle {
    public var isSelected: Bool = false
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.subheadline())
            .foregroundColor(isSelected ? .white : AppColor.inkSecondary)
            .padding(.vertical, AppSpacing.xs + 2)
            .padding(.horizontal, AppSpacing.md)
            .background(isSelected ? AppColor.accent : AppColor.surfaceSubtle)
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Color Hex & Dynamic Helper

public extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }
    
    init(hexString: String, alpha: Double = 1.0) {
        var cleanHex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanHex.hasPrefix("#") {
            cleanHex.removeFirst()
        }
        var rgbValue: UInt64 = 0
        Scanner(string: cleanHex).scanHexInt64(&rgbValue)
        self.init(hex: UInt(rgbValue), alpha: alpha)
    }
    
    init(light: Color, dark: Color) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .dark:
                return UIColor(dark)
            default:
                return UIColor(light)
            }
        })
        #else
        self = light
        #endif
    }
}
