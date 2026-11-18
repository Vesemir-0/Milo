//
//  DesignSystem.swift
//  AIScheduleAssistant
//
//  Modern macOS Design System
//  Milo · the capybara scribe. Approved warm paper palette.
//

import SwiftUI

// MARK: - Design System

enum DesignSystem {

    // MARK: - Colors

    enum Colors {
        // Milo's terracotta accent.
        static let primary = Color(hex: "#B4553A")
        static let primaryHover = Color(hex: "#A54A31")
        static let primaryPressed = Color(hex: "#8D402C")

        // Backgrounds
        static let background = Color(hex: "#F4F0E7")
        static let backgroundSecondary = Color(hex: "#EEE8DF")
        static let backgroundTertiary = Color(hex: "#E8DFD2")

        // Glass needs a chromatic tint, rather than a nearly white opaque wash.
        // These warm pigments retain the paper palette over AppKit's neutral blur.
        static let glassTintTop = Color(hex: "#F1D7AF")
        static let glassTintBottom = Color(hex: "#D9B98D")

        // Surfaces
        static let surface = Color(hex: "#FFFCF6")
        static let surfaceHover = Color(hex: "#F8F3EA")

        // Text
        static let textPrimary = Color(hex: "#45372D")
        static let textSecondary = Color(hex: "#79634F")
        static let textTertiary = Color(hex: "#927A62")
        static let textMetadata = Color(hex: "#846D57")
        static let textQuaternary = Color(hex: "#A3917E")

        // Semantic Colors
        static let success = Color(hex: "#77866A")
        static let warning = Color(hex: "#A6733B")
        static let error = Color(hex: "#AD523D")
        static let info = Color(hex: "#957357")

        // Borders & Dividers
        static let border = Color(hex: "#DCCBB5")
        static let borderHover = Color(hex: "#C8AD8D")
        static let divider = Color(hex: "#DCCBB5").opacity(0.6)

        // Shadows
        static let shadowLight = Color.black.opacity(0.04)
        static let shadowMedium = Color.black.opacity(0.08)
        static let shadowHeavy = Color.black.opacity(0.12)

        // Overlays
        static let overlay = Color.black.opacity(0.4)
        static let overlayLight = Color.black.opacity(0.2)
    }

    // MARK: - Typography

    enum Typography {
        static let largeTitle = Font.system(size: 28, weight: .bold, design: .default)
        static let title1 = Font.system(size: 22, weight: .bold, design: .default)
        static let title2 = Font.system(size: 18, weight: .semibold, design: .default)
        static let title3 = Font.system(size: 16, weight: .semibold, design: .default)
        static let headline = Font.system(size: 15, weight: .semibold, design: .default)
        static let body = Font.system(size: 15, weight: .regular, design: .default)
        static let bodySemibold = Font.system(size: 15, weight: .semibold, design: .default)
        static let callout = Font.system(size: 14, weight: .regular, design: .default)
        static let subheadline = Font.system(size: 13, weight: .regular, design: .default)
        static let footnote = Font.system(size: 12, weight: .regular, design: .default)
        static let caption1 = Font.system(size: 11, weight: .regular, design: .default)
        static let caption2 = Font.system(size: 10, weight: .regular, design: .default)
    }

    // MARK: - Spacing

    enum Spacing {
        static let xxxs: CGFloat = 2
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 6
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
        static let huge: CGFloat = 40
    }

    // MARK: - Corner Radius

    enum CornerRadius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 10
        static let xl: CGFloat = 12
        static let xxl: CGFloat = 16
        static let round: CGFloat = 999  // Fully rounded
    }

    // MARK: - Shadow

    enum Shadow {
        static let light = (color: Colors.shadowLight, radius: CGFloat(4), x: CGFloat(0), y: CGFloat(2))
        static let medium = (color: Colors.shadowMedium, radius: CGFloat(8), x: CGFloat(0), y: CGFloat(4))
        static let heavy = (color: Colors.shadowHeavy, radius: CGFloat(12), x: CGFloat(0), y: CGFloat(6))
    }

    // MARK: - Animation

    enum Animation {
        static let quick = SwiftUI.Animation.easeInOut(duration: 0.15)
        static let normal = SwiftUI.Animation.easeInOut(duration: 0.25)
        static let slow = SwiftUI.Animation.easeInOut(duration: 0.35)
        static let spring = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.7)
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - View Modifiers

struct CardModifier: ViewModifier {
    let shadowStyle: ShadowStyle

    enum ShadowStyle {
        case light, medium, heavy, none
    }

