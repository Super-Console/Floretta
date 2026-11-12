import CoreGraphics
import Foundation

/// UI-test-only hook so a pinch-process screenshot can hold the same
/// continuous canvas scale that `MagnifyGesture.onChanged` uses, without
/// the end-of-gesture snap to a legal `ZoomStop`.
///
/// Enabled only when the process was launched with `-FlorettaUITest` and
/// `-FlorettaPinchShot`. The test writes a scale into
/// `/tmp/theme-modes-shot-handshake/hold-scale.txt` (and `FLORETTA_UITEST_DIR`
/// if that directory is visible). The canvas applies `viewport.zoom(to:)` and
/// acknowledges in `hold-scale.ack`. If the test deletes the ack and asks
/// for the same scale again, the hook re-applies and re-acks.
@MainActor
enum CanvasScaleHook {
    static let pinchShotArgument = "-FlorettaPinchShot"
    static let holdScaleArgument = "-FlorettaHoldCanvasScale"
    static let requestFileName = "hold-scale.txt"
    static let ackFileName = "hold-scale.ack"
    static let handshakeDirectory = URL(fileURLWithPath: "/tmp/theme-modes-shot-handshake", isDirectory: true)

    static var isEnabled: Bool {
        // Parsed here so this file can compile in FlorettaTests, which
        // includes Canvas sources but not FlorettaApp.swift (`AppLaunch`).
        ProcessInfo.processInfo.arguments.contains("-FlorettaUITest")
            && ProcessInfo.processInfo.arguments.contains(pinchShotArgument)
    }

    static var initialScale: CGFloat? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: holdScaleArgument),
              arguments.indices.contains(index + 1),
              let value = Double(arguments[index + 1]),
              value.isFinite,
              value > 0
        else { return nil }
        return CanvasViewport.clampScale(CGFloat(value))
    }

    private static var lastApplied: CGFloat?
    private static var appliedInitial = false

    static func resetForTests() {
        lastApplied = nil
        appliedInitial = false
    }

    /// Next scale the canvas should apply, or `nil` if nothing changed.
    static func pendingScale() -> CGFloat? {
        guard isEnabled else { return nil }
        if let fromFile = requestedScaleFromFile() {
            if lastApplied == fromFile, ackMatches(fromFile) { return nil }
            return fromFile
        }
        if !appliedInitial, let initial = initialScale {
            if lastApplied == initial { return nil }
            return initial
        }
        return nil
    }

    static func markApplied(_ scale: CGFloat) {
        lastApplied = scale
        if initialScale != nil { appliedInitial = true }
        let payload = String(format: "%.6f\n", Double(scale))
        for directory in searchDirectories {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? payload.write(to: directory.appendingPathComponent(ackFileName), atomically: true, encoding: .utf8)
        }
    }

    /// Handshake dir first (shared Mac `/tmp`), then `FLORETTA_UITEST_DIR`
    /// after any rewrite via `getenv`.
    private static var searchDirectories: [URL] {
        var directories = [handshakeDirectory]
        if let directory = uiTestDirectory, directory != handshakeDirectory {
            directories.append(directory)
        }
        return directories
    }

    /// Prefer `getenv` so a rewritten `FLORETTA_UITEST_DIR` is visible.
    private static var uiTestDirectory: URL? {
        guard let raw = getenv("FLORETTA_UITEST_DIR") else { return nil }
        let path = String(cString: raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private static func requestedScaleFromFile() -> CGFloat? {
        for directory in searchDirectories {
            let url = directory.appendingPathComponent(requestFileName)
            guard let raw = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value = Double(trimmed), value.isFinite, value > 0 else { continue }
            return CanvasViewport.clampScale(CGFloat(value))
        }
        return nil
    }

    private static func ackMatches(_ scale: CGFloat) -> Bool {
        let expected = String(format: "%.6f", Double(scale))
        for directory in searchDirectories {
            let url = directory.appendingPathComponent(ackFileName)
            guard let raw = try? String(contentsOf: url, encoding: .utf8) else { continue }
            if raw.trimmingCharacters(in: .whitespacesAndNewlines) == expected {
                return true
            }
        }
        return false
    }
}
