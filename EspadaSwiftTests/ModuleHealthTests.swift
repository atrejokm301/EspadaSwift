import XCTest
@testable import Espada

final class ModuleHealthTests: XCTestCase {

    private func module(
        path: String,
        title: String,
        kind: ModuleKind = .lexicon,
        health: ModuleHealth? = nil
    ) -> ModuleInfo {
        ModuleInfo(
            path: path,
            filename: (path as NSString).lastPathComponent,
            title: title,
            abbreviation: "",
            kind: kind,
            encrypted: false,
            hasStrongs: false,
            version: 1,
            health: health
        )
    }

    private func health(
        wedge: Int = 0,
        mojibake: Int = 0,
        unmappedPUA: Int = 0,
        repairedPUA: Int = 0,
        mangled: Int = 0,
        rows: Int
    ) -> ModuleHealth {
        var h = ModuleHealth()
        h.wedgeHits = wedge
        h.mojibakeRows = mojibake
        h.unmappedPrivateUseHits = unmappedPUA
        h.repairedPrivateUseHits = repairedPUA
        h.mangledScriptRuns = mangled
        h.sampledRows = rows
        return h
    }

    override func tearDown() {
        ModuleTextRepair.repairsCodepageWedges = true   // restore the shipping default
        super.tearDown()
    }

    // MARK: - Severity

    func testCleanSampleScoresClean() {
        var h = ModuleHealth()
        h.accumulate(sample: "Deléitate asimismo en Jehová; el corazón, ¿no conozco? el niño")
        XCTAssertEqual(h.severity, .clean)
        XCTAssertTrue(h.isClean)
        XCTAssertNil(h.spanishSummary)
    }

    /// Swanson runs ~1.3 wedges per row across 5 416 rows. Scored with repair disabled,
    /// because that is the only state in which wedges are still damage the reader sees.
    func testPervasiveWedgesScoreDamagedWhenRepairIsOff() {
        ModuleTextRepair.repairsCodepageWedges = false
        let h = health(wedge: 7_299, rows: 5_416)
        XCTAssertEqual(h.severity, .damaged)
        XCTAssertEqual(h.spanishSummary, "Codificación dañada: acentos guardados como letras griegas o hebreas.")
    }

    /// Vila Escuain has a single wedge in 2 894 rows — visible, but not "damaged".
    func testIsolatedHitScoresMinorWhenRepairIsOff() {
        ModuleTextRepair.repairsCodepageWedges = false
        let h = health(wedge: 1, rows: 2_894)
        XCTAssertEqual(h.severity, .minor)
        XCTAssertNotNil(h.spanishSummary)
    }

    /// With repair on (the shipping default) a wedge-damaged module reads correctly, so it
    /// must not carry a warning.
    func testWedgeDamagedModuleIsCleanWithRepairOn() {
        XCTAssertTrue(ModuleTextRepair.repairsCodepageWedges)
        let h = health(wedge: 7_299, rows: 5_416)
        XCTAssertEqual(h.severity, .clean)
        XCTAssertNil(h.spanishSummary)
    }

    func testAccumulateCountsRealDamage() {
        var h = ModuleHealth()
        h.accumulate(sample: "se utiliza tambiιn como prefijo en espaρol")   // 2 wedges
        h.accumulate(sample: "*1CrÃ³n 2:16")                                  // mojibake row
        h.accumulate(sample: "y ſan\u{E003}ificólo")                          // repairable glyph
        h.accumulate(sample: "resto \u{E123} desconocido")                    // unmapped glyph
        XCTAssertEqual(h.wedgeHits, 2)
        XCTAssertEqual(h.mojibakeRows, 1)
        XCTAssertEqual(h.repairedPrivateUseHits, 1)
        XCTAssertEqual(h.unmappedPrivateUseHits, 1)
        XCTAssertEqual(h.sampledRows, 4)
        XCTAssertEqual(h.severity, .damaged)
    }

    /// Reina 1569's `ct` ligature is everywhere but is expanded automatically, so the
    /// reader sees correct text and must not be warned about it.
    func testAutomaticallyRepairedDamageDoesNotWarn() {
        var h = ModuleHealth()
        for _ in 0..<40 {
            h.accumulate(sample: "y ſan\u{E003}ificólo, perfe\u{E003}o")
        }
        XCTAssertEqual(h.repairedPrivateUseHits, 80)
        XCTAssertEqual(h.residualHits, 0)
        XCTAssertEqual(h.severity, .clean)
        XCTAssertNil(h.spanishSummary)
    }

    /// Mojibake is repaired unconditionally, so it is recorded but never warned about.
    func testMojibakeAloneDoesNotWarn() {
        var h = ModuleHealth()
        h.accumulate(sample: "*1CrÃ³n 2:16")
        XCTAssertEqual(h.mojibakeRows, 1)
        XCTAssertEqual(h.severity, .clean)
    }

    /// Toggling repair flips the warning in both directions.
    func testWedgeWarningFollowsTheRepairSetting() {
        let swanson = health(wedge: 7_299, rows: 5_416)
        ModuleTextRepair.repairsCodepageWedges = false
        XCTAssertEqual(swanson.severity, .damaged)
        ModuleTextRepair.repairsCodepageWedges = true
        XCTAssertEqual(swanson.severity, .clean)
        XCTAssertNil(swanson.spanishSummary)
    }

