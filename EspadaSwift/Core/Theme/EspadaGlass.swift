import SwiftUI
import UIKit

// MARK: - Glass styles

/// Surfaces that share one continuous Liquid Glass system
/// (nav bar · control strip · tab dock · chips · sheets).
enum EspadaGlassStyle: String, CaseIterable, Sendable {
    /// Nav / tab / Bible tools strip — continuous chrome
    case chrome
    /// Modal sheets & pickers
    case sheet
    /// Small chips sitting *on* chrome (book pill, icon buttons)
    case chip
}

// MARK: - Theme → Liquid Glass tokens

extension AppTheme {
    /// SwiftUI Liquid Glass recipe for custom views (`.glassEffect`).
    /// - Chrome/sheet: regular glass + soft theme tint (reads content underneath).
    /// - Chip: clear glass (non-interactive by default — interactive steals button hits / popovers).
    func liquidGlass(for style: EspadaGlassStyle, interactive: Bool = false) -> Glass {
        var glass: Glass
        switch style {
        case .chrome, .sheet:
            glass = .regular
        case .chip:
            // Clearer so chips can sit on a glass chrome strip without mud.
            glass = .clear
        }

        // Theme-aware tint — subtle so verse text still refracts through.
        let tint = liquidGlassTintColor(for: style)
        glass = glass.tint(tint)

        // Never auto-enable interactive for chips — breaks Button + .popover hit testing.
        if interactive {
            glass = glass.interactive()
        }
        return glass
    }

    /// Soft tint sampled from the theme canvas (not a heavy solid overlay).
    func liquidGlassTintColor(for style: EspadaGlassStyle) -> Color {
        let opacity: Double
        switch (self, style) {
        case (.highContrast, .chrome): opacity = 0.55
        case (.highContrast, .sheet): opacity = 0.45
        case (.highContrast, .chip): opacity = 0.40
        case (.warmPaper, .chrome): opacity = 0.28
        case (.warmPaper, .sheet): opacity = 0.22
        case (.warmPaper, .chip): opacity = 0.18
        case (.trueDark, .chrome): opacity = 0.35
        case (.trueDark, .sheet): opacity = 0.28
        case (.trueDark, .chip): opacity = 0.22
        case (_, .chrome): opacity = 0.24
        case (_, .sheet): opacity = 0.18
        case (_, .chip): opacity = 0.14
        }
        return background.opacity(opacity)
    }

    /// UIKit Liquid Glass for system nav / tab appearances (`UIGlassEffect`).
    func uiGlassEffect(for style: EspadaGlassStyle, interactive: Bool = false) -> UIGlassEffect {
        let effectStyle: UIGlassEffect.Style
        switch style {
        case .chrome, .sheet:
            effectStyle = .regular
        case .chip:
            effectStyle = .clear
        }
        let effect = UIGlassEffect(style: effectStyle)
        effect.isInteractive = interactive
        effect.tintColor = UIColor(liquidGlassTintColor(for: style))
        return effect
    }

    // MARK: Legacy material helpers (kept for reduce-transparency fallbacks)

    /// Solid / material fallback when Reduce Transparency is on.
    var glassMaterial: Material {
        usesDarkChrome ? .ultraThinMaterial : .thinMaterial
    }

    func glassBlurStyle(for style: EspadaGlassStyle) -> UIBlurEffect.Style {
        if usesDarkChrome {
            switch style {
            case .chrome: return .systemUltraThinMaterialDark
            case .sheet: return .systemThinMaterialDark
            case .chip: return .systemUltraThinMaterialDark
            }
        }
        if self == .warmPaper {
            switch style {
            case .chrome: return .systemThinMaterialLight
            case .sheet: return .systemUltraThinMaterialLight
            case .chip: return .systemUltraThinMaterialLight
            }
        }
        switch style {
        case .chrome: return .systemUltraThinMaterialLight
        case .sheet: return .systemUltraThinMaterialLight
        case .chip: return .systemUltraThinMaterialLight
        }
    }

    func glassTintOpacity(for style: EspadaGlassStyle, wide: Bool = false) -> Double {
        let padBoost = wide ? 0.06 : 0
        if usesDarkChrome {
            switch style {
            case .chrome: return min(0.72, 0.55 + padBoost)
            case .sheet: return min(0.55, 0.40 + padBoost)
            case .chip: return 0.35
            }
        }
        if self == .warmPaper {
            switch style {
            case .chrome: return min(0.58, 0.48 + padBoost)
            case .sheet: return min(0.42, 0.32 + padBoost)
            case .chip: return 0.32
            }
        }
        if self == .highContrast {
            switch style {
            case .chrome: return min(0.70, 0.58 + padBoost)
            case .sheet: return min(0.55, 0.42 + padBoost)
            case .chip: return 0.40
            }
        }
        switch style {
        case .chrome: return min(0.55, 0.42 + padBoost)
        case .sheet: return min(0.40, 0.28 + padBoost)
        case .chip: return 0.30
        }
    }

    /// UIKit nav/tab tint for reduce-transparency / pre-glass fallbacks.
    var uiGlassTint: UIColor {
        let wide = EspadaAdaptive.isPadDevice
        return uiBackground.withAlphaComponent(CGFloat(glassTintOpacity(for: .chrome, wide: wide)))
    }

    /// Legacy alias used by sheets.
    var uiBlurStyle: UIBlurEffect.Style { glassBlurStyle(for: .sheet) }
}

// MARK: - UIKit Liquid Glass representable (wide iPad bars, sheets)

