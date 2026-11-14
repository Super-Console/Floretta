import XCTest
@testable import FlorettaCore

final class ThemeFontResolverTests: XCTestCase {
    func testClassicCJKUsesSongtiAndSerif() {
        let spec = ThemeFontResolver.spec(for: .classic, script: .cjk)

        XCTAssertTrue(spec.isSerif)
        XCTAssertEqual(spec.familyCandidates.first, "Songti SC")
    }

    func testChineseInterfaceClassicPrefersSongtiFamily() {
        let resolved = ThemeFontResolver.spec(for: .classic, script: .cjk)
        XCTAssertTrue(resolved.familyCandidates.first?.hasPrefix("Songti") == true)
    }

    func testChineseInterfaceModernPrefersPingFangFamily() {
        let resolved = ThemeFontResolver.spec(for: .modern, script: .cjk)
        XCTAssertTrue(resolved.familyCandidates.first?.hasPrefix("PingFang") == true)
    }

    func testClassicLatinUsesEBGaramondAndSerif() {
        let spec = ThemeFontResolver.spec(for: .classic, script: .latin)

        XCTAssertTrue(spec.isSerif)
        XCTAssertEqual(spec.familyCandidates.first, "EB Garamond")
    }

    func testModernCJKUsesPingFang() {
        let spec = ThemeFontResolver.spec(for: .modern, script: .cjk)

        XCTAssertFalse(spec.isSerif)
        XCTAssertEqual(spec.familyCandidates.first, "PingFang SC")
    }

    func testModernLatinUsesInter() {
        let spec = ThemeFontResolver.spec(for: .modern, script: .latin)

        XCTAssertFalse(spec.isSerif)
        XCTAssertEqual(spec.familyCandidates.first, "Inter")
    }

    func testClassicCanOverrideToSansSerif() {
        let spec = ThemeFontResolver.spec(for: .classic, script: .cjk, serifOverride: false)

        XCTAssertFalse(spec.isSerif)
    }

    func testCustomWithoutOverrideMatchesClassic() {
        for script: ThemeScript in [.cjk, .latin] {
            XCTAssertEqual(
                ThemeFontResolver.spec(for: .custom, script: script),
                ThemeFontResolver.spec(for: .classic, script: script)
            )
        }
    }
}
