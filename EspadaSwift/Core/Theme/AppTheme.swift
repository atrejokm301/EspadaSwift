import SwiftUI
import UIKit

enum AppTheme: String, CaseIterable, Identifiable, Codable, Sendable {
    case trueDark
    case plainWhite
    /// Indoor reading default: aged-paper warmth without banana-yellow sepia.
    case warmPaper
    /// Max legibility: pure white canvas, near-black ink, strong edges.
    case highContrast
    case pastelGreen
    case pastelYellow
    case lightBlue
    case pastelRose
    case mutedLila

    var id: String { rawValue }

    var label: String {
        switch self {
        case .trueDark: return "True Dark"
        case .plainWhite: return "Plain White"
        case .warmPaper: return "Warm Paper"
        case .highContrast: return "High Contrast"
        case .pastelGreen: return "Pastel Green"
        case .pastelYellow: return "Pastel Yellow"
        case .lightBlue: return "Light Blue"
        case .pastelRose: return "Pastel Rose"
        case .mutedLila: return "Muted Lila"
        }
    }

    /// Short Spanish subtitle for accessibility / picker hints.
    var accessibilityHint: String {
        switch self {
        case .trueDark: return "Fondo negro, ideal de noche"
        case .plainWhite: return "Claro neutro"
        case .warmPaper: return "Papel cálido para lectura interior"
        case .highContrast: return "Máximo contraste de texto"
        case .pastelGreen: return "Verde suave"
        case .pastelYellow: return "Amarillo pastel"
        case .lightBlue: return "Azul claro"
        case .pastelRose: return "Rosa suave"
        case .mutedLila: return "Lila apagado"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .trueDark: return .dark
        default: return .light
        }
    }

    /// Whether chrome blur should use dark materials.
    var usesDarkChrome: Bool {
        preferredColorScheme == .dark
    }

    /// Full-screen canvas + chrome (nav / tab). True Dark is pure black.
    var background: Color {
        switch self {
        case .trueDark: return .black
        case .plainWhite: return Color(red: 0.96, green: 0.96, blue: 0.97)
        // Warm paper ≈ #F4EDE4 — peach-cream, not lemon sepia.
        case .warmPaper: return Color(red: 0.957, green: 0.929, blue: 0.894)
        case .highContrast: return .white
        case .pastelGreen: return Color(red: 0.90, green: 0.96, blue: 0.92)
        case .pastelYellow: return Color(red: 0.97, green: 0.94, blue: 0.84)
        case .lightBlue: return Color(red: 0.88, green: 0.93, blue: 0.98)
        case .pastelRose: return Color(red: 1.0, green: 0.92, blue: 0.93)
        // Soft dusty lilac wash (not neon purple)
        case .mutedLila: return Color(red: 0.93, green: 0.90, blue: 0.95)
        }
    }

    /// Cards / rows slightly elevated but still on-theme (no system gray).
    var card: Color {
        switch self {
        case .trueDark: return Color(white: 0.06) // near-black, not gray midtones
        case .plainWhite: return .white
        // Slightly brighter sheet on the paper field (#FAF6F0)
        case .warmPaper: return Color(red: 0.980, green: 0.965, blue: 0.941)
        case .highContrast: return .white
        case .pastelGreen: return Color(red: 0.96, green: 0.99, blue: 0.97)
        case .pastelYellow: return Color(red: 0.99, green: 0.97, blue: 0.90)
        case .lightBlue: return Color(red: 0.95, green: 0.97, blue: 1.0)
        case .pastelRose: return Color(red: 1.0, green: 0.96, blue: 0.97)
        case .mutedLila: return Color(red: 0.97, green: 0.95, blue: 0.99)
        }
    }

    var primaryText: Color {
        switch self {
        case .trueDark: return Color(white: 0.96)
        case .plainWhite: return Color(white: 0.08)
        // Warm ink — soft brown-black, easier than pure black on cream paper.
        case .warmPaper: return Color(red: 0.20, green: 0.16, blue: 0.12)
        case .highContrast: return .black
        case .pastelGreen: return Color(red: 0.08, green: 0.24, blue: 0.14)
        case .pastelYellow: return Color(red: 0.24, green: 0.18, blue: 0.06)
        case .lightBlue: return Color(red: 0.06, green: 0.16, blue: 0.30)
        case .pastelRose: return Color(red: 0.30, green: 0.10, blue: 0.14)
        case .mutedLila: return Color(red: 0.22, green: 0.14, blue: 0.32)
        }
    }