    func body(content: Content) -> some View {
        content
            .background(DesignSystem.Colors.surface)
            .cornerRadius(DesignSystem.CornerRadius.xl)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xl)
                    .strokeBorder(DesignSystem.Colors.border, lineWidth: 0.5)
            )
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
    }

    private var shadowColor: Color {
        switch shadowStyle {
        case .light: return DesignSystem.Shadow.light.color
        case .medium: return DesignSystem.Shadow.medium.color
        case .heavy: return DesignSystem.Shadow.heavy.color
        case .none: return .clear
        }
    }

    private var shadowRadius: CGFloat {
        switch shadowStyle {
        case .light: return DesignSystem.Shadow.light.radius
        case .medium: return DesignSystem.Shadow.medium.radius
        case .heavy: return DesignSystem.Shadow.heavy.radius
        case .none: return 0
        }
    }

    private var shadowY: CGFloat {
        switch shadowStyle {
        case .light: return DesignSystem.Shadow.light.y
        case .medium: return DesignSystem.Shadow.medium.y
        case .heavy: return DesignSystem.Shadow.heavy.y
        case .none: return 0
        }
    }
}

extension View {
    func card(shadow: CardModifier.ShadowStyle = .medium) -> some View {
        modifier(CardModifier(shadowStyle: shadow))
    }
}

// MARK: - Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.Typography.bodySemibold)
            .foregroundColor(.white)
            .padding(.vertical, 10)
            .padding(.horizontal, 20)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                    .fill(backgroundColor(configuration: configuration))
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(DesignSystem.Animation.quick, value: configuration.isPressed)
    }

    private func backgroundColor(configuration: Configuration) -> Color {
        if !isEnabled {
            return DesignSystem.Colors.textQuaternary
        }
        if configuration.isPressed {
            return DesignSystem.Colors.primaryPressed
        }
        return DesignSystem.Colors.primary
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.Typography.body)
            .foregroundColor(isEnabled ? DesignSystem.Colors.textPrimary : DesignSystem.Colors.textTertiary)
            .padding(.vertical, 10)
            .padding(.horizontal, 20)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                    .fill(configuration.isPressed ? DesignSystem.Colors.backgroundTertiary : DesignSystem.Colors.backgroundSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                    .strokeBorder(DesignSystem.Colors.border, lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(DesignSystem.Animation.quick, value: configuration.isPressed)
    }
}

struct DestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.Typography.bodySemibold)
            .foregroundColor(.white)
            .padding(.vertical, 10)
            .padding(.horizontal, 20)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                    .fill(isEnabled ? DesignSystem.Colors.error : DesignSystem.Colors.textQuaternary)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(DesignSystem.Animation.quick, value: configuration.isPressed)
    }
}

// MARK: - Text Field Style

struct ModernTextFieldStyle: TextFieldStyle {
    @FocusState private var isFocused: Bool

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(DesignSystem.Typography.body)
            .foregroundColor(DesignSystem.Colors.textPrimary)
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.backgroundSecondary)
            .cornerRadius(DesignSystem.CornerRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                    .strokeBorder(
                        isFocused ? DesignSystem.Colors.primary : DesignSystem.Colors.border,
                        lineWidth: isFocused ? 1.5 : 0.5
                    )
            )
    }
}

// MARK: - Components

struct SectionHeader: View {
    let title: String
    let icon: String?

    init(_ title: String, icon: String? = nil) {
        self.title = title
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(DesignSystem.Typography.headline)
                    .foregroundColor(DesignSystem.Colors.primary)
            }

            Text(title)
                .font(DesignSystem.Typography.headline)
                .foregroundColor(DesignSystem.Colors.textPrimary)

            Spacer()
        }
    }
}

struct Badge: View {
    let text: String
    let color: Color
    let icon: String?

    init(_ text: String, color: Color = DesignSystem.Colors.primary, icon: String? = nil) {
        self.text = text
        self.color = color
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 4) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(DesignSystem.Typography.caption1)
            }
            Text(text)
                .font(DesignSystem.Typography.caption1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12))
        .foregroundColor(color)
        .cornerRadius(DesignSystem.CornerRadius.sm)
    }
}

struct ModernDivider: View {
    var body: some View {
        Rectangle()
            .fill(DesignSystem.Colors.divider)
            .frame(height: 0.5)
    }
}

struct LoadingView: View {
    let message: String

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            ProgressView()
                .scaleEffect(1.2)
            Text(message)
                .font(DesignSystem.Typography.callout)
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
        .padding(DesignSystem.Spacing.xxxl)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(DesignSystem.Colors.textQuaternary)

            VStack(spacing: DesignSystem.Spacing.xs) {
                Text(title)
                    .font(DesignSystem.Typography.title3)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Text(message)
                    .font(DesignSystem.Typography.callout)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(DesignSystem.Spacing.xxxl)
    }
}
