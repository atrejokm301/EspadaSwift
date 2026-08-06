import XCTest
@testable import Espada

final class AppThemeTests: XCTestCase {
    private let themeKey = "espada.theme"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: themeKey)
        super.tearDown()
    }

    func testWarmPaperAndHighContrastAreInCatalog() {
        XCTAssertTrue(AppTheme.allCases.contains(.warmPaper))
        XCTAssertTrue(AppTheme.allCases.contains(.highContrast))
        XCTAssertEqual(AppTheme.warmPaper.rawValue, "warmPaper")
        XCTAssertEqual(AppTheme.highContrast.rawValue, "highContrast")
    }

    func testWarmPaperIsLightReadingTheme() {
        let t = AppTheme.warmPaper
        XCTAssertEqual(t.preferredColorScheme, .light)
        XCTAssertFalse(t.usesDarkChrome)
        XCTAssertEqual(t.label, "Warm Paper")
        // Ink should not be pure black; paper should not be pure white (comfort).
        XCTAssertNotEqual(t.primaryText, .black)
        XCTAssertNotEqual(t.background, .white)
    }

    func testHighContrastMaxLegibility() {
        let t = AppTheme.highContrast
        XCTAssertEqual(t.preferredColorScheme, .light)
        XCTAssertEqual(t.background, .white)
        XCTAssertEqual(t.primaryText, .black)
        XCTAssertEqual(t.card, .white)
    }

    func testTrueDarkStillDark() {
        XCTAssertEqual(AppTheme.trueDark.preferredColorScheme, .dark)
        XCTAssertTrue(AppTheme.trueDark.usesDarkChrome)
    }

    func testThemeManagerPersistsWarmPaper() {
        UserDefaults.standard.removeObject(forKey: themeKey)
        let manager = ThemeManager()
        manager.theme = .warmPaper
        XCTAssertEqual(UserDefaults.standard.string(forKey: themeKey), "warmPaper")

        let reloaded = ThemeManager()
        XCTAssertEqual(reloaded.theme, .warmPaper)
    }

    func testThemeManagerPersistsHighContrast() {
        UserDefaults.standard.removeObject(forKey: themeKey)
        let manager = ThemeManager()
        manager.theme = .highContrast
        XCTAssertEqual(UserDefaults.standard.string(forKey: themeKey), "highContrast")

        let reloaded = ThemeManager()
        XCTAssertEqual(reloaded.theme, .highContrast)
    }

    func testUnknownStoredThemeFallsBackToTrueDark() {
        UserDefaults.standard.set("not-a-real-theme", forKey: themeKey)
        let manager = ThemeManager()
        XCTAssertEqual(manager.theme, .trueDark)
    }

    func testAllThemesHaveNonEmptyLabelsAndHints() {
        for theme in AppTheme.allCases {
            XCTAssertFalse(theme.label.isEmpty, "\(theme) label")
            XCTAssertFalse(theme.accessibilityHint.isEmpty, "\(theme) hint")
            XCTAssertEqual(theme.swatchColors.count, 2, "\(theme) swatch")
        }
    }
}
