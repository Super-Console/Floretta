import Foundation
import XCTest
@testable import FlorettaCore

final class AppearanceModeTests: XCTestCase {
    func testOneDefaultProfileIsSansOnThePaperHome() {
        let profile = AppearanceCatalog.defaultProfile()

        XCTAssertEqual(profile.fontFamilyID, "system-sans")
        XCTAssertEqual(profile.fontFamilyID, AppearanceCatalog.defaultFontFamilyID)
        XCTAssertFalse(profile.fontIsSerif, "content defaults to sans; serif is one pick away")
        XCTAssertEqual(profile.light.canvasHex, HomeBackground.paper.pageHex(for: .light))
        XCTAssertEqual(profile.dark.canvasHex, HomeBackground.paper.pageHex(for: .dark))
        XCTAssertEqual(profile.fontSizeScale, 1)
        XCTAssertEqual(profile.cornerRadius, 12)
    }

    func testWhiteHomeBackgroundSeedsTheProfilePaper() {
        let profile = AppearanceCatalog.defaultProfile(homeBackground: .white)
        XCTAssertEqual(profile.light.canvasHex, "#FFFFFF")
        XCTAssertEqual(profile.dark.canvasHex, "#121212")
    }

    func testLegacyThreeModeProfilePayloadStillDecodes() throws {
        // The migration is the only reader; it must still understand the old blob.
        let classic = AppearanceCatalog.defaultProfile()
        var modern = classic
        modern.fontFamilyID = "inter"
        let data = try AppearanceCatalog.encodeLegacyProfiles(["classic": classic, "modern": modern])

        let decoded = AppearanceCatalog.legacyProfiles(from: data)
        XCTAssertEqual(decoded["classic"]?.fontFamilyID, "system-sans")
        XCTAssertEqual(decoded["modern"]?.fontFamilyID, "inter")
        XCTAssertEqual(decoded["custom"], nil)
        XCTAssertTrue(AppearanceCatalog.legacyProfiles(from: nil).isEmpty)
    }

    func testCatalogIncludesBundledLatinFamiliesAndFollowsSystemName() {
        let ids = AppearanceCatalog.families.map(\.id)
        XCTAssertEqual(ids, [
            "system-serif",
            "system-sans",
            "eb-garamond",
            "crimson-pro",
            "libre-baskerville",
            "noto-serif",
            "inter",
            "ibm-plex-sans",
            "noto-sans",
        ])
        XCTAssertEqual(AppearanceCatalog.family(id: "system-sans")?.nameKey, "跟随系统")
        XCTAssertNil(AppearanceCatalog.family(id: "source-han-serif"))
        XCTAssertEqual(AppearanceCatalog.family(id: "ibm-plex-sans")?.postScriptName, "IBMPlexSans")
        XCTAssertEqual(AppearanceCatalog.families.filter { $0.resourceFileName != nil }.count, 7)
        // Every family the inspector lists is a face, not a mode.
        XCTAssertEqual(AppearanceCatalog.families.filter { $0.kind == .serif }.count, 5)
    }

    func testProfileAppliesPaperFillInkAndCornerToLayoutAppearance() {
        var profile = AppearanceCatalog.defaultProfile()
        profile.cornerRadius = 20
        profile.light.canvasHex = "#ABCDEF"
        profile.light.nodeFillHex = "#123456"
        profile.light.textHex = "#010203"
        profile.fontSizeScale = 1.5
        let applied = profile.applying(to: .standard, scheme: .light)
        XCTAssertEqual(applied.canvasBackground, BranchColor(hex: "#ABCDEF"))
        XCTAssertEqual(applied.uniformFill, BranchColor(hex: "#123456"))
        XCTAssertEqual(applied.centerText, BranchColor(hex: "#010203"))
        XCTAssertEqual(applied.cornerRadius, 20)
        XCTAssertEqual(profile.clampedFontSizeScale, 1.5)
    }
}
