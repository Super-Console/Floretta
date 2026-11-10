import AppKit
import SwiftUI
import XCTest

/// Proves the Mac side panels install an official glass view, not a solid fill.
@MainActor
final class AppleGlassPanelTests: XCTestCase {
    /// Windows stay alive until this case ends, so the hierarchy can be read.
    private var mountedWindows: [NSWindow] = []

    func testResolvedBackendMatchesTheMacOS26DeploymentTarget() {
        XCTAssertEqual(AppleGlassBackend.resolved, .swiftUIGlassEffect)
        XCTAssertEqual(AppleGlassMetrics.cornerRadius, 16)
        XCTAssertGreaterThanOrEqual(AppleGlassMetrics.cornerRadius, 12)
        XCTAssertLessThanOrEqual(AppleGlassMetrics.cornerRadius, 16)
    }

    func testAppKitFallbackConstructsNSGlassEffectView() {
        let view = AppleGlassPlate.makeGlassEffectView(cornerRadius: AppleGlassMetrics.cornerRadius)
        XCTAssertTrue(type(of: view) === NSGlassEffectView.self)
        XCTAssertEqual(view.cornerRadius, 16)
        XCTAssertTrue(String(describing: view.style).localizedCaseInsensitiveContains("regular"))
        XCTAssertNil(view.layer?.backgroundColor)
    }

    func testVisualEffectFallbackIsBehindWindowAndNotASolidFill() {
        let view = AppleGlassVisualEffectPlate.makeView(cornerRadius: 16)
        XCTAssertTrue(type(of: view) === NSVisualEffectView.self)
        XCTAssertEqual(view.material, .underWindowBackground)
        XCTAssertEqual(view.blendingMode, .behindWindow)
        XCTAssertEqual(view.layer?.cornerCurve, .continuous)
        XCTAssertEqual(view.layer?.cornerRadius, 16)
        XCTAssertNil(view.layer?.backgroundColor)
    }

    func testSwiftUIPanelMountsAnOfficialGlassView() {
        let names = mountedClassNames(AppleGlassPanel {
            Text(verbatim: "glass")
                .frame(width: 120, height: 80)
        })
        XCTAssertTrue(
            names.contains { $0.localizedCaseInsensitiveContains("Glass") },
            "Expected SwiftUI glassEffect or NSGlassEffectView, found \(names)"
        )
    }

    func testAppKitBackendMountsNSGlassEffectView() {
        let names = mountedClassNames(AppleGlassPanel(backend: .nsGlassEffectView) {
            Text(verbatim: "glass")
                .frame(width: 120, height: 80)
        })
        XCTAssertTrue(names.contains("NSGlassEffectView"), "\(names)")
        XCTAssertFalse(names.contains("NSColorWell"))
    }

    func testVisualEffectBackendMountsTheSystemMaterial() {
        let root = mount(AppleGlassPanel(backend: .nsVisualEffectView) {
            Text(verbatim: "glass")
                .frame(width: 120, height: 80)
        })
        let effect = firstVisualEffect(in: root)
        XCTAssertNotNil(effect, "Classes: \(classNames(in: root))")
        XCTAssertEqual(effect?.material, .underWindowBackground)
        XCTAssertEqual(effect?.blendingMode, .behindWindow)
        XCTAssertNil(effect?.layer?.backgroundColor)
    }

    func testEditorSourceUsesGlassInsteadOfASolidSlab() throws {
        let editor = try repoFile("Floretta/Shared/Shell/DocumentEditor.swift")
        let glass = try repoFile("Floretta/Shared/Shell/AppleGlassPanel.swift")
        XCTAssertTrue(editor.contains("editor.outline.glass"))
        XCTAssertTrue(editor.contains("editor.inspector.glass"))
        XCTAssertTrue(editor.contains("AppleGlassPanel"))
        XCTAssertTrue(glass.contains("GlassEffectContainer"))
        XCTAssertTrue(glass.contains("glassEffect(.regular, in:"))
        XCTAssertTrue(glass.contains("NSGlassEffectView"))
        XCTAssertTrue(glass.contains("blendingMode = .behindWindow"))
        XCTAssertTrue(glass.contains("material = .underWindowBackground"))
        XCTAssertFalse(glass.contains("Color.white"))
        XCTAssertFalse(glass.contains("Color.gray"))
        XCTAssertFalse(glass.contains(".regularMaterial"))
        XCTAssertFalse(glass.contains("ultraThinMaterial"))
        XCTAssertFalse(glass.contains(".shadow("))

        let panels = try slice(editor, from: ".overlay(alignment: .leading)", until: ".overlay(alignment: .top)")
        XCTAssertTrue(panels.contains("AppleGlassPanel"))
        XCTAssertFalse(panels.contains("backend:"))
        XCTAssertTrue(panels.contains("AppleGlassMetrics.outlineWidth"))
        XCTAssertTrue(panels.contains("AppleGlassMetrics.inspectorWidth"))
        XCTAssertFalse(panels.contains(".regularMaterial"))
        XCTAssertFalse(panels.contains(".background(Color"))
    }

    private func mountedClassNames<V: View>(_ view: V) -> [String] {
        classNames(in: mount(view))
    }

    private func mount<V: View>(_ view: V) -> NSView {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 200, height: 160)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 160),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        window.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        mountedWindows.append(window)
        return hosting
    }

    private func classNames(in view: NSView) -> [String] {
        var names = [String(describing: type(of: view))]
        for subview in view.subviews {
            names.append(contentsOf: classNames(in: subview))
        }
        return names
    }

    private func firstVisualEffect(in view: NSView) -> NSVisualEffectView? {
        if let effect = view as? NSVisualEffectView { return effect }
        for subview in view.subviews {
            if let effect = firstVisualEffect(in: subview) { return effect }
        }
        return nil
    }

    private func repoFile(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
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
