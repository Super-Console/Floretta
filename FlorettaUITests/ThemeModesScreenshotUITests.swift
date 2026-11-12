import XCTest

/// Canvas-perf probe and pinch-process typography shots for PR #119.
///
/// These are opt-in so a default UITest scheme run does not launch the
/// 500-node probe or wait on an external screenshot poller:
/// - `FLORETTA_RUN_PERF_PROBE=1` runs `testCanvasPerf500ViaUITest`
/// - `FLORETTA_RUN_THEME_SHOTS=1` runs `testPinchZoomGlyphContinuity`
/// - A leftover `/tmp/floretta-run-theme-shots` or `/tmp/floretta-run-perf-probe`
///   flag also opts in, unless the matching env var is explicitly `0`.
///   `scripts/pre-release.sh` sets both to `0` and skips this class so a
///   leftover flag cannot fail the gate when no poller is started.
///   An intentional run (`=1`, or a flag without `=0`) still waits on the
///   poller and fails if it does not write `.done`.
final class ThemeModesScreenshotUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private static func isOptIn(_ envKey: String, flagFile: String) -> Bool {
        let env = ProcessInfo.processInfo.environment[envKey]
        // Explicit 0 wins, including pre-release, even if a leftover
        // flag file is still sitting in /tmp.
        if env == "0" { return false }
        return env == "1" || FileManager.default.isReadableFile(atPath: flagFile)
    }

    @MainActor
    func testCanvasPerf500ViaUITest() throws {
        try XCTSkipUnless(
            Self.isOptIn("FLORETTA_RUN_PERF_PROBE", flagFile: "/tmp/floretta-run-perf-probe"),
            "opt-in canvas-perf probe; not part of a default UITest run"
        )
        let app = XCUIApplication()
        app.launchArguments = [
            "-FlorettaUITest",
            "-FlorettaPerfNodes", "500",
            "-FlorettaLanguage", "zh-Hans",
            "-AppleLanguages", "(zh-Hans)",
            "-AppleLocale", "zh_CN",
        ]
        let started = Date()
        app.launch()
        // settle 3 + pan 3 + zoom 6 + drag 3 + bloom/open + result write
        let deadline = Date().addingTimeInterval(75)
        while Date() < deadline {
            let state = app.state
            if state == .notRunning || state == .unknown {
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        let elapsed = Date().timeIntervalSince(started)
        let state = app.state
        print("FLORETTA_PERF_UITEST_DONE elapsed=\(String(format: "%.1f", elapsed)) state=\(state.rawValue)")
    }

    /// Opens the same glyph-sample document, sets EB Garamond, dismisses the
    /// inspector, then holds the continuous pinch scales 100/85/70/55% using
    /// the same `viewport.zoom(to:)` path as `MagnifyGesture.onChanged`.
    /// An external poller writes `docs/reviews/theme-modes/pinch-*.png`.
    @MainActor
    func testPinchZoomGlyphContinuity() throws {
        try XCTSkipUnless(
            Self.isOptIn("FLORETTA_RUN_THEME_SHOTS", flagFile: "/tmp/floretta-run-theme-shots"),
            "opt-in pinch-process typography shots; not part of a default UITest run"
        )

        let root = makeUITestRoot()
        let sample = glyphSampleURL()
        XCTAssertTrue(FileManager.default.isReadableFile(atPath: sample.path), "missing \(sample.path)")
        let imported = root.appendingPathComponent("import", isDirectory: true).appendingPathComponent("glyph-sample.floretta")
        try FileManager.default.copyItem(at: sample, to: imported)

        let app = XCUIApplication()
        app.launchArguments = [
            "-FlorettaUITest",
            "-FlorettaPinchShot",
            "-FlorettaHoldCanvasScale", "1.0",
            "-FlorettaLanguage", "zh-Hans",
            "-AppleLanguages", "(zh-Hans)",
            "-AppleLocale", "zh_CN",
        ]
        app.launchEnvironment["FLORETTA_UITEST_DIR"] = root.path
        app.launchEnvironment["FLORETTA_UITEST_IMPORT_FILE"] = imported.path
        app.launch()

        XCTAssertTrue(app.buttons["home.toolbarMenu"].waitForExistence(timeout: 20), "homepage did not appear")
        app.buttons["home.toolbarMenu"].tap()
        XCTAssertTrue(app.buttons["home.open"].waitForExistence(timeout: 5))
        app.buttons["home.open"].tap()
        let openFiles = app.buttons["从文件应用打开"]
        XCTAssertTrue(openFiles.waitForExistence(timeout: 5))
        openFiles.tap()

        let title = app.buttons["document.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "document title missing after import")
        XCTAssertEqual(title.label, "字形样本")

        openInspector(app)
        let classic = app.descendants(matching: .any)["inspector.appearance.classic"]
        if classic.waitForExistence(timeout: 3), classic.isHittable {
            classic.tap()
        }
        let family = app.descendants(matching: .any)["inspector.appearance.fontFamily"]
        XCTAssertTrue(family.waitForExistence(timeout: 5), "font family picker missing")
        family.tap()
        let garamond = app.descendants(matching: .any)["inspector.appearance.fontFamily.eb-garamond"]
        XCTAssertTrue(garamond.waitForExistence(timeout: 5), "EB Garamond option missing")
        garamond.tap()
        // Confirm the menu picked a named face, not a system fallback.
        XCTAssertTrue(app.staticTexts["EB Garamond"].waitForExistence(timeout: 3) || garamond.exists)
        dismissInspector(app)

        fitToWindow(app)
        requestScale(1.0, root: root, app: app)

        let shots: [(String, CGFloat)] = [
            ("pinch-100", 1.00),
            ("pinch-85", 0.85),
            ("pinch-70", 0.70),
            ("pinch-55", 0.55),
        ]
        for (name, scale) in shots {
            requestScale(scale, root: root, app: app)
            // Let the canvas redraw at the held scale before the poller captures.
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
            handshakeShot(name)
        }
        print("FLORETTA_PINCH_SHOTS_DONE")
    }

    @MainActor
    private func inspectorIsOpen(_ app: XCUIApplication) -> Bool {
        app.descendants(matching: .any)["inspector.appearance.fontFamily"].exists
            || app.descendants(matching: .any)["inspector.header"].exists
            || app.descendants(matching: .any)["inspector.tabs"].exists
    }

    @MainActor
    private func openInspector(_ app: XCUIApplication) {
        if inspectorIsOpen(app) { return }
        let open = app.descendants(matching: .any)["inspector.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 8), "inspector.open missing")
        open.tap()
        let opened = app.descendants(matching: .any)["inspector.appearance.fontFamily"].waitForExistence(timeout: 5)
            || app.descendants(matching: .any)["inspector.tabs"].waitForExistence(timeout: 2)
        XCTAssertTrue(opened || inspectorIsOpen(app), "inspector did not open")
    }

    @MainActor
    private func dismissInspector(_ app: XCUIApplication) {
        // Compact (iPhone) uses a sheet handle. iPad regular width has no
        // handle; the paintbrush button toggles the trailing inspector.
        let dismiss = app.buttons["inspector.dismiss"]
        if dismiss.waitForExistence(timeout: 1), dismiss.isHittable {
            dismiss.tap()
        } else {
            let open = app.descendants(matching: .any)["inspector.open"]
            XCTAssertTrue(open.waitForExistence(timeout: 3), "inspector.open missing; cannot toggle inspector shut")
            open.tap()
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    }

    @MainActor
    private func fitToWindow(_ app: XCUIApplication) {
        let zoom = app.descendants(matching: .any)["statusBar.zoom"]
        guard zoom.waitForExistence(timeout: 5) else { return }
        zoom.tap()
        let fit = app.buttons["适应窗口"]
        if fit.waitForExistence(timeout: 3) {
            fit.tap()
        } else {
            // Dismiss the menu if the fit item did not appear.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    }

    @MainActor
    private func requestScale(_ scale: CGFloat, root: URL, app: XCUIApplication) {
        let handshake = URL(fileURLWithPath: "/tmp/theme-modes-shot-handshake", isDirectory: true)
        try? FileManager.default.createDirectory(at: handshake, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: handshake.path)
        let directories = [handshake, root]
        for directory in directories {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("hold-scale.ack"))
        }
        let payload = String(format: "%.6f\n", Double(scale))
        for directory in directories {
            try? payload.write(to: directory.appendingPathComponent("hold-scale.txt"), atomically: true, encoding: .utf8)
        }
        let expected = String(format: "%.6f", Double(scale))
        let percent = Int((scale * 100).rounded())
        let predicate = NSPredicate { _, _ in
            for directory in directories {
                let ack = directory.appendingPathComponent("hold-scale.ack")
                if let raw = try? String(contentsOf: ack, encoding: .utf8),
                   raw.trimmingCharacters(in: .whitespacesAndNewlines) == expected {
                    return true
                }
            }
            let badge = app.descendants(matching: .any)["uitest.heldCanvasScale"]
            return badge.exists && (badge.label.contains("\(percent)%") || badge.staticTexts["pinch scale \(percent)%"].exists)
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        let result = XCTWaiter.wait(for: [expectation], timeout: 15)
        XCTAssertEqual(result, .completed, "canvas did not hold scale \(scale) (no ack and no pinch-scale badge)")
    }

    private func handshakeShot(_ name: String, timeout: TimeInterval = 30) {
        let dir = URL(fileURLWithPath: "/tmp/theme-modes-shot-handshake", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ready = dir.appendingPathComponent("\(name).ready")
        let done = dir.appendingPathComponent("\(name).done")
        try? FileManager.default.removeItem(at: ready)
        try? FileManager.default.removeItem(at: done)
        try? "ready\n".write(to: ready, atomically: true, encoding: .utf8)
        let predicate = NSPredicate { _, _ in
            FileManager.default.isReadableFile(atPath: done.path)
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, "screenshot poller did not capture \(name)")
    }

    private func makeUITestRoot() -> URL {
        let root = URL(fileURLWithPath: "/tmp/floretta-theme-shots-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: root.appendingPathComponent("export", isDirectory: true),
            withIntermediateDirectories: true
        )
        try? FileManager.default.createDirectory(
            at: root.appendingPathComponent("import", isDirectory: true),
            withIntermediateDirectories: true
        )
        try? FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: root.path)
        return root
    }

    private func glyphSampleURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("docs/reviews/theme-modes/glyph-sample.floretta")
    }
}
