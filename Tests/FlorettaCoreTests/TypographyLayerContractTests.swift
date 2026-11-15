import XCTest

/// The two typography layers stay separate: content may take the theme family,
/// chrome never does. Apple draws the same line in Books, Pages and Notes — a
/// serif body inside a system toolbar — and this app adopted it as a design
/// rule, so the source asserts it instead of trusting review.
final class TypographyLayerContractTests: XCTestCase {
    /// Every file whose text is interface, not document.
    private let chromeSurfaces = [
        "Floretta/Shared/Shell/AppearanceSettingsPanel.swift",
        "Floretta/Shared/Shell/DocumentEditor.swift",
        "Floretta/Shared/Shell/LibraryHome.swift",
        "Floretta/Shared/Shell/EditorStatusBar.swift",
    ]

    func testChromeSurfacesNeverTakeTheThemeFamily() throws {
        for path in chromeSurfaces {
            let source = try repoFile(path)
            XCTAssertFalse(
                source.contains("themeTypography("),
                "\(path) is chrome; interface text must not resolve the theme family"
            )
            XCTAssertTrue(
                source.contains("chromeTypography("),
                "\(path) is chrome; interface text stays on the system face"
            )
        }
    }

    /// Chrome may not reach the theme family through the back door either, so the
    /// modifier itself is checked for any resolver call or custom face.
    func testChromeModifierUsesOnlyTheSystemFace() throws {
        let source = try repoFile("Floretta/Shared/ThemeSettings.swift")
        XCTAssertTrue(source.contains("func chromeTypography("))
        XCTAssertTrue(source.contains("func themeTypography("), "the content layer keeps its theme modifier")

        let modifier = try slice(
            source,
            from: "struct ChromeTypographyModifier",
            until: "extension View {\n    /// Chrome-only typography"
        )
        XCTAssertTrue(modifier.contains("content.font(role.font)"))
        XCTAssertFalse(modifier.contains("ThemeFontResolver"))
        XCTAssertFalse(modifier.contains("familyCandidates"))
        XCTAssertFalse(modifier.contains(".custom("))
        XCTAssertFalse(modifier.contains("isFontAvailable"))

        let roles = try slice(source, from: "enum ChromeTextRole", until: "struct ChromeTypographyModifier")
        XCTAssertTrue(roles.contains("case .body: .body"), "chrome body is the platform text style, not a fixed size")
        XCTAssertTrue(roles.contains("case .compact: .callout"))
        XCTAssertFalse(roles.contains("size:"), "chrome never hand-picks a point size per surface")
    }

    func testContentSurfacesStillResolveTheThemeFamily() throws {
        let canvas = try repoFile("Floretta/Shared/Canvas/InfiniteCanvas.swift")
        XCTAssertTrue(
            canvas.contains("ThemeTypography.font(mode: mode, language: language, locale: locale, size: pointSize)"),
            "canvas topics keep the theme face"
        )
        XCTAssertTrue(canvas.contains("NodeTextTypography.canvasText("))
        XCTAssertFalse(
            canvas.contains(".themeTypography("),
            "canvas text resolves its family per node; it must not inherit the chrome face from the environment"
        )

        let editor = try repoFile("Floretta/Shared/Keyboard/NodeTextEditor.swift")
        XCTAssertTrue(editor.contains("ThemeFontCascade.platformFont(familyID:"), "in-place node editing keeps the theme face")

        // The appearance preview is content: it shows what the map will look like.
        let settings = try repoFile("Floretta/Shared/Shell/AppearanceSettingsPanel.swift")
        let preview = try slice(settings, from: "private var preview: some View", until: "private var activeScheme")
        XCTAssertTrue(preview.contains("FlorettaTitleFont.font("))
        XCTAssertFalse(preview.contains("chromeTypography("), "the preview samples the theme family inside the chrome form")
    }

    private func repoFile(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    private func slice(_ source: String, from startMark: String, until endMark: String) throws -> String {
        let start = try XCTUnwrap(source.range(of: startMark), "missing \(startMark)")
        let rest = source[start.lowerBound...]
        let end = try XCTUnwrap(rest.range(of: endMark), "missing \(endMark)")
        return String(rest[..<end.lowerBound])
    }
}