    var secondaryText: Color {
        switch self {
        case .trueDark: return Color(white: 0.62)
        case .plainWhite: return Color(white: 0.38)
        case .warmPaper: return Color(red: 0.42, green: 0.35, blue: 0.28)
        case .highContrast: return Color(white: 0.18)
        case .pastelGreen: return Color(red: 0.26, green: 0.44, blue: 0.32)
        case .pastelYellow: return Color(red: 0.46, green: 0.38, blue: 0.20)
        case .lightBlue: return Color(red: 0.28, green: 0.40, blue: 0.54)
        case .pastelRose: return Color(red: 0.52, green: 0.32, blue: 0.36)
        case .mutedLila: return Color(red: 0.44, green: 0.36, blue: 0.52)
        }
    }

    var accent: Color {
        switch self {
        case .trueDark: return Color(red: 0.50, green: 0.66, blue: 1.0)
        case .plainWhite: return Color(red: 0.0, green: 0.40, blue: 0.90)
        // Walnut / warm leather bookmark tone
        case .warmPaper: return Color(red: 0.55, green: 0.35, blue: 0.18)
        case .highContrast: return Color(red: 0.0, green: 0.30, blue: 0.85)
        case .pastelGreen: return Color(red: 0.14, green: 0.50, blue: 0.32)
        case .pastelYellow: return Color(red: 0.70, green: 0.48, blue: 0.04)
        case .lightBlue: return Color(red: 0.08, green: 0.38, blue: 0.78)
        case .pastelRose: return Color(red: 0.76, green: 0.24, blue: 0.36)
        // Muted violet-lila accent
        case .mutedLila: return Color(red: 0.52, green: 0.38, blue: 0.66)
        }
    }

    var selectionFill: Color {
        accent.opacity(preferredColorScheme == .dark ? 0.26 : 0.14)
    }

    var selectionStroke: Color {
        accent.opacity(0.45)
    }

    var hairline: Color {
        switch self {
        case .trueDark:
            return Color.white.opacity(0.10)
        case .highContrast:
            return Color.black.opacity(0.28)
        case .warmPaper:
            return Color(red: 0.45, green: 0.32, blue: 0.18).opacity(0.14)
        default:
            return Color.black.opacity(0.07)
        }
    }

    /// Classic red-letter Bible color for Words of Christ (readable on light + dark).
    var wordsOfChrist: Color {
        switch self {
        case .trueDark:
            return Color(red: 1.0, green: 0.38, blue: 0.38) // brighter on pure black
        case .warmPaper:
            // Slightly brick-warmer so red letters sit naturally on cream paper
            return Color(red: 0.72, green: 0.16, blue: 0.12)
        case .highContrast:
            return Color(red: 0.75, green: 0.0, blue: 0.0)
        default:
            return Color(red: 0.70, green: 0.12, blue: 0.12) // classic #B31F1F family
        }
    }

    var swatchColors: [Color] {
        switch self {
        case .trueDark: return [.black, Color(white: 0.06)]
        case .plainWhite: return [background, .white]
        case .warmPaper: return [background, Color(red: 0.90, green: 0.82, blue: 0.70)]
        case .highContrast: return [.white, .black]
        case .pastelGreen: return [background, Color(red: 0.55, green: 0.82, blue: 0.65)]
        case .pastelYellow: return [background, Color(red: 0.95, green: 0.82, blue: 0.40)]
        case .lightBlue: return [background, Color(red: 0.45, green: 0.70, blue: 0.95)]
        case .pastelRose: return [background, Color(red: 0.95, green: 0.60, blue: 0.66)]
        case .mutedLila: return [background, Color(red: 0.72, green: 0.62, blue: 0.84)]
        }
    }

    // MARK: UIKit chrome colors (nav / tab must match or they go gray)

    var uiBackground: UIColor {
        switch self {
        case .trueDark: return .black
        case .plainWhite: return UIColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1)
        case .warmPaper: return UIColor(red: 0.957, green: 0.929, blue: 0.894, alpha: 1)
        case .highContrast: return .white
        case .pastelGreen: return UIColor(red: 0.90, green: 0.96, blue: 0.92, alpha: 1)
        case .pastelYellow: return UIColor(red: 0.97, green: 0.94, blue: 0.84, alpha: 1)
        case .lightBlue: return UIColor(red: 0.88, green: 0.93, blue: 0.98, alpha: 1)
        case .pastelRose: return UIColor(red: 1.0, green: 0.92, blue: 0.93, alpha: 1)
        case .mutedLila: return UIColor(red: 0.93, green: 0.90, blue: 0.95, alpha: 1)
        }
    }

    var uiPrimaryText: UIColor {
        switch self {
        case .trueDark: return UIColor(white: 0.96, alpha: 1)
        case .plainWhite: return UIColor(white: 0.08, alpha: 1)
        case .warmPaper: return UIColor(red: 0.20, green: 0.16, blue: 0.12, alpha: 1)
        case .highContrast: return .black
        case .pastelGreen: return UIColor(red: 0.08, green: 0.24, blue: 0.14, alpha: 1)
        case .pastelYellow: return UIColor(red: 0.24, green: 0.18, blue: 0.06, alpha: 1)
        case .lightBlue: return UIColor(red: 0.06, green: 0.16, blue: 0.30, alpha: 1)
        case .pastelRose: return UIColor(red: 0.30, green: 0.10, blue: 0.14, alpha: 1)
        case .mutedLila: return UIColor(red: 0.22, green: 0.14, blue: 0.32, alpha: 1)
        }
    }

}