    /// The broken Chávez lost its Hebrew *into* Latin (`àÆáÀéåéï`). Wedge repair cannot
    /// undo that, so it must count as damage no matter how repair is configured.
    func testMangledOriginalScriptAlwaysCountsAsDamage() {
        var h = ModuleHealth()
        h.accumulate(sample: "acerca de la palabra àÆáÀéåéï: Necesitado ( Deu 15:4 )")
        XCTAssertGreaterThan(h.mangledScriptRuns, 0)
        for enabled in [true, false] {
            ModuleTextRepair.repairsCodepageWedges = enabled
            XCTAssertEqual(h.severity, .damaged, "repair enabled: \(enabled)")
        }
        XCTAssertEqual(
            h.spanishSummary,
            "Codificación dañada: el hebreo/griego de este módulo se guardó como letras latinas."
        )
    }

    /// Ordinary Spanish stacks at most one accented letter per word.
    func testNormalSpanishIsNotMistakenForMangledScript() {
        var h = ModuleHealth()
        h.accumulate(sample: "Génesis, niño, Jehová, corazón, café, Éxodo, ángeles, María")
        XCTAssertEqual(h.mangledScriptRuns, 0)
        XCTAssertEqual(h.severity, .clean)
    }

    /// A Hebrew dictionary is full of Hebrew — that is not damage.
    func testGenuineOriginalScriptDoesNotCountAsDamage() {
        var h = ModuleHealth()
        h.accumulate(sample: "לֵב leb corazón; también ἀγάπη agápe amor")
        XCTAssertEqual(h.wedgeHits, 0)
        XCTAssertEqual(h.severity, .clean)
    }

    // MARK: - Duplicate detection

    /// The two installed Chávez copies are titled differently but are the same work.
    func testDifferentlyTitledCopiesOfTheSameWorkAreMatched() {
        let clean = module(path: "/a.lexi", title: "Diccionario de Hebreo Bíblico por Moisés Chávez")
        let broken = module(path: "/b.lexi", title: "Diccionario De Hebreo Biblico --MOISES CHAVEZ")
        XCTAssertTrue(clean.isSameWork(as: broken))

        let tuggyA = module(path: "/c.lexi", title: "Léxico griego-español del NT - Alfred E. Tuggy")
        let tuggyB = module(path: "/d.lexi", title: "Léxico Griego Español del NT por Alfred Tuggy")
        XCTAssertTrue(tuggyA.isSameWork(as: tuggyB))
    }

    func testDistinctWorksAreNotMatched() {
        let swanson = module(path: "/a.lexi", title: "Diccionario de Griego Bíblico por James Swanson")
        let chavez = module(path: "/b.lexi", title: "Diccionario de Hebreo Bíblico por Moisés Chávez")
        XCTAssertFalse(swanson.isSameWork(as: chavez))

        let tuggy = module(path: "/c.lexi", title: "Léxico Griego Español del NT por Alfred Tuggy")
        XCTAssertFalse(swanson.isSameWork(as: tuggy))
    }

    func testDifferentKindsAreNeverTheSameWork() {
        let lex = module(path: "/a.lexi", title: "Diccionario de Hebreo Bíblico Chávez", kind: .lexicon)
        let dict = module(path: "/b.dcti", title: "Diccionario de Hebreo Bíblico Chávez", kind: .dictionary)
        XCTAssertFalse(lex.isSameWork(as: dict))
    }

    // MARK: - Preferring the healthy copy

    func testDamagedDuplicateIsDemotedAndCleanOneIsNot() {
        let clean = module(
            path: "/clean.lexi",
            title: "Diccionario de Hebreo Bíblico por Moisés Chávez",
            health: health(rows: 120)
        )
        let broken = module(
            path: "/broken.lexi",
            title: "Diccionario De Hebreo Biblico --MOISES CHAVEZ",
            health: health(wedge: 627, mangled: 9, rows: 120)
        )
        let demoted = ModuleStore.demotedDuplicates(in: [broken, clean])
        XCTAssertEqual(demoted, ["/broken.lexi"])
    }

    /// Two identical clean copies (the Vila Escuain pair) — neither is worse, so ordering
    /// must be left alone rather than arbitrarily demoting one.
    func testEquallyHealthyDuplicatesAreNotDemoted() {
        let a = module(path: "/a.dcti", title: "Nuevo Diccionario Bíblico Ilustrado (Vila-Escuain)",
                       kind: .dictionary, health: health(rows: 120))
        let b = module(path: "/b.dcti", title: "Nuevo Diccionario Bíblico Ilustrado (Vila-Escuain)",
                       kind: .dictionary, health: health(rows: 120))
        XCTAssertTrue(ModuleStore.demotedDuplicates(in: [a, b]).isEmpty)
    }

    /// A module with no health reading must not be demoted below a known-broken one.
    func testUnsampledModuleOutranksADamagedOne() {
        let unknown = module(path: "/unknown.lexi", title: "Diccionario de Hebreo Bíblico Chávez")
        let broken = module(path: "/broken.lexi", title: "Diccionario de Hebreo Biblico Chavez",
                            health: health(wedge: 600, mangled: 9, rows: 120))
        XCTAssertEqual(ModuleStore.demotedDuplicates(in: [unknown, broken]), ["/broken.lexi"])
    }

    func testNoDuplicatesMeansNoDemotions() {
        let a = module(path: "/a.lexi", title: "Diccionario de Griego Bíblico por James Swanson")
        let b = module(path: "/b.lexi", title: "Diccionario de Hebreo Bíblico por Moisés Chávez")
        XCTAssertTrue(ModuleStore.demotedDuplicates(in: [a, b]).isEmpty)
    }
}
