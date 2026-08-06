import XCTest
@testable import Espada

final class ModulePickerOrderingTests: XCTestCase {

    private func mod(_ name: String, path: String? = nil) -> ModuleInfo {
        ModuleInfo(
            path: path ?? "/tmp/\(name).cmti",
            filename: "\(name).cmti",
            title: name,
            abbreviation: name,
            kind: .commentary,
            encrypted: false,
            hasStrongs: false,
            version: 3
        )
    }

    func testAlphabeticalWhenNoAvailabilityHits() {
        let modules = [mod("Zeta"), mod("Alpha"), mod("Mu")]
        let parts = ModulePickerOrdering.partition(
            modules: modules,
            availability: [:] // nothing selected / no probes
        )
        XCTAssertTrue(parts.hits.isEmpty)
        XCTAssertEqual(parts.flat.map(\.displayName), ["Alpha", "Mu", "Zeta"])
    }

    func testAlphabeticalWhenAllAvailabilityFalse() {
        let a = mod("Alpha", path: "/a")
        let z = mod("Zeta", path: "/z")
        let parts = ModulePickerOrdering.partition(
            modules: [z, a],
            availability: ["/a": false, "/z": false]
        )
        XCTAssertTrue(parts.hits.isEmpty)
        XCTAssertEqual(parts.flat.map(\.path), ["/a", "/z"])
    }

    func testHitsGroupedFirstThenAlphabeticalRest() {
        let alpha = mod("Alpha", path: "/alpha")
        let mu = mod("Mu", path: "/mu")       // has content
        let zeta = mod("Zeta", path: "/zeta") // has content
        let beta = mod("Beta", path: "/beta")

        let parts = ModulePickerOrdering.partition(
            modules: [alpha, mu, zeta, beta],
            availability: [
                "/alpha": false,
                "/mu": true,
                "/zeta": true,
                "/beta": false
            ]
        )
        // Hits together, A–Z within group: Mu, Zeta then rest Alpha, Beta
        XCTAssertEqual(parts.hits.map(\.path), ["/mu", "/zeta"])
        XCTAssertEqual(parts.rest.map(\.path), ["/alpha", "/beta"])
        XCTAssertEqual(parts.flat.map(\.path), ["/mu", "/zeta", "/alpha", "/beta"])
    }

    func testSearchStillRespectsHitPriority() {
        let keepHit = mod("Matthew Henry", path: "/mh")
        let keepRest = mod("MacArthur", path: "/mac")
        let drop = mod("Gill", path: "/gill")
        let parts = ModulePickerOrdering.partition(
            modules: [keepHit, keepRest, drop],
            availability: ["/mh": true, "/mac": false, "/gill": false],
            search: "Ma"
        )
        XCTAssertEqual(parts.hits.map(\.path), ["/mh"])
        XCTAssertEqual(parts.rest.map(\.path), ["/mac"])
        XCTAssertFalse(parts.flat.contains(where: { $0.path == "/gill" }))
    }
}
