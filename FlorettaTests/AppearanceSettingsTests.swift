import XCTest
@testable import FlorettaCore

@MainActor
final class AppearanceSettingsTests: XCTestCase {
    private func makeSettings() throws -> AppSettings {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "appearance-settings-tests.\(UUID().uuidString)"))
        return AppSettings(defaults: defaults)
    }

    /// Settings and the inspector bind one AppSettings instance; a write is visible
    /// immediately through the same bindings the other entry would use. No copy, no delayed write.
    func testSettingsAndInspectorShareOneAppSettingsInstanceAndSyncLive() throws {
        let settings = try makeSettings()
        let settingsEntry = settings
        let inspectorEntry = settings
        XCTAssertTrue(settingsEntry === inspectorEntry)

        settingsEntry.appearanceMode = .modern
        XCTAssertEqual(inspectorEntry.appearanceMode, .modern)

        inspectorEntry.updateCurrentProfile { $0.fontFamilyID = "inter" }
        XCTAssertEqual(settingsEntry.currentProfile.fontFamilyID, "inter")
        XCTAssertEqual(settingsEntry.appearanceProfiles[.modern]?.fontFamilyID, "inter")

        settingsEntry.updateCurrentProfile { $0.light.canvasHex = "#FEDCBA" }
        XCTAssertEqual(inspectorEntry.currentProfile.light.canvasHex, "#FEDCBA")
    }

    func testThreeModesAreSwitchableAndClassicSansPersistsAcrossRestart() {
        let defaultsName = "appearance-settings-tests.persist.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.appearanceMode, .classic)

        settings.updateCurrentProfile { $0.fontFamilyID = "inter" }
        XCTAssertEqual(settings.currentProfile.fontFamilyID, "inter")

        settings.appearanceMode = .modern
        XCTAssertEqual(settings.appearanceMode, .modern)
        XCTAssertEqual(settings.currentProfile.fontFamilyID, "system-sans")

        settings.appearanceMode = .custom
        XCTAssertEqual(settings.appearanceMode, .custom)
        XCTAssertEqual(settings.currentProfile.fontFamilyID, "system-serif")

        settings.appearanceMode = .classic
        XCTAssertEqual(settings.currentProfile.fontFamilyID, "inter")

        let relaunched = AppSettings(defaults: defaults)
        XCTAssertEqual(relaunched.appearanceMode, .classic)
        XCTAssertEqual(relaunched.currentProfile.fontFamilyID, "inter")
    }

    func testIdentifierPrefixesAreStableAndDoNotCollideWithColorSchemePicker() {
        XCTAssertEqual(AppearanceIdentifier.settingsPrefix, "settings.appearance")
        XCTAssertEqual(AppearanceIdentifier.inspectorPrefix, "inspector.appearance")
        XCTAssertEqual(AppearanceIdentifier.id(AppearanceIdentifier.settingsPrefix, "mode"), "settings.appearance.mode")
        XCTAssertEqual(AppearanceIdentifier.id(AppearanceIdentifier.inspectorPrefix, "mode"), "inspector.appearance.mode")
        XCTAssertEqual(AppearanceIdentifier.id(AppearanceIdentifier.settingsPrefix, "fontFamily"), "settings.appearance.fontFamily")
        XCTAssertEqual(AppearanceIdentifier.id(AppearanceIdentifier.inspectorPrefix, "fontFamily"), "inspector.appearance.fontFamily")
        // The light/dark/system picker keeps the un-suffixed `settings.appearance`.
        for key in AppearanceIdentifier.keys {
            XCTAssertNotEqual(AppearanceIdentifier.id(AppearanceIdentifier.settingsPrefix, key), "settings.appearance")
            XCTAssertTrue(AppearanceIdentifier.id(AppearanceIdentifier.settingsPrefix, key).hasPrefix("settings.appearance."))
            XCTAssertTrue(AppearanceIdentifier.id(AppearanceIdentifier.inspectorPrefix, key).hasPrefix("inspector.appearance."))
        }
    }

    func testLayoutFramesPickUpProfilePaperFillScaleAndCornerImmediately() {
        var profile = AppearanceCatalog.defaultProfile(for: .classic)
        profile.fontFamilyID = "inter"
        profile.fontSizeScale = 1.5
        profile.cornerRadius = 20
        profile.light.canvasHex = "#F6F1E4"
        profile.light.nodeFillHex = "#FFEEDD"
        profile.light.textHex = "#112233"

        let document = MindMapDocument(
            title: "appearance",
            roots: [MindMapNode(text: "根", children: [MindMapNode(text: "子")])]
        )
        let unstyled = LayoutEngine().layout(document, scheme: .light)
        let styled = LayoutEngine().layout(document, scheme: .light, profile: profile)
        XCTAssertFalse(unstyled.isEmpty)
        XCTAssertEqual(styled.count, unstyled.count)
        XCTAssertEqual(styled[0].cornerRadius, 20)
        XCTAssertEqual(styled[0].fill, BranchColor(hex: "#FFEEDD"))
        XCTAssertEqual(styled[0].textColor, BranchColor(hex: "#112233"))
        XCTAssertEqual(styled[0].fontSize, unstyled[0].fontSize * 1.5, accuracy: 0.01)

        let applied = profile.applying(to: .standard, scheme: .light)
        XCTAssertEqual(applied.canvasBackground, BranchColor(hex: "#F6F1E4"))
    }
}
