import Foundation
import XCTest
@testable import FlorettaCore

/// 首页背景 stores a meaning, not a color. These cases pin the dark half of that
/// decision: the choice still takes effect at night, and it never turns the page
/// into a bright sheet.
final class HomeDarkModeTests: XCTestCase {
    func testEachChoiceResolvesPerScheme() {
        let cases: [(HomeBackground, MapColorScheme, String)] = [
            (.paper, .light, "#FBF7F0"),
            (.paper, .dark, "#1B1917"),
            (.white, .light, "#FFFFFF"),
            (.white, .dark, "#121212"),
        ]
        for (background, scheme, hex) in cases {
            XCTAssertEqual(background.pageHex(for: scheme), hex, "\(background) \(scheme)")
        }
        XCTAssertEqual(HomeBackground.allCases.count, 2, "the setting has exactly two choices")
    }

    func testTheTwoChoicesStayDifferentInDark() {
        XCTAssertNotEqual(
            HomeBackground.paper.pageHex(for: .dark),
            HomeBackground.white.pageHex(for: .dark),
            "if these matched, the setting would look like it stopped working at night"
        )
        // The dark paper is warm and near-black, not an inverted light value.
        let warm = try! XCTUnwrap(BranchColor(hex: HomeBackground.paper.pageHex(for: .dark)))
        XCTAssertLessThan(warm.red, 0.12)
        XCTAssertGreaterThan(warm.red, warm.blue, "paper stays warm in dark")
    }

    func testADocumentCreatedInDarkStoresTheDarkColor() {
        // The document stores the resolved color, so the file is deterministic and
        // an export cannot drift with the appearance.
        for background in HomeBackground.allCases {
            let stored = MindMapDocument.newMap(
                title: "深色新建",
                canvasBackgroundHex: background.pageHex(for: .dark)
            ).canvasBackgroundHex
            XCTAssertEqual(stored, background.pageHex(for: .dark))
            XCTAssertNotEqual(stored, "#FFFFFF", "\(background) must not be born white in dark")
            XCTAssertEqual(
                MindMapDocument.newMap(title: "浅色新建", canvasBackgroundHex: background.pageHex(for: .light)).canvasBackgroundHex,
                background.pageHex(for: .light)
            )
        }
    }

    func testBodyTextClearsWCAGAAOnEveryBackground() throws {
        for background in HomeBackground.allCases {
            for scheme: MapColorScheme in [.light, .dark] {
                let palette = background.palette(for: scheme)
                let body = try XCTUnwrap(ColorContrast.ratio(hex: palette.inkHex, hex: palette.pageHex))
                XCTAssertGreaterThanOrEqual(body, 4.5, "body text on \(background) \(scheme) is \(body)")
                let secondary = try XCTUnwrap(ColorContrast.ratio(hex: palette.secondaryInkHex, hex: palette.cardHex))
                XCTAssertGreaterThanOrEqual(secondary, 4.5, "secondary text on a card, \(background) \(scheme)")
            }
        }
    }

    func testDarkCardsAreRaisedByLightnessNotByAStroke() throws {
        for background in HomeBackground.allCases {
            let palette = background.palette(for: .dark)
            let page = try XCTUnwrap(ColorContrast.relativeLuminance(hex: palette.pageHex))
            let card = try XCTUnwrap(ColorContrast.relativeLuminance(hex: palette.cardHex))
            XCTAssertGreaterThan(card, page, "\(background) card sits above the page")
            // 5% lightening, expressed as a relative lift that a near-black page can show.
            let lift = (card - page) / max(page, 0.0001)
            XCTAssertGreaterThan(lift, 0.2)
            XCTAssertLessThan(lift, 1.2)
        }
        // No palette carries a border color: elevation is the only separation.
        let palette = HomeBackground.paper.palette(for: .dark)
        XCTAssertGreaterThan(
            try XCTUnwrap(ColorContrast.ratio(hex: palette.cardHex, hex: palette.pageHex)),
            1,
            "the card is distinguishable from the page without any outline"
        )
    }
}
