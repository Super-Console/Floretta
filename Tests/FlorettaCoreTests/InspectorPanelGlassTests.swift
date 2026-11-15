import Foundation
import XCTest
@testable import FlorettaCore

/// The style inspector is one glass panel with opaque row blocks on it. This
/// macOS cannot render the running app for a screenshot, so the panel contract
/// is the source, and the row colours are numbers a test can check.
final class InspectorPanelGlassTests: XCTestCase {
    func testPanelContainerIsTheInspectorGlassRole() throws {
        let editor = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        let body = try slice(editor, from: "private var inspectorBody", until: "private var inspectorHeader")

        XCTAssertTrue(body.contains(".appleGlassChrome(.inspectorPanel)"), "the panel container is the system glass plate")
        XCTAssertTrue(body.contains("inspectorTabPage"))
        XCTAssertTrue(body.contains(".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)"), "the plate fills the column, so no glass strip is left showing")
        XCTAssertFalse(body.contains(".background("), "no second background is painted over the glass")
        XCTAssertEqual(InspectorPanelStyle.glassRole, "inspectorPanel", "the token names the role the container uses")

        let glass = try repoFile("Floretta/Shared/Shell/AppleGlassChrome.swift")
        XCTAssertTrue(glass.contains("case inspectorPanel"))
        XCTAssertFalse(glass.contains("case inspectorPanelGlass"), "the panel reuses the existing role; no alias was added")
    }

    func testEveryInspectorFormLetsThePanelGlassThrough() throws {
        let glass = try repoFile("Floretta/Shared/Shell/AppleGlassChrome.swift")
        let plate = try slice(glass, from: "func appleGlassInspectorFormPlate()", until: "/// Soft bottom-edge fade")

        XCTAssertTrue(plate.contains(".scrollContentBackground(.hidden)"), "a form-painted background would cover the panel glass")
        XCTAssertFalse(plate.contains("#if os(iOS)"), "macOS needs the same plate as iOS; the old iOS-only gate is what left the Mac panel opaque")
        XCTAssertFalse(plate.contains("#else"), "one behaviour on both platforms")

        let editor = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        let panel = try repoFile("Floretta/Shared/Shell/AppearanceSettingsPanel.swift")
        XCTAssertGreaterThanOrEqual(
            editor.components(separatedBy: ".appleGlassInspectorFormPlate()").count - 1,
            7,
            "every inspector form asks for the plate"
        )
        // 专区 was the one inspector form that still painted its own background.
        let region = try slice(editor, from: "private var regionStyleForm", until: "private var regionDraftToken")
        XCTAssertTrue(region.contains(".appleGlassInspectorFormPlate()"))
        XCTAssertFalse(panel.contains("scrollContentBackground"), "the shared panel leaves the plate to its inspector host")
    }

    func testSettingRowsKeepAnOpaqueBlockEach() throws {
        let editor = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        let panel = try repoFile("Floretta/Shared/Shell/AppearanceSettingsPanel.swift")
        let rows = try repoFile("Floretta/Shared/Shell/InspectorPanelRowBlock.swift")

        // Style tab: 结构 / 配色方案 / 分支, 导图 facts, 专区 and the label forms.
        XCTAssertGreaterThanOrEqual(
            editor.components(separatedBy: ".inspectorRowBlock()").count - 1,
            13,
            "the structural sections carry the same row block as the appearance rows"
        )
        XCTAssertTrue(panel.contains(".inspectorRowBlock(enabled: density == .inspector)"), "Settings shares these rows and keeps the grouped background")

        // A row is never cleared to see-through.
        XCTAssertFalse(editor.contains(".listRowBackground(Color.clear)"))
        XCTAssertFalse(panel.contains(".listRowBackground(Color.clear)"))
        XCTAssertFalse(editor.contains(".inspectorRowBlock().scrollContentBackground"))

        // The block is a solid colour, not a material, a blur, or a wash.
        XCTAssertTrue(rows.contains(".background("))
        XCTAssertTrue(rows.contains("RoundedRectangle("))
        XCTAssertTrue(rows.contains(".fill(blockColor)"))
        XCTAssertTrue(rows.contains("#if os(macOS)"), "iOS keeps its inset-grouped cards; a second plate there would double the layer")
        XCTAssertFalse(rows.contains("Material"))
        XCTAssertFalse(rows.contains(".blur("))
        XCTAssertFalse(rows.contains(".opacity("))
        XCTAssertFalse(rows.contains("LinearGradient"))
    }

