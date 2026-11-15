import XCTest
@testable import FlorettaCore

@MainActor
final class AppearanceSettingsTests: XCTestCase {
    private func makeSettings() throws -> AppSettings {
        let name = "appearance-settings-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return AppSettings(defaults: defaults)
    }

    /// Settings and the inspector bind one AppSettings instance; a write is visible
    /// immediately through the same bindings the other entry would use. No copy, no delayed write.
    func testSettingsAndInspectorShareOneAppSettingsInstanceAndSyncLive() throws {
        let settings = try makeSettings()
        let settingsEntry = settings
        let inspectorEntry = settings
        XCTAssertTrue(settingsEntry === inspectorEntry)

        settingsEntry.homeBackground = .white
        XCTAssertEqual(inspectorEntry.homeBackground, .white)

        inspectorEntry.updateCurrentProfile { $0.fontFamilyID = "inter" }
        XCTAssertEqual(settingsEntry.currentProfile.fontFamilyID, "inter")
        XCTAssertEqual(settingsEntry.profile.fontFamilyID, "inter")

        settingsEntry.updateCurrentProfile { $0.light.canvasHex = "#FEDCBA" }
        XCTAssertEqual(inspectorEntry.currentProfile.light.canvasHex, "#FEDCBA")
    }

    func testHomeBackgroundAndProfilePersistAcrossRelaunch() throws {
        let name = "appearance-settings-tests.persist.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.homeBackground, .paper)
        XCTAssertEqual(settings.currentProfile.fontFamilyID, AppearanceCatalog.defaultFontFamilyID)
        XCTAssertFalse(settings.currentProfile.fontIsSerif, "content defaults to sans")

        // Choosing a serif is a font-list decision, not a mode.
        settings.updateCurrentProfile { $0.fontFamilyID = "eb-garamond" }
        settings.homeBackground = .white

        let relaunched = AppSettings(defaults: defaults)
        XCTAssertEqual(relaunched.homeBackground, .white)
        XCTAssertEqual(relaunched.currentProfile.fontFamilyID, "eb-garamond")
        XCTAssertEqual(defaults.string(forKey: AppearanceMigration.contentFontFamilyKey), "eb-garamond")
    }

    func testLegacyThreeModeDefaultsAreMigratedOnFirstLaunch() throws {
        let name = "appearance-settings-tests.legacy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        var modern = AppearanceCatalog.defaultProfile(homeBackground: .white)
        modern.fontFamilyID = "noto-sans"
        defaults.set("modern", forKey: AppearanceMigration.legacyModeKey)
        defaults.set(try AppearanceCatalog.encodeLegacyProfiles(["modern": modern]), forKey: AppearanceMigration.legacyProfilesKey)

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.homeBackground, .white, "modern maps to 纯白")
        XCTAssertEqual(settings.currentProfile.fontFamilyID, "noto-sans")
        XCTAssertNil(defaults.object(forKey: AppearanceMigration.legacyModeKey))
    }

    func testRestoringContentDefaultsKeepsTheHomeBackground() throws {
        let settings = try makeSettings()
        settings.homeBackground = .white
        settings.updateCurrentProfile { $0.cornerRadius = 3 }
        settings.restoreContentAppearanceDefaults()
        XCTAssertEqual(settings.currentProfile.cornerRadius, AppearanceCatalog.defaultProfile().cornerRadius)
        XCTAssertEqual(settings.currentProfile.light.canvasHex, "#FFFFFF")
        XCTAssertEqual(settings.homeBackground, .white)
    }

    func testNewDocumentsResolveTheHomeBackgroundForTheCurrentScheme() throws {
        let settings = try makeSettings()
        XCTAssertEqual(settings.defaultDocumentBackgroundHex(for: .light), "#FBF7F0")
        XCTAssertEqual(settings.defaultDocumentBackgroundHex(for: .dark), "#1B1917")

        settings.homeBackground = .white
        XCTAssertEqual(settings.defaultDocumentBackgroundHex(for: .light), "#FFFFFF")
        XCTAssertEqual(settings.defaultDocumentBackgroundHex(for: .dark), "#121212")
    }

    func testIdentifierPrefixesAreStableAndDoNotCollideWithColorSchemePicker() {
        XCTAssertEqual(AppearanceIdentifier.settingsPrefix, "settings.appearance")
        XCTAssertEqual(AppearanceIdentifier.inspectorPrefix, "inspector.appearance")
        XCTAssertEqual(AppearanceIdentifier.id(AppearanceIdentifier.settingsPrefix, "homeBackground"), "settings.appearance.homeBackground")
        XCTAssertEqual(AppearanceIdentifier.id(AppearanceIdentifier.inspectorPrefix, "homeBackground"), "inspector.appearance.homeBackground")
        XCTAssertEqual(AppearanceIdentifier.id(AppearanceIdentifier.settingsPrefix, "fontFamily"), "settings.appearance.fontFamily")
        XCTAssertFalse(AppearanceIdentifier.keys.contains("mode"))
        // The light/dark/system picker keeps the un-suffixed `settings.appearance`.
        for key in AppearanceIdentifier.keys {
            XCTAssertNotEqual(AppearanceIdentifier.id(AppearanceIdentifier.settingsPrefix, key), "settings.appearance")
            XCTAssertTrue(AppearanceIdentifier.id(AppearanceIdentifier.settingsPrefix, key).hasPrefix("settings.appearance."))
            XCTAssertTrue(AppearanceIdentifier.id(AppearanceIdentifier.inspectorPrefix, key).hasPrefix("inspector.appearance."))
        }
    }

    func testLayoutFramesPickUpProfilePaperFillScaleAndCornerImmediately() {
        var profile = AppearanceCatalog.defaultProfile()
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

    func testDocumentPaperDoesNotMoveWhenTheHomePreferenceChanges() throws {
        let settings = try makeSettings()
        // A document created now keeps the color it was born with.
        let document = MindMapDocument.newMap(
            title: "继承",
            canvasBackgroundHex: settings.defaultDocumentBackgroundHex(for: .light)
        )
        settings.homeBackground = .white
        XCTAssertEqual(document.canvasBackgroundHex, "#FBF7F0")
        XCTAssertEqual(settings.defaultDocumentBackgroundHex(for: .light), "#FFFFFF")
    }
}
