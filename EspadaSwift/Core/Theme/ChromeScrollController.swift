import SwiftUI
import UIKit

/// Auto-hides nav + tab chrome while reading (liked Espada Mobile behavior).
///
/// Scroll **down** → hide; scroll **up** → show.
/// Uses toolbar visibility with a short animation (no max-height / padding collapse).
@Observable
final class ChromeScrollController {
    /// When true, system nav + tab bars hide to maximize reading space.
    private(set) var isHidden = false

    private var lastScrollY: CGFloat?
    /// Ignore tiny jitter from bounce / layout.
    private let threshold: CGFloat = 14
    /// Don't hide until the user has scrolled a bit into content.
    private let hideAfter: CGFloat = 40

    func reportContentMinY(_ minY: CGFloat) {
        // Content minY decreases as user scrolls down.
        defer { lastScrollY = minY }
        guard let last = lastScrollY else { return }
        let delta = minY - last

        if delta < -threshold, minY < -hideAfter {
            setHidden(true)
        } else if delta > threshold {
            setHidden(false)
        }
    }

    /// Always show chrome (tab switch, open picker, etc.).
    func show() {
        setHidden(false)
    }

    private func setHidden(_ hidden: Bool) {
        guard isHidden != hidden else { return }
        withAnimation(.easeInOut(duration: 0.22)) {
            isHidden = hidden
        }
    }
}

// MARK: - Scroll offset tracking (no layout jiggle)

private struct ScrollMinYKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

extension View {
    /// Reports the scroll content's minY so chrome can auto-hide.
    func espadaTrackScrollForChrome(_ chrome: ChromeScrollController) -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: ScrollMinYKey.self,
                    value: geo.frame(in: .named("espadaScroll")).minY
                )
            }
        )
        .onPreferenceChange(ScrollMinYKey.self) { y in
            chrome.reportContentMinY(y)
        }
    }

    /// Coordinate space + chrome visibility for a reading ScrollView.
    func espadaReadingScrollChrome(_ chrome: ChromeScrollController) -> some View {
        coordinateSpace(name: "espadaScroll")
            .onAppear { chrome.show() }
    }
}

extension View {
    /// Apply shared nav/tab auto-hide driven by `ChromeScrollController`.
    func espadaChromeVisibility(_ chrome: ChromeScrollController) -> some View {
        self
            .toolbar(chrome.isHidden ? .hidden : .automatic, for: .navigationBar)
            .toolbar(chrome.isHidden ? .hidden : .automatic, for: .tabBar)
    }
}