// MARK: - Theme + reading size

@Observable
final class ThemeManager {
    var theme: AppTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: "espada.theme")
            applySystemChrome()
        }
    }

    /// Body text size for study content (Bible / commentary / dict / lex).
    /// 12…50: normal reading ≈16–22; large print / accessibility up to 50.
    static let minBodyFontSize: Double = 12
    static let maxBodyFontSize: Double = 50
    static let defaultBodyFontSize: Double = 18

    var bodyFontSize: Double {
        didSet {
            let clamped = min(Self.maxBodyFontSize, max(Self.minBodyFontSize, bodyFontSize.rounded()))
            if clamped != bodyFontSize { bodyFontSize = clamped; return }
            UserDefaults.standard.set(bodyFontSize, forKey: "espada.bodyFontSize")
        }
    }

    /// Latin reading face (Spanish / UI body). Hebrew & Greek always use Libertinus Serif.
    var readingFontFamily: ReadingFontFamily {
        didSet {
            UserDefaults.standard.set(readingFontFamily.rawValue, forKey: "espada.readingFontFamily")
        }
    }

    /// Study body text uses the selected Latin family (not Libertinus).
    var bodyFont: Font { BibleFont.body(size: bodyFontSize, family: readingFontFamily) }
    var headlineFont: Font { BibleFont.semiBold(size: bodyFontSize + 2, family: readingFontFamily) }
    var titleFont: Font { BibleFont.bold(size: bodyFontSize + 4, family: readingFontFamily) }
    var captionFont: Font { BibleFont.caption(size: bodyFontSize, family: readingFontFamily) }
    var footnoteFont: Font { BibleFont.body(size: max(11, bodyFontSize - 5), family: readingFontFamily) }

    init() {
        if let raw = UserDefaults.standard.string(forKey: "espada.theme"),
           let t = AppTheme(rawValue: raw) {
            theme = t
        } else {
            theme = .trueDark
        }
        let stored = UserDefaults.standard.object(forKey: "espada.bodyFontSize") as? Double
        bodyFontSize = min(
            Self.maxBodyFontSize,
            max(Self.minBodyFontSize, stored ?? Self.defaultBodyFontSize)
        )
        if let fr = UserDefaults.standard.string(forKey: "espada.readingFontFamily"),
           let fam = ReadingFontFamily(rawValue: fr) {
            readingFontFamily = fam
        } else {
            readingFontFamily = .googleSansFlex
        }
        applySystemChrome()
    }

    /// Theme nav/tab for **true Liquid Glass**.
    ///
    /// `UIBarAppearance.backgroundEffect` is typed as `UIBlurEffect` only — assigning
    /// a blur **replaces** system Liquid Glass with legacy frost. On iOS 26+, leave
    /// the effect nil / use the default background so the system glass material runs,
    /// and only soft-tint with `backgroundColor`. Custom chrome (Bible tools strip)
    /// uses SwiftUI `.glassEffect` / `UIGlassEffect` separately.
    ///
    /// Never force `isTranslucent = false` on UITabBar (creates a giant solid bar).
    func applySystemChrome() {
        let fg = theme.uiPrimaryText
        let accentUI = UIColor(theme.accent)
        let muted = theme.preferredColorScheme == .dark
            ? UIColor(white: 0.55, alpha: 1)
            : UIColor(white: 0.45, alpha: 1)
        let reduceTransparency = UIAccessibility.isReduceTransparencyEnabled
        // Soft theme wash over system glass (not a solid plate).
        let softTint = UIColor(theme.liquidGlassTintColor(for: .chrome))

        let nav = UINavigationBarAppearance()
        if reduceTransparency {
            nav.configureWithOpaqueBackground()
            nav.backgroundColor = theme.uiBackground
            nav.backgroundEffect = nil
        } else {
            // Default background → system Liquid Glass on iOS 26+ (not UIBlurEffect).
            nav.configureWithDefaultBackground()
            nav.backgroundEffect = nil
            nav.backgroundColor = softTint
        }
        nav.shadowColor = .clear
        nav.titleTextAttributes = [
            .foregroundColor: fg,
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold),
        ]
        nav.largeTitleTextAttributes = [
            .foregroundColor: fg,
            .font: UIFont.systemFont(ofSize: 28, weight: .bold),
        ]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().compactScrollEdgeAppearance = nav
        UINavigationBar.appearance().tintColor = accentUI
        UINavigationBar.appearance().isTranslucent = true

        let tab = UITabBarAppearance()
        if reduceTransparency {
            tab.configureWithOpaqueBackground()
            tab.backgroundColor = theme.uiBackground
            tab.backgroundEffect = nil
        } else {
            tab.configureWithDefaultBackground()
            tab.backgroundEffect = nil
            tab.backgroundColor = softTint
        }
        tab.shadowColor = .clear

        let item = UITabBarItemAppearance()
        item.normal.iconColor = muted
        item.normal.titleTextAttributes = [.foregroundColor: muted]
        item.selected.iconColor = accentUI
        item.selected.titleTextAttributes = [.foregroundColor: accentUI]
        tab.stackedLayoutAppearance = item
        tab.inlineLayoutAppearance = item
        tab.compactInlineLayoutAppearance = item

        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
        UITabBar.appearance().tintColor = accentUI
        UITabBar.appearance().unselectedItemTintColor = muted
        UITabBar.appearance().isTranslucent = true
    }
}

