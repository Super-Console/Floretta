import Foundation
import XCTest
@testable import FlorettaCore

/// The three appearance modes are gone. These cases pin what happens to the
/// values that are already on someone's disk, and to the paper new documents take.
final class AppearanceMigrationTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "appearance-migration-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    // MARK: - 1. Old mode values map onto the two new backgrounds

    func testEveryLegacyModeMapsToExactlyOneHomeBackground() {
        XCTAssertEqual(AppearanceMigration.homeBackground(forLegacyMode: "classic"), .paper)
        XCTAssertEqual(AppearanceMigration.homeBackground(forLegacyMode: "modern"), .white)
        XCTAssertEqual(AppearanceMigration.homeBackground(forLegacyMode: "custom"), .paper)
        XCTAssertEqual(AppearanceMigration.homeBackground(forLegacyMode: nil), .paper)
        XCTAssertEqual(AppearanceMigration.homeBackground(forLegacyMode: ""), .paper)
        XCTAssertEqual(AppearanceMigration.homeBackground(forLegacyMode: "3-modes-are-gone"), .paper)

        for mode in AppearanceMigration.LegacyMode.allCases {
            XCTAssertTrue(HomeBackground.allCases.contains(mode.homeBackground))
        }
    }

    func testMigrationKeepsTheProfileOfTheModeThatWasSelected() throws {
        var classic = AppearanceCatalog.defaultProfile()
        classic.fontFamilyID = "eb-garamond"
        var modern = AppearanceCatalog.defaultProfile(homeBackground: .white)
        modern.fontSizeScale = 1.4
        let blob = try AppearanceCatalog.encodeLegacyProfiles(["classic": classic, "modern": modern])

        let fromClassic = AppearanceMigration.resolve(legacyMode: "classic", legacyProfiles: blob)
        XCTAssertEqual(fromClassic.homeBackground, .paper)
        XCTAssertEqual(fromClassic.profile.fontFamilyID, "eb-garamond", "an existing picture keeps its face")
        XCTAssertTrue(fromClassic.readLegacyMode)

        let fromModern = AppearanceMigration.resolve(legacyMode: "modern", legacyProfiles: blob)
        XCTAssertEqual(fromModern.homeBackground, .white)
        XCTAssertEqual(fromModern.profile.fontSizeScale, 1.4)

        // A mode with no stored profile falls back to the default for that background.
        let fromCustom = AppearanceMigration.resolve(legacyMode: "custom", legacyProfiles: blob)
        XCTAssertEqual(fromCustom.homeBackground, .paper)
        XCTAssertEqual(fromCustom.profile, AppearanceCatalog.defaultProfile(homeBackground: .paper))

        // The older `floretta.theme.mode` key is the same vocabulary.
        let fromThemeMode = AppearanceMigration.resolve(legacyMode: nil, legacyProfiles: nil, legacyThemeMode: "modern")
        XCTAssertEqual(fromThemeMode.homeBackground, .white)
        XCTAssertEqual(fromThemeMode.profile.fontFamilyID, "system-sans")
    }

    func testMigratingClearsLegacyKeysAndIsIdempotent() throws {
        let store = defaults()
        var modern = AppearanceCatalog.defaultProfile(homeBackground: .white)
        modern.fontFamilyID = "inter"
        store.set("modern", forKey: AppearanceMigration.legacyModeKey)
        store.set(try AppearanceCatalog.encodeLegacyProfiles(["modern": modern]), forKey: AppearanceMigration.legacyProfilesKey)
        store.set("modern", forKey: AppearanceMigration.legacyThemeModeKey)
        store.set(false, forKey: AppearanceMigration.legacySerifOverrideKey)

        let migrated = AppearanceMigration.migrateIfNeeded(defaults: store)
        XCTAssertEqual(migrated?.homeBackground, .white)
        XCTAssertEqual(store.string(forKey: AppearanceMigration.homeBackgroundKey), "white")
        XCTAssertEqual(
            AppearanceCatalog.profile(from: store.data(forKey: AppearanceMigration.profileKey)).fontFamilyID,
            "inter"
        )
        XCTAssertEqual(store.string(forKey: AppearanceMigration.contentFontFamilyKey), "inter")
        for key in [
            AppearanceMigration.legacyModeKey,
            AppearanceMigration.legacyProfilesKey,
            AppearanceMigration.legacyThemeModeKey,
            AppearanceMigration.legacySerifOverrideKey,
        ] {
            XCTAssertNil(store.object(forKey: key), key)
        }

        // Second launch: nothing left to migrate, and no second rewrite.
        XCTAssertNil(AppearanceMigration.migrateIfNeeded(defaults: store))
    }

    func testFreshInstallStartsOnPaperWithASansDefault() {
        let store = defaults()
        let migrated = AppearanceMigration.migrateIfNeeded(defaults: store)
        XCTAssertEqual(migrated?.homeBackground, .paper)
        XCTAssertEqual(migrated?.profile.fontFamilyID, "system-sans")
        XCTAssertFalse(migrated?.readLegacyMode ?? true)
    }

    // MARK: - 2. New documents take the background, old documents keep theirs

    func testNewDocumentStoresTheResolvedConcreteBackground() {
        // Light: paper is the warm off-white, white is the sheet.
        XCTAssertEqual(MindMapDocument.newMap(title: "新", canvasBackgroundHex: HomeBackground.paper.pageHex(for: .light)).canvasBackgroundHex, "#FBF7F0")
        XCTAssertEqual(MindMapDocument.newMap(title: "新", canvasBackgroundHex: HomeBackground.white.pageHex(for: .light)).canvasBackgroundHex, "#FFFFFF")

        // Dark: the same two choices, and neither is a white sheet.
        let darkPaper = MindMapDocument.newMap(title: "深", canvasBackgroundHex: HomeBackground.paper.pageHex(for: .dark))
        let darkWhite = MindMapDocument.newMap(title: "深", canvasBackgroundHex: HomeBackground.white.pageHex(for: .dark))
        XCTAssertEqual(darkPaper.canvasBackgroundHex, "#1B1917")
        XCTAssertEqual(darkWhite.canvasBackgroundHex, "#121212")
        XCTAssertNotEqual(darkPaper.canvasBackgroundHex, "#FFFFFF")
        XCTAssertNotEqual(darkPaper.canvasBackgroundHex, darkWhite.canvasBackgroundHex)
    }

    func testDocumentWithoutStoredPaperIsLeftAlone() throws {
        // A file written before documents carried a background.
        let legacy = MindMapDocument(title: "旧", roots: [MindMapNode(text: "根")])
        let json = try FlorettaCodec.encode(legacy)
        XCTAssertFalse(String(decoding: json, as: UTF8.self).contains("canvasBackgroundHex"))

        let reopened = try FlorettaCodec.decode(json)
        XCTAssertNil(reopened.canvasBackgroundHex)
        // It keeps following the appearance instead of being stamped with one.
        let fallback = BranchColor(hex: "#F6F1E4")
        XCTAssertEqual(reopened.resolvedCanvasBackground(fallback: fallback), fallback)

        // Editing and saving that document still writes no paper.
        var edited = reopened
        edited.title = "旧·改"
        XCTAssertFalse(String(decoding: try FlorettaCodec.encode(edited), as: UTF8.self).contains("canvasBackgroundHex"))
    }

    func testStoredPaperBeatsTheFallbackAndSurvivesExportProjection() throws {
        let document = MindMapDocument.newMap(title: "存", canvasBackgroundHex: "#1B1917")
        let fallback = BranchColor(hex: "#F6F1E4")
        XCTAssertEqual(document.resolvedCanvasBackground(fallback: fallback), BranchColor(hex: "#1B1917"))

        // PNG/PDF project one sheet; the paper must travel with it.
        let projected = document.singleTreeExport()
        XCTAssertEqual(projected.canvasBackgroundHex, "#1B1917")
        let reopened = try FlorettaCodec.decode(try FlorettaCodec.encode(document))
        XCTAssertEqual(reopened.canvasBackgroundHex, "#1B1917")
    }

    // MARK: - 3. The semantic choice survives dark mode

    func testSemanticBackgroundResolvesDifferentlyPerScheme() {
        XCTAssertEqual(HomeBackground.paper.pageHex(for: .light), "#FBF7F0")
        XCTAssertEqual(HomeBackground.paper.pageHex(for: .dark), "#1B1917")
        XCTAssertEqual(HomeBackground.white.pageHex(for: .light), "#FFFFFF")
        XCTAssertEqual(HomeBackground.white.pageHex(for: .dark), "#121212")

        // Distinct in dark, so the setting does not silently stop working.
        XCTAssertNotEqual(HomeBackground.paper.pageHex(for: .dark), HomeBackground.white.pageHex(for: .dark))
        // Warm, not a saturated accent.
        let warm = try! XCTUnwrap(BranchColor(hex: HomeBackground.paper.pageHex(for: .dark)))
        XCTAssertGreaterThan(warm.red, warm.blue)
        XCTAssertLessThan(warm.red, 0.15)
    }

    func testBodyInkClearsContrastOnBothSchemes() throws {
        for background in HomeBackground.allCases {
            for scheme: MapColorScheme in [.light, .dark] {
                let palette = background.palette(for: scheme)
                let ratio = try XCTUnwrap(ColorContrast.ratio(hex: palette.inkHex, hex: palette.pageHex))
                XCTAssertGreaterThanOrEqual(ratio, ColorContrast.bodyMinimum, "\(background) \(scheme)")
                let secondary = try XCTUnwrap(ColorContrast.ratio(hex: palette.secondaryInkHex, hex: palette.pageHex))
                XCTAssertGreaterThanOrEqual(secondary, 3, "secondary text still reads: \(background) \(scheme)")
            }
        }
    }

    func testDarkCardsRiseByLightnessInsteadOfAStroke() throws {
        for background in HomeBackground.allCases {
            let palette = background.palette(for: .dark)
            let page = try XCTUnwrap(ColorContrast.relativeLuminance(hex: palette.pageHex))
            let card = try XCTUnwrap(ColorContrast.relativeLuminance(hex: palette.cardHex))
            XCTAssertGreaterThan(card, page, "the card is raised above the page: \(background)")
            let growth = (card - page) / max(page, 0.0001)
            XCTAssertGreaterThan(growth, 0.2, "5% lightening is visible even on near-black")
        }
        // Light keeps a card that is at least as light as the page.
        for background in HomeBackground.allCases {
            let palette = background.palette(for: .light)
            let page = try XCTUnwrap(ColorContrast.relativeLuminance(hex: palette.pageHex))
            let card = try XCTUnwrap(ColorContrast.relativeLuminance(hex: palette.cardHex))
            XCTAssertGreaterThanOrEqual(card + 0.0001, page)
        }
    }
}
