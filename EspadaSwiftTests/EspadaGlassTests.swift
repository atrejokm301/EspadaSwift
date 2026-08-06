import XCTest
import SwiftUI
@testable import Espada

final class EspadaGlassTests: XCTestCase {

    func testAllStylesHaveLiquidGlassRecipes() {
        for theme in AppTheme.allCases {
            for style in EspadaGlassStyle.allCases {
                // Touch the recipe so it must compile and return a Glass value.
                let glass = theme.liquidGlass(for: style, interactive: style == .chip)
                // Tint is always applied — non-optional pipeline.
                _ = glass
                let ui = theme.uiGlassEffect(for: style, interactive: false)
                XCTAssertNotNil(ui.tintColor, "\(theme) \(style) should tint UIGlassEffect")
            }
        }
    }

    func testChromeTintIsStrongerThanChip() {
        // Relative opacity in liquidGlassTintColor: chrome > chip for readability of bars.
        for theme in [AppTheme.warmPaper, .trueDark, .plainWhite, .highContrast] {
            let chrome = theme.liquidGlassTintColor(for: .chrome)
            let chip = theme.liquidGlassTintColor(for: .chip)
            // Resolve opacities via UIColor components as a smoke check that both exist.
            XCTAssertNotEqual(
                UIColor(chrome).cgColor.alpha,
                0,
                "\(theme) chrome tint alpha"
            )
            XCTAssertLessThan(
                UIColor(chip).cgColor.alpha,
                UIColor(chrome).cgColor.alpha + 0.001,
                "\(theme) chip should not be more opaque than chrome"
            )
        }
    }

    func testHighContrastChromeIsMostOpaqueAmongLightThemes() {
        let hc = UIColor(AppTheme.highContrast.liquidGlassTintColor(for: .chrome)).cgColor.alpha
        let paper = UIColor(AppTheme.warmPaper.liquidGlassTintColor(for: .chrome)).cgColor.alpha
        let plain = UIColor(AppTheme.plainWhite.liquidGlassTintColor(for: .chrome)).cgColor.alpha
        XCTAssertGreaterThan(hc, paper)
        XCTAssertGreaterThan(hc, plain)
    }

    func testUIGlassEffectStyles() {
        let chrome = AppTheme.warmPaper.uiGlassEffect(for: .chrome)
        // Regular glass for chrome bars
        XCTAssertFalse(chrome.isInteractive)

        let chip = AppTheme.warmPaper.uiGlassEffect(for: .chip, interactive: true)
        XCTAssertTrue(chip.isInteractive)
    }

    func testGlassStyleCasesStable() {
        XCTAssertEqual(
            EspadaGlassStyle.allCases.map(\.rawValue).sorted(),
            ["chip", "chrome", "sheet"]
        )
    }
}
