import SwiftUI

/// Cold-start splash: parchment scroll unfurling while the first chapter loads.
/// Scales up cleanly on iPad (regular width / pad idiom).
struct ScrollLoadingView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// 0 = closed, 1 = fully open
    @State private var openAmount: CGFloat = 0

    /// Soft baby-blue wash (calm, readable, works with parchment + wood).
    private let skyTop = Color(red: 0.78, green: 0.90, blue: 0.98)
    private let skyBottom = Color(red: 0.62, green: 0.80, blue: 0.94)
    private let wood = Color(red: 0.55, green: 0.42, blue: 0.22)
    private let woodHighlight = Color(red: 0.68, green: 0.54, blue: 0.32)
    private let parchment = Color(red: 0.96, green: 0.91, blue: 0.78)
    private let ink = Color(red: 0.35, green: 0.28, blue: 0.18)

    /// iPad / wide layout gets a larger, more centered scroll.
    private var isWide: Bool {
        EspadaAdaptive.prefersWideChrome(horizontalSizeClass: horizontalSizeClass)
    }

    private var scale: CGFloat { isWide ? 1.55 : 1.0 }
    private var cylinderWidth: CGFloat { 18 * scale }
    private var cylinderHeight: CGFloat { 90 * scale }
    private var parchmentHeight: CGFloat { 78 * scale }
    private var parchmentBaseWidth: CGFloat { 36 * scale }
    private var parchmentOpenExtra: CGFloat { 168 * scale }
    private var titleSize: CGFloat { isWide ? 34 : 22 }
    private var messageSize: CGFloat { isWide ? 18 : 13 }
    private var stackSpacing: CGFloat { isWide ? 40 : 28 }
    private var vignetteRadius: CGFloat { isWide ? 480 : 280 }
    private var shadowRadius: CGFloat { isWide ? 28 : 18 }

    var body: some View {
        GeometryReader { geo in
            let shortSide = min(geo.size.width, geo.size.height)
            ZStack {
                LinearGradient(
                    colors: [skyTop, skyBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                // Soft vignette — scales with screen so iPad isn’t empty at the edges
                RadialGradient(
                    colors: [
                        Color.white.opacity(0.28),
                        Color.white.opacity(0.08),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: shortSide * 0.04,
                    endRadius: max(vignetteRadius, shortSide * 0.42)
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                VStack(spacing: stackSpacing) {
                    scrollGraphic

                    Text("Espada")
                        .font(.system(size: titleSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 0.18, green: 0.32, blue: 0.48).opacity(0.85))
                        .opacity(0.55 + 0.45 * openAmount)

                    if isWide {
                        Text("Estudio bíblico offline")
                            .font(.system(size: messageSize - 2, weight: .regular, design: .rounded))
                            .foregroundStyle(Color(red: 0.22, green: 0.38, blue: 0.52).opacity(0.65))
                            .opacity(0.4 + 0.5 * openAmount)
                    }
                }
                .frame(maxWidth: isWide ? min(640, geo.size.width * 0.72) : .infinity)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(
                .easeInOut(duration: 1.55)
                .repeatForever(autoreverses: true)
            ) {
                openAmount = 1
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cargando la Palabra")
    }

    private var scrollGraphic: some View {
        HStack(spacing: 0) {
            cylinder

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            parchment.opacity(0.95),
                            parchment,
                            parchment.opacity(0.92)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(
                    width: parchmentBaseWidth + (openAmount * parchmentOpenExtra),
                    height: parchmentHeight
                )
                .overlay(alignment: .center) {
                    if openAmount > 0.55 {
                        Text("Cargando la Palabra…")
                            .font(.system(size: messageSize, weight: .medium, design: .rounded))
                            .foregroundStyle(ink)
                            .opacity(Double((openAmount - 0.55) / 0.45))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.horizontal, isWide ? 16 : 8)
                    }
                }
                .overlay {
                    // Subtle paper lines
                    VStack(spacing: isWide ? 14 : 10) {
                        ForEach(0..<(isWide ? 5 : 4), id: \.self) { _ in
                            Rectangle()
                                .fill(ink.opacity(0.06))
                                .frame(height: 1)
                        }
                    }
                    .padding(.horizontal, isWide ? 22 : 14)
                    .opacity(openAmount)
                }
                .clipShape(RoundedRectangle(cornerRadius: isWide ? 3 : 2, style: .continuous))

            cylinder
        }
        .shadow(
            color: Color(red: 0.25, green: 0.40, blue: 0.55).opacity(0.22),
            radius: shadowRadius,
            y: isWide ? 14 : 10
        )
    }

    private var cylinder: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [woodHighlight, wood, wood.opacity(0.9)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: cylinderWidth, height: cylinderHeight)
            .overlay(
                Capsule()
                    .strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
    }
}

#Preview("iPhone") {
    ScrollLoadingView()
}

#Preview("iPad", traits: .landscapeLeft) {
    ScrollLoadingView()
}