// MARK: - Shared chrome

extension View {
    /// Screen canvas + translucent themed navigation (glass, not solid gray).
    func espadaThemedScreen() -> some View {
        modifier(EspadaThemedScreenModifier())
    }

    /// Liquid Glass sheet: refracts the reading surface behind the modal.
    func espadaFrostedSheet() -> some View {
        modifier(EspadaFrostedSheetModifier())
    }
}

/// Subtle paper atmosphere for Warm Paper — soft radial cream, not a heavy filter.
/// Prefer solid theme colors for text; this only deepens the field edges slightly.
struct WarmPaperAtmosphere: View {
    var body: some View {
        ZStack {
            // Base is already warmPaper.background from the screen; this adds depth only.
            RadialGradient(
                colors: [
                    Color(red: 0.99, green: 0.97, blue: 0.94).opacity(0.55),
                    Color.clear,
                ],
                center: .center,
                startRadius: 40,
                endRadius: 520
            )
            // Very soft top warmth (like light through a window, not a yellow cast).
            LinearGradient(
                colors: [
                    Color(red: 0.92, green: 0.82, blue: 0.68).opacity(0.07),
                    Color.clear,
                ],
                startPoint: .top,
                endPoint: .center
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct EspadaThemedScreenModifier: ViewModifier {
    @Environment(ThemeManager.self) private var themes

    func body(content: Content) -> some View {
        // Hide SwiftUI’s solid toolbar fill so UIKit `UIGlassEffect` (from
        // `ThemeManager.applySystemChrome`) can render true Liquid Glass on
        // both iPhone and iPad. Content scrolls under the bar and refracts.
        content
            .background { readingCanvas }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(themes.theme.preferredColorScheme, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var readingCanvas: some View {
        ZStack {
            themes.theme.background
            if themes.theme == .warmPaper {
                WarmPaperAtmosphere()
            }
        }
        .ignoresSafeArea()
    }
}

private struct EspadaFrostedSheetModifier: ViewModifier {
    @Environment(ThemeManager.self) private var themes
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isWide: Bool {
        EspadaAdaptive.prefersWideChrome(horizontalSizeClass: horizontalSizeClass)
    }

    func body(content: Content) -> some View {
        let theme = themes.theme
        content
            .presentationBackground {
                EspadaGlassBackground(style: .sheet)
            }
            .presentationCornerRadius(isWide ? 20 : 28)
            .presentationDragIndicator(.visible)
            .toolbarColorScheme(theme.preferredColorScheme, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

// MARK: - Highlight colors

enum HighlightColor: String, CaseIterable, Identifiable, Codable, Sendable {
    case yellow, green, blue, pink, orange, purple

    var id: String { rawValue }

    var label: String {
        switch self {
        case .yellow: return "Amarillo"
        case .green: return "Verde"
        case .blue: return "Azul"
        case .pink: return "Rosa"
        case .orange: return "Naranja"
        case .purple: return "Violeta"
        }
    }

    var color: Color {
        switch self {
        case .yellow: return Color.yellow.opacity(0.40)
        case .green: return Color.green.opacity(0.32)
        case .blue: return Color.blue.opacity(0.32)
        case .pink: return Color.pink.opacity(0.36)
        case .orange: return Color.orange.opacity(0.36)
        case .purple: return Color.purple.opacity(0.32)
        }
    }

    var swatch: Color {
        switch self {
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .pink: return .pink
        case .orange: return .orange
        case .purple: return .purple
        }
    }
}

