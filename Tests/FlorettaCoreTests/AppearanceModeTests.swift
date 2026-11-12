import Foundation
import XCTest
@testable import FlorettaCore

final class AppearanceModeTests: XCTestCase {
    func testDefaultModeIsClassicAndCustomStartsFromClassic() {
        XCTAssertEqual(AppearanceCatalog.defaultMode, .classic)
        let classic = AppearanceCatalog.defaultProfile(for: .classic)
        let custom = AppearanceCatalog.defaultProfile(for: .custom)
        let modern = AppearanceCatalog.defaultProfile(for: .modern)
        XCTAssertEqual(classic.fontFamilyID, "system-serif")
        XCTAssertEqual(custom, classic)
        XCTAssertEqual(modern.fontFamilyID, "system-sans")
        XCTAssertNotEqual(classic.light.canvasHex, modern.light.canvasHex)
    }

    func testClassicProfileCanStoreSansAndRoundTrip() throws {
        var profiles: [AppearanceMode: AppearanceProfile] = [:]
        for mode in AppearanceMode.allCases {
            profiles[mode] = AppearanceCatalog.defaultProfile(for: mode)
        }
        var classic = profiles[.classic]!
        classic.fontFamilyID = "system-sans"
        profiles[.classic] = classic

        let data = try AppearanceCatalog.encodeProfiles(profiles)
        let decoded = AppearanceCatalog.profiles(from: data)
        XCTAssertEqual(decoded[.classic]?.fontFamilyID, "system-sans")
        XCTAssertEqual(decoded[.modern]?.fontFamilyID, "system-sans")
        XCTAssertEqual(decoded[.custom]?.fontFamilyID, "system-serif")
    }
}