    func testGroupedFormAndChromeTypographyAreUntouched() throws {
        let editor = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        let panel = try repoFile("Floretta/Shared/Shell/AppearanceSettingsPanel.swift")

        XCTAssertGreaterThanOrEqual(editor.components(separatedBy: ".formStyle(.grouped)").count - 1, 7)
        XCTAssertGreaterThanOrEqual(editor.components(separatedBy: "Form {").count - 1, 7, "the inspector keeps the grouped form, not a hand-laid list")
        XCTAssertFalse(editor.contains(".listStyle("), "no hand-tuned list style replaced the grouped form")
        XCTAssertTrue(panel.contains(".chromeTypography(language: settings.language)"), "the panel keeps the chrome face rule")
        XCTAssertFalse(panel.contains(".font(.system(size:"), "row blocks do not change the 13 pt chrome type")
    }

    func testRowBlockClearsWCAGAAInBothAppearances() throws {
        for scheme: MapColorScheme in [.light, .dark] {
            let block = InspectorPanelStyle.rowBlockHex(for: scheme)
            let body = try XCTUnwrap(
                ColorContrast.ratio(hex: InspectorPanelStyle.inkHex(for: scheme), hex: block),
                "\(scheme)"
            )
            XCTAssertGreaterThanOrEqual(body, ColorContrast.bodyMinimum, "13 pt body text on the row block, \(scheme): \(body)")
            let secondary = try XCTUnwrap(
                ColorContrast.ratio(hex: InspectorPanelStyle.secondaryInkHex(for: scheme), hex: block),
                "\(scheme)"
            )
            XCTAssertGreaterThanOrEqual(secondary, ColorContrast.bodyMinimum, "readouts on the row block, \(scheme): \(secondary)")
        }
    }

    func testDarkRowBlockStaysSolidAndRaisedOnTheGlass() throws {
        let darkBlock = InspectorPanelStyle.rowBlockHex(for: .dark)
        let darkPanel = InspectorPanelStyle.panelBackdropHex(for: .dark)

        // It stays a dark, solid block: a washed mid-grey would be the "dirty"
        // panel this design is avoiding.
        let luminance = try XCTUnwrap(ColorContrast.relativeLuminance(hex: darkBlock))
        XCTAssertLessThan(luminance, 0.05, "the dark row block is dark, not a grey wash")

        // Neutral, so it cannot pick up a colour cast from the canvas behind it.
        let parsed = try XCTUnwrap(BranchColor(hex: darkBlock))
        let spread = max(parsed.red, parsed.green, parsed.blue) - min(parsed.red, parsed.green, parsed.blue)
        XCTAssertLessThan(spread, 0.02, "the dark row block is neutral")

        // Raised off the panel without a stroke.
        let raised = try XCTUnwrap(ColorContrast.ratio(hex: darkBlock, hex: darkPanel))
        XCTAssertGreaterThan(raised, 1.15, "the row block is distinguishable from the panel, \(raised)")
        let lightRaised = try XCTUnwrap(
            ColorContrast.ratio(
                hex: InspectorPanelStyle.rowBlockHex(for: .light),
                hex: InspectorPanelStyle.panelBackdropHex(for: .light)
            )
        )
        XCTAssertGreaterThan(lightRaised, 1.05, "the light row block is distinguishable from the panel, \(lightRaised)")
    }

    func testRowBlockColoursAreOpaqueHexValues() throws {
        for hex in [
            InspectorPanelStyle.rowBlockLightHex,
            InspectorPanelStyle.rowBlockDarkHex,
            InspectorPanelStyle.inkLightHex,
            InspectorPanelStyle.inkDarkHex,
            InspectorPanelStyle.secondaryInkLightHex,
            InspectorPanelStyle.secondaryInkDarkHex,
            InspectorPanelStyle.panelBackdropLightHex,
            InspectorPanelStyle.panelBackdropDarkHex,
        ] {
            XCTAssertEqual(hex.count, 7, "\(hex) is #RRGGBB with no alpha channel")
            XCTAssertTrue(hex.hasPrefix("#"))
            XCTAssertNotNil(BranchColor(hex: hex))
        }
    }

    private func repoFile(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    private func slice(_ source: String, from startMark: String, until endMark: String) throws -> String {
        let start = try XCTUnwrap(source.range(of: startMark))
        let rest = source[start.lowerBound...]
        let end = try XCTUnwrap(rest.range(of: endMark))
        return String(rest[..<end.lowerBound])
    }
}
