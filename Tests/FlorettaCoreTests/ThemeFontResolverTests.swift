import XCTest
@testable import FlorettaCore

/// Serif is a property of the chosen face, not of an appearance mode. These
/// cases keep the family candidates, and pin the two families the app defaults to.
final class ThemeFontResolverTests: XCTestCase {
    func testSerifCJKUsesSongtiAndSerif() {
        let spec = ThemeFontResolver.spec(script: .cjk, isSerif: true)

        XCTAssertTrue(spec.isSerif)
        XCTAssertEqual(spec.familyCandidates.first, "Songti SC")
    }

    func testSansCJKUsesPingFang() {
        let spec = ThemeFontResolver.spec(script: .cjk, isSerif: false)

        XCTAssertFalse(spec.isSerif)
        XCTAssertEqual(spec.familyCandidates.first, "PingFang SC")
    }

    func testSerifLatinUsesEBGaramondAndSerif() {
        let spec = ThemeFontResolver.spec(script: .latin, isSerif: true)

        XCTAssertTrue(spec.isSerif)
        XCTAssertEqual(spec.familyCandidates.first, "EB Garamond")
    }

    func testSansLatinUsesInter() {
        let spec = ThemeFontResolver.spec(script: .latin, isSerif: false)

        XCTAssertFalse(spec.isSerif)
        XCTAssertEqual(spec.familyCandidates.first, "Inter")
    }

    func testFamilyIDDecidesTheFaceThroughTheCatalog() {
        for script: ThemeScript in [.cjk, .latin] {
            XCTAssertEqual(
                ThemeFontResolver.spec(script: script, familyID: "system-serif"),
                ThemeFontResolver.spec(script: script, isSerif: true)
            )
            XCTAssertEqual(
                ThemeFontResolver.spec(script: script, familyID: "inter"),
                ThemeFontResolver.spec(script: script, isSerif: false)
            )
        }
        XCTAssertEqual(
            ThemeFontResolver.spec(script: .latin, familyID: AppearanceCatalog.defaultFontFamilyID),
            ThemeFontResolver.spec(script: .latin, isSerif: false),
            "the content default is sans"
        )
    }
}