/// Full-bleed `UIVisualEffectView` with **true** `UIGlassEffect` (iOS 26+).
/// Expands correctly in wide SwiftUI frames where plain representables often collapse.
struct LiquidGlassEffectView: UIViewRepresentable {
    var style: EspadaGlassStyle
    var tint: UIColor?
    var interactive: Bool = false

    final class Coordinator {
        var effectView: UIVisualEffectView?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear
        container.isUserInteractionEnabled = false

        let glass = UIGlassEffect(style: style == .chip ? .clear : .regular)
        glass.isInteractive = interactive
        glass.tintColor = tint

        let effectView = UIVisualEffectView(effect: glass)
        effectView.translatesAutoresizingMaskIntoConstraints = false
        effectView.isUserInteractionEnabled = false
        container.addSubview(effectView)
        NSLayoutConstraint.activate([
            effectView.topAnchor.constraint(equalTo: container.topAnchor),
            effectView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            effectView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
        context.coordinator.effectView = effectView

        container.setContentHuggingPriority(.defaultLow, for: .horizontal)
        container.setContentHuggingPriority(.defaultLow, for: .vertical)
        container.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        container.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let glass = UIGlassEffect(style: style == .chip ? .clear : .regular)
        glass.isInteractive = interactive
        glass.tintColor = tint
        context.coordinator.effectView?.effect = glass
    }
}

/// Legacy name — still used at a few call sites; maps to Liquid Glass.
struct VisualEffectBlur: UIViewRepresentable {
    var style: UIBlurEffect.Style

    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: style)
    }
}

// MARK: - Shared glass fill

/// One recipe for chrome: **true Liquid Glass** that refracts scrolling content.
struct EspadaGlassBackground: View {
    @Environment(ThemeManager.self) private var themes
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var style: EspadaGlassStyle = .chrome

    private var isWide: Bool {
        EspadaAdaptive.prefersWideChrome(horizontalSizeClass: horizontalSizeClass)
    }

    var body: some View {
        let theme = themes.theme
        Group {
            if reduceTransparency {
                // Accessibility: no refraction — solid themed veil.
                Rectangle()
                    .fill(theme.background.opacity(theme.glassTintOpacity(for: style, wide: isWide) + 0.25))
            } else if isWide {
                // Wide iPad sheets: UIKit UIGlassEffect expands edge-to-edge reliably.
                LiquidGlassEffectView(
                    style: style,
                    tint: UIColor(theme.liquidGlassTintColor(for: style)),
                    interactive: false
                )
            } else {
                // iPhone: SwiftUI Liquid Glass (single layer — never stack glass on glass).
                Rectangle()
                    .fill(.clear)
                    .glassEffect(theme.liquidGlass(for: style), in: Rectangle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

// MARK: - View modifiers

extension View {
    /// Full-width chrome strip (Bible tools, module toolbars). True Liquid Glass.
    func espadaGlassChromeBar() -> some View {
        modifier(EspadaGlassChromeBarModifier())
    }

    /// Alias kept for call sites that said "banner".
    func espadaGlassBanner() -> some View {
        espadaGlassChromeBar()
    }

    /// Control chips on a glass chrome bar.
    /// Default is a solid elevated pill (reliable taps + popovers). Pass `liquid: true`
    /// only for decorative non-button surfaces.
    func espadaGlassChip(shape: some Shape, liquid: Bool = false) -> some View {
        modifier(EspadaGlassChipModifier(shape: shape, liquid: liquid))
    }

    /// Apply system-matching glass button style when Liquid Glass is allowed.
    func espadaGlassButtonStyle() -> some View {
        modifier(EspadaGlassButtonStyleModifier())
    }
}

private struct EspadaGlassChromeBarModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(ThemeManager.self) private var themes

    private var isWide: Bool {
        EspadaAdaptive.prefersWideChrome(horizontalSizeClass: horizontalSizeClass)
    }

    func body(content: Content) -> some View {
        let theme = themes.theme
        // Single Liquid Glass layer — refracts verse text scrolling under the strip.
        content
            .frame(maxWidth: .infinity)
            .background {
                Group {
                    if reduceTransparency {
                        Rectangle()
                            .fill(theme.background.opacity(theme.glassTintOpacity(for: .chrome, wide: isWide) + 0.3))
                    } else if isWide {
                        LiquidGlassEffectView(
                            style: .chrome,
                            tint: UIColor(theme.liquidGlassTintColor(for: .chrome))
                        )
                    } else {
                        Color.clear
                            .glassEffect(theme.liquidGlass(for: .chrome), in: Rectangle())
                    }
                }
                .ignoresSafeArea(edges: isWide ? .horizontal : [])
            }
    }
}

private struct EspadaGlassChipModifier<S: Shape>: ViewModifier {
    @Environment(ThemeManager.self) private var themes
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let shape: S
    /// When true, use `.glassEffect` (non-interactive). Default solid lift for controls.
    var liquid: Bool = false

    func body(content: Content) -> some View {
        let theme = themes.theme
        // Solid elevated chip sits *on* the liquid chrome bar.
        // Liquid/interactive glass on the label steals taps and breaks popovers (Recientes / CR).
        if liquid, !reduceTransparency {
            content
                .glassEffect(theme.liquidGlass(for: .chip, interactive: false), in: shape)
        } else {
            content
                .background(
                    shape.fill(
                        theme.usesDarkChrome
                            ? Color.white.opacity(0.12)
                            : theme.card
                    )
                )
                .overlay(shape.stroke(theme.hairline.opacity(0.9), lineWidth: 0.5))
        }
    }
}

private struct EspadaGlassButtonStyleModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.buttonStyle(.bordered)
        } else {
            content.buttonStyle(.glass)
        }
    }
}
