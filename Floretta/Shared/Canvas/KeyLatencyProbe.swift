import Foundation
import QuartzCore
import os
#if os(macOS)
import AppKit
#endif

// MARK: - Launch switches

/// Key-to-frame latency measurement for the canvas.
///
/// Inert unless the process is started with `-FlorettaKeyLatency <iterations>`
/// (self-driving run) or `FLORETTA_KEY_LATENCY=1` (probe only, so an external
/// driver can send the keys). The default editor pays one `Bool` check per stage.
enum KeyLatencyRun {
    static let iterationsArgument = "-FlorettaKeyLatency"
    static let nodesArgument = "-FlorettaKeyLatencyNodes"
    static let environmentSwitch = "FLORETTA_KEY_LATENCY"

    private static let arguments = ProcessInfo.processInfo.arguments

    static let requestedIterations: Int? = {
        guard let index = arguments.firstIndex(of: iterationsArgument),
              index + 1 < arguments.count,
              let value = Int(arguments[index + 1]), value > 0 else { return nil }
        return value
    }()

    /// Topic count of the fixture the run opens. Missing keeps a one-topic new map.
    static let requestedNodeCount: Int? = {
        guard let index = arguments.firstIndex(of: nodesArgument),
              index + 1 < arguments.count,
              let value = Int(arguments[index + 1]), value >= 0 else { return nil }
        return value
    }()

    static let drivesItself = requestedIterations != nil

    static let isProbeEnabled = drivesItself
        || ProcessInfo.processInfo.environment[environmentSwitch] == "1"
}

/// The stages the probe times. The order is the order they happen in one key press.
enum KeyLatencyStage: String, CaseIterable, Sendable {
    /// The key reached `.onKeyPress`.
    case keyDown
    /// `MindMapKeyDispatch` returned: the model editor wrote the document back.
    case modelApplied
    /// `DocumentEditor.body` finished a recompute.
    case editorBody
    /// `InfiniteCanvas.body` finished a recompute.
    case canvasBody
    /// The first layout pass after the key produced its frames.
    case framesLaidOut
    /// The first `Canvas` draw after the key started.
    case drawStarted
    /// That draw finished.
    case drawEnded
    /// Core Animation committed the transaction that carries that draw.
    case committed
}

// MARK: - Probe

/// Times one key press from the keyboard event to the frame that shows it.
///
/// Each mark lands once per press: the first body recompute, the first layout
/// pass, the first draw. Later draws (a petal animation, a hover redraw) do not
/// move a mark, so `total` is the first frame that can show the new topic.
@MainActor
final class KeyLatencyProbe {
    static let shared = KeyLatencyProbe()
    static let isEnabled = KeyLatencyRun.isProbeEnabled

    struct Sample: Sendable {
        var name: String
        /// Key press to committed frame. Falls back to the draw end when the
        /// transaction completion did not arrive in time.
        var totalMs: Double
        var totalEndedAtDraw: Bool
        var phases: [String: Double]
        var canvasBodyEvaluations: Int
        var editorBodyEvaluations: Int
        var layoutPasses: Int
        var layoutCostMs: Double
        var canvasBuildMs: Double
        var bodyOffsets: [Double]
        var bodySignatures: [String]
        var editorBuildMs: Double
        var textViewMs: Double
        var editorUpdates: Int
        var chromeWrites: Int
        var boundsPublishes: Int
        var thumbSyncs: Int
        var censusMs: Double
    }

    private struct Run {
        var name: String
        var start: CFTimeInterval
        var marks: [KeyLatencyStage: CFTimeInterval] = [:]
        var canvasBodies = 0
        var editorBodies = 0
        var layoutPasses = 0
        var layoutCost: Double = 0
        var canvasBuildCost: Double = 0
        var editorBuildCost: Double = 0
        var textViewCost: Double = 0
        var censusCost: Double = 0
        var bodyOffsets: [Double] = []
        var bodySignatures: [String] = []
        var editorUpdates = 0
        var chromeWrites = 0
        var boundsPublishes = 0
        var thumbSyncs = 0
        var interval: OSSignpostIntervalState?
    }

    private var run: Run?
    private(set) var samples: [Sample] = []
    /// Keys the probe saw but could not finish, because the mark never arrived.
    private(set) var abandoned = 0
    private(set) var keyDownCount = 0

    private let signposter = OSSignposter(subsystem: "net.timhuang.floretta", category: .pointsOfInterest)

    var isTiming: Bool { run != nil }

    // MARK: Press lifetime

    /// Starts a press. Called by the driver before it posts the key, or by the
    /// key handler itself when an external driver owns the keys.
    func begin(_ name: String) {
        guard Self.isEnabled else { return }
        if run != nil { finish() }
        run = Run(
            name: name,
            start: CACurrentMediaTime(),
            interval: signposter.beginInterval("KeyLatency.press")
        )
        signposter.emitEvent("KeyLatency.begin")
    }

    /// The canvas saw a Tab or Return key down. Starts a press when nobody else
    /// did, so an external driver with `FLORETTA_KEY_LATENCY=1` needs no handshake.
    func noteKeyPress(name: String) {
        guard Self.isEnabled else { return }
        keyDownCount += 1
        if run == nil { begin(name) }
        mark(.keyDown)
    }

    /// One `camera.contentBounds` write from the canvas.
    func countBoundsPublish() {
        guard Self.isEnabled, var run else { return }
        run.boundsPublishes += 1
        self.run = run
    }

    /// One `refreshThumbnails` pass.
    func countThumbnailSync() {
        guard Self.isEnabled, var run else { return }
        run.thumbSyncs += 1
        self.run = run
    }

    /// One `updateNSView` of the node editor.
    func countEditorUpdate() {
        guard Self.isEnabled, var run else { return }
        run.editorUpdates += 1
        self.run = run
    }

    /// One full AppKit chrome write on the node editor.
    func countChromeWrite() {
        guard Self.isEnabled, var run else { return }
        run.chromeWrites += 1
        self.run = run
    }

    /// Times one layout pass and records it. Returns the pass output unchanged.
    func timeLayout<T>(_ body: () -> T) -> T {
        guard Self.isEnabled, run != nil else { return body() }
        let start = CACurrentMediaTime()
        let result = body()
        countLayoutPass(cost: CACurrentMediaTime() - start)
        return result
    }

    /// Times one SwiftUI `body` build. `kind` names the view in the report.
    func timeBuild<T>(_ kind: String, _ body: () -> T) -> T {
        guard Self.isEnabled, run != nil else { return body() }
        let start = CACurrentMediaTime()
        let result = body()
        add(build: CACurrentMediaTime() - start, to: kind)
        return result
    }

    /// Times the AppKit text view the edit field creates on every entry to edit mode.
    func timeTextView<T>(_ body: () -> T) -> T {
        guard Self.isEnabled, run != nil else { return body() }
        let start = CACurrentMediaTime()
        let result = body()
        add(build: CACurrentMediaTime() - start, to: "textView")
        return result
    }

    /// Times the topic/word/character census the status capsule reads.
    func timeCensus<T>(_ body: () -> T) -> T {
        guard Self.isEnabled, run != nil else { return body() }
        let start = CACurrentMediaTime()
        let result = body()
        add(build: CACurrentMediaTime() - start, to: "census")
        return result
    }

    private func add(build cost: Double, to kind: String) {
        guard Self.isEnabled, var run else { return }
        switch kind {
        case "canvas": run.canvasBuildCost += cost
        case "editor": run.editorBuildCost += cost
        case "textView": run.textViewCost += cost
        case "census": run.censusCost += cost
        default: break
        }
        self.run = run
    }

    func mark(_ stage: KeyLatencyStage) {
        guard Self.isEnabled, var run else { return }
        guard run.marks[stage] == nil else { return }
        run.marks[stage] = CACurrentMediaTime()
        self.run = run
        emit(stage)
        if stage == .committed { finish() }
    }

    /// Counts one `DocumentEditor.body` recompute.
    func countEditorBody() {
        guard Self.isEnabled, var run else { return }
        run.editorBodies += 1
        self.run = run
        if run.marks[.editorBody] == nil { mark(.editorBody) }
    }

    /// Counts one `InfiniteCanvas.body` recompute and marks the first one.
    func countCanvasBody(signature: String = "") {
        guard Self.isEnabled, var run else { return }
        run.canvasBodies += 1
        run.bodyOffsets.append((CACurrentMediaTime() - run.start) * 1000)
        run.bodySignatures.append(signature)
        self.run = run
        if run.marks[.canvasBody] == nil { mark(.canvasBody) }
    }

    /// One `CanvasPlacement.nodes` pass, timed. Marks the first pass of the press.
    func countLayoutPass(cost: Double) {
        guard Self.isEnabled, var run else { return }
        run.layoutPasses += 1
        run.layoutCost += cost
        self.run = run
        if run.marks[.framesLaidOut] == nil { mark(.framesLaidOut) }
    }

    /// Asks Core Animation to tell us when the frame carrying this draw commits.
    /// Without it a press would report the draw start only.
    func noteDrawEnded() {
        guard Self.isEnabled, let run, run.marks[.drawEnded] != nil, run.marks[.committed] == nil else { return }
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            Task { @MainActor in self?.mark(.committed) }
        }
        CATransaction.commit()
    }

    private func emit(_ stage: KeyLatencyStage) {
        switch stage {
        case .keyDown: signposter.emitEvent("KeyLatency.keyDown")
        case .modelApplied: signposter.emitEvent("KeyLatency.modelApplied")
        case .editorBody: signposter.emitEvent("KeyLatency.body.editor")
        case .canvasBody: signposter.emitEvent("KeyLatency.body.canvas")
        case .framesLaidOut: signposter.emitEvent("KeyLatency.framesLaidOut")
        case .drawStarted: signposter.emitEvent("KeyLatency.draw.started")
        case .drawEnded: signposter.emitEvent("KeyLatency.draw.ended")
        case .committed: signposter.emitEvent("KeyLatency.committed")
        }
    }

    /// Closes the press. `committed` normally calls this; the driver calls it when
    /// a mark never arrived, so one broken press cannot stall a whole run.
    @discardableResult
    func finish() -> Sample? {
        guard var run else { return nil }
        self.run = nil
        if let interval = run.interval {
            signposter.endInterval("KeyLatency.press", interval)
        }
        let end = run.marks[.committed] ?? run.marks[.drawEnded]
        guard let end else {
            abandoned += 1
            return nil
        }
        var phases: [String: Double] = [:]
        for (stage, time) in run.marks {
            phases[stage.rawValue] = (time - run.start) * 1000
        }
        let sample = Sample(
            name: run.name,
            totalMs: (end - run.start) * 1000,
            totalEndedAtDraw: run.marks[.committed] == nil,
            phases: phases,
            canvasBodyEvaluations: run.canvasBodies,
            editorBodyEvaluations: run.editorBodies,
            layoutPasses: run.layoutPasses,
            layoutCostMs: run.layoutCost * 1000,
            canvasBuildMs: run.canvasBuildCost * 1000,
            bodyOffsets: run.bodyOffsets,
            bodySignatures: run.bodySignatures,
            editorBuildMs: run.editorBuildCost * 1000,
            textViewMs: run.textViewCost * 1000,
            editorUpdates: run.editorUpdates,
            chromeWrites: run.chromeWrites,
            boundsPublishes: run.boundsPublishes,
            thumbSyncs: run.thumbSyncs,
            censusMs: run.censusCost * 1000
        )
        samples.append(sample)
        return sample
    }

    // MARK: Report

    private static func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        if sorted.count == 1 { return sorted[0] }
        let rank = Int((Double(sorted.count - 1) * fraction).rounded(.up))
        return sorted[min(max(rank, 0), sorted.count - 1)]
    }

    private static func summary(_ values: [Double]) -> [String: Double] {
        let sorted = values.sorted()
        return [
            "n": Double(sorted.count),
            "p50": percentile(sorted, 0.5),
            "p95": percentile(sorted, 0.95),
            "min": sorted.first ?? 0,
            "max": sorted.last ?? 0,
            "mean": sorted.isEmpty ? 0 : sorted.reduce(0, +) / Double(sorted.count),
        ]
    }

    func report() -> [String: Any] {
        var byKey: [String: [[String: Any]]] = [:]
        for sample in samples {
            let phases: [String: Double] = sample.phases
            var entry: [String: Any] = [
                "total": sample.totalMs,
                "endedAtDraw": sample.totalEndedAtDraw,
                "canvasBodyEvaluations": Double(sample.canvasBodyEvaluations),
                "editorBodyEvaluations": Double(sample.editorBodyEvaluations),
                "layoutPasses": Double(sample.layoutPasses),
                "layoutCost": sample.layoutCostMs,
                "canvasBuild": sample.canvasBuildMs,
                "editorBuild": sample.editorBuildMs,
                "textViewCreate": sample.textViewMs,
                "census": sample.censusMs,
                "editorUpdates": Double(sample.editorUpdates),
                "chromeWrites": Double(sample.chromeWrites),
                "boundsPublishes": Double(sample.boundsPublishes),
                "thumbSyncs": Double(sample.thumbSyncs),
            ]
            for stage in KeyLatencyStage.allCases {
                if let value = phases[stage.rawValue] { entry[stage.rawValue] = value }
            }
            byKey[sample.name, default: []].append(entry)
        }

        var keys: [String: Any] = [:]
        for (name, entries) in byKey.sorted(by: { $0.key < $1.key }) {
            var metrics: [String: Any] = [:]
            let totals = entries.compactMap { $0["total"] as? Double }
            metrics["total"] = Self.summary(totals)
            metrics["endedAtDraw"] = Double(entries.filter { $0["endedAtDraw"] as? Bool == true }.count)
            metrics["editorBodyEvaluations"] = Self.summary(entries.compactMap { $0["editorBodyEvaluations"] as? Double })
            metrics["canvasBodyEvaluations"] = Self.summary(entries.compactMap { $0["canvasBodyEvaluations"] as? Double })
            metrics["layoutPasses"] = Self.summary(entries.compactMap { $0["layoutPasses"] as? Double })
            metrics["layoutCost"] = Self.summary(entries.compactMap { $0["layoutCost"] as? Double })
            metrics["canvasBuild"] = Self.summary(entries.compactMap { $0["canvasBuild"] as? Double })
            metrics["editorBuild"] = Self.summary(entries.compactMap { $0["editorBuild"] as? Double })
            metrics["textViewCreate"] = Self.summary(entries.compactMap { $0["textViewCreate"] as? Double })
            metrics["census"] = Self.summary(entries.compactMap { $0["census"] as? Double })
            metrics["editorUpdates"] = Self.summary(entries.compactMap { $0["editorUpdates"] as? Double })
            metrics["chromeWrites"] = Self.summary(entries.compactMap { $0["chromeWrites"] as? Double })
            metrics["boundsPublishes"] = Self.summary(entries.compactMap { $0["boundsPublishes"] as? Double })
            metrics["thumbSyncs"] = Self.summary(entries.compactMap { $0["thumbSyncs"] as? Double })
            for stage in KeyLatencyStage.allCases {
                let values = entries.compactMap { $0[stage.rawValue] as? Double }
                guard !values.isEmpty else { continue }
                metrics[stage.rawValue] = Self.summary(values)
            }
            keys[name] = metrics
        }

        var report: [String: Any] = [
            "platform": Self.platformName,
            "mode": KeyLatencyRun.drivesItself ? "driver" : "probe",
            "iterations": Double(KeyLatencyRun.requestedIterations ?? 0),
            "nodeCount": Double(KeyLatencyRun.requestedNodeCount ?? 0),
            "samples": Double(samples.count),
            "abandoned": Double(abandoned),
            "keyDowns": Double(keyDownCount),
            "byKey": keys,
            "finishedAt": ISO8601DateFormatter().string(from: Date()),
        ]
        report["driver"] = KeyLatencyDriver.diagnostics
        report["sequences"] = samples.map {
            ["name": $0.name, "total": $0.totalMs, "bodyOffsets": $0.bodyOffsets, "bodySignatures": $0.bodySignatures]
        }
        return report
    }

    static var platformName: String {
        #if os(macOS)
        "macOS"
        #elseif os(iOS)
        "iOS"
        #else
        "unknown"
        #endif
    }

    /// One line per key, so a terminal run reads without opening the JSON.
    func textSummary() -> String {
        var lines: [String] = []
        let names = Set(samples.map(\.name)).sorted()
        for name in names {
            let totals = samples.filter { $0.name == name }.map(\.totalMs)
            let sorted = totals.sorted()
            let stats = Self.summary(sorted)
            let phases = samples.filter { $0.name == name }.flatMap { Array($0.phases.keys) }
            let phaseNames = Set(phases).sorted()
            var detail: [String] = []
            for phase in phaseNames {
                let values = samples.filter { $0.name == name }.compactMap { $0.phases[phase] }
                let phaseStats = Self.summary(values)
                detail.append(String(format: "%@ p50=%.1f p95=%.1f", phase, phaseStats["p50"] ?? 0, phaseStats["p95"] ?? 0))
            }
            lines.append(String(
                format: "%@ n=%.0f total p50=%.1fms p95=%.1fms mean=%.1f max=%.1f | %@",
                name,
                stats["n"] ?? 0,
                stats["p50"] ?? 0,
                stats["p95"] ?? 0,
                stats["mean"] ?? 0,
                stats["max"] ?? 0,
                detail.joined(separator: "; ")
            ))
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Driver

#if os(macOS)
/// Measures busy versus idle main-run-loop time, so a slow press can be told
/// apart from a frame that simply arrived late.
@MainActor
final class RunLoopGapSampler {
    private var busy: [CFTimeInterval] = []
    private var idle: [CFTimeInterval] = []
    private var observer: CFRunLoopObserver?
    private var busySince: CFTimeInterval?
    private var idleSince: CFTimeInterval?

    func start() {
        var context = CFRunLoopObserverContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        guard let observer = CFRunLoopObserverCreate(
            kCFAllocatorDefault,
            CFRunLoopActivity.allActivities.rawValue,
            true,
            0,
            { _, activity, info in
                guard let info else { return }
                let sampler = Unmanaged<RunLoopGapSampler>.fromOpaque(info).takeUnretainedValue()
                MainActor.assumeIsolated { sampler.note(activity) }
            },
            &context
        ) else { return }
        self.observer = observer
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }

    private func note(_ activity: CFRunLoopActivity) {
        let now = CACurrentMediaTime()
        switch activity {
        case .beforeSources, .beforeTimers:
            if let since = idleSince {
                idle.append(now - since)
                idleSince = nil
            }
            if busySince == nil { busySince = now }
        case .beforeWaiting, .afterWaiting, .exit:
            if let since = busySince {
                busy.append(now - since)
                busySince = nil
            }
            if idleSince == nil { idleSince = now }
        default:
            break
        }
    }

    func summary() -> [String: Double] {
        func total(_ values: [CFTimeInterval]) -> Double { values.reduce(0, +) * 1000 }
        return [
            "busyMs": (total(busy) * 10).rounded() / 10,
            "idleMs": (total(idle) * 10).rounded() / 10,
            "busySpans": Double(busy.count),
            "idleSpans": Double(idle.count),
            "longestBusyMs": ((busy.max() ?? 0) * 1000 * 10).rounded() / 10,
            "longestIdleMs": ((idle.max() ?? 0) * 1000 * 10).rounded() / 10,
        ]
    }
}

/// Posts real Tab / Return key events into the editor window and reads the probe.
///
/// Only runs with `-FlorettaKeyLatency <iterations>`. The run leaves the window on
/// a second display when the Mac has one, takes no screenshots, and terminates.
@MainActor
enum KeyLatencyDriver {
    private static var started = false
    private(set) static var diagnostics: [String: Any] = [:]
    private static var window: NSWindow?
    private static var posted = 0
    private static var landed = 0
    /// Kept alive for the run so App Nap cannot stretch the measured frames.
    private static var activity: NSObjectProtocol?
    private static var previousApp: NSRunningApplication?

    enum Kind: String, CaseIterable {
        case tab
        case enter
        /// Control: selects a sibling and stays in command mode. It measures the
        /// cost every canvas update pays, without opening the text field.
        case arrow

        var keyCode: UInt16 {
            switch self {
            case .tab: 48
            case .enter: 36
            case .arrow: 124
            }
        }

        var characters: String {
            switch self {
            case .tab: "\t"
            case .enter: "\r"
            case .arrow: "\u{F703}"
            }
        }
    }

    static func startIfRequested() {
        guard KeyLatencyRun.drivesItself, !started else { return }
        started = true
        Task { @MainActor in await run() }
    }

    private static func run() async {
        // A napped app coalesces its frames, which would measure the power
        // management policy instead of the editor. The user's window is live.
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical, .idleSystemSleepDisabled],
            reason: "Floretta key latency run"
        )
        previousApp = NSWorkspace.shared.frontmostApplication
        await settle(milliseconds: 1200)
        guard let found = editorWindow() else {
            diagnostics["error"] = "no editor window"
            writeReport()
            await settle(milliseconds: 200)
            NSApp.terminate(nil)
            return
        }
        window = found
        // Move the probe window before making it key. The toolbar benchmark is
        // run on the secondary display so activating the window never flashes
        // its initial frame over the user's primary display.
        placeWindow(found)
        NSApp.activate(ignoringOtherApps: true)
        found.makeKeyAndOrderFront(nil)
        gapSampler = RunLoopGapSampler()
        gapSampler?.start()
        diagnostics["windowIsKey"] = found.isKeyWindow
        diagnostics["firstResponder"] = String(describing: found.firstResponder.map { type(of: $0) })
        diagnostics["screens"] = NSScreen.screens.count

        await settle(milliseconds: 600)
        let iterations = KeyLatencyRun.requestedIterations ?? 0
        for _ in 0..<iterations {
            for kind in Kind.allCases {
                await leaveEditMode()
                await settle(milliseconds: 120)
                KeyLatencyProbe.shared.begin(kind.rawValue)
                post(kind)
                posted += 1
                await waitForSample()
                await settle(milliseconds: 60)
                if KeyLatencyProbe.shared.samples.last?.name == kind.rawValue { landed += 1 }
            }
        }
        await leaveEditMode()
        if let sampler = gapSampler {
            diagnostics["mainThreadBusyMs"] = sampler.summary()
        }
        diagnostics["posted"] = posted
        diagnostics["landed"] = landed
        diagnostics["windowIsKeyAfter"] = window?.isKeyWindow ?? false
        diagnostics["appActive"] = NSApp.isActive
        diagnostics["occlusionVisible"] = window?.occlusionState.contains(.visible) ?? false
        diagnostics["firstResponderAfter"] = String(describing: window?.firstResponder.map { type(of: $0) })
        writeReport()
        await settle(milliseconds: 400)
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        previousApp?.activate(options: [.activateIgnoringOtherApps])
        await settle(milliseconds: 200)
        NSApp.terminate(nil)
    }

    private static func editorWindow() -> NSWindow? {
        NSApp.windows
            .filter { !($0 is NSPanel) && $0.contentView != nil && $0.frame.width >= 400 }
            .max { $0.frame.width < $1.frame.width }
    }

    /// AGENTS.md keeps GUI runs off the display the user works on.
    private static func placeWindow(_ window: NSWindow) {
        let screens = NSScreen.screens
        guard screens.count > 1 else { return }
        guard let secondary = screens.max(by: { $0.frame.origin.x < $1.frame.origin.x }) else { return }
        var frame = window.frame
        let visible = secondary.visibleFrame
        frame.origin = CGPoint(x: visible.minX + 60, y: visible.maxY - frame.height - 60)
        window.setFrame(frame, display: true)
    }

    private static func post(_ kind: Kind) {
        guard let window else { return }
        let timestamp = ProcessInfo.processInfo.systemUptime
        guard let down = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: timestamp,
            windowNumber: window.windowNumber,
            context: nil,
            characters: kind.characters,
            charactersIgnoringModifiers: kind.characters,
            isARepeat: false,
            keyCode: kind.keyCode
        ) else { return }
        NSApp.sendEvent(down)
        let up = NSEvent.keyEvent(
            with: .keyUp,
            location: .zero,
            modifierFlags: [],
            timestamp: timestamp + 0.04,
            windowNumber: window.windowNumber,
            context: nil,
            characters: kind.characters,
            charactersIgnoringModifiers: kind.characters,
            isARepeat: false,
            keyCode: kind.keyCode
        )
        if let up {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                NSApp.sendEvent(up)
            }
        }
    }

    /// Escape commits the open topic and puts the canvas back in command mode.
    private static func leaveEditMode() async {
        guard let window else { return }
        guard let escape = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false,
            keyCode: 53
        ) else { return }
        NSApp.sendEvent(escape)
        await settle(milliseconds: 200)
    }

    private static func waitForSample() async {
        let deadline = Date().addingTimeInterval(2.5)
        while Date() < deadline {
            if !KeyLatencyProbe.shared.isTiming { return }
            await settle(milliseconds: 10)
        }
        KeyLatencyProbe.shared.finish()
    }

    /// Records how the main run loop spends a press: executing sources (busy)
    /// or waiting for the next event (idle). Diagnostic only.
    private static var gapSampler: RunLoopGapSampler?

    private static func settle(milliseconds: Int) async {
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }

    private static func writeReport() {
        let report = KeyLatencyProbe.shared.report()
        let jsonText: String
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted]) {
            jsonText = String(decoding: data, as: UTF8.self)
        } else {
            jsonText = "{}"
        }
        let text = "KEY_LATENCY_RESULT " + jsonText
        print(text)
        print(KeyLatencyProbe.shared.textSummary())
        fflush(stdout)
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("floretta-key-latency.json")
        try? Data(text.utf8).write(to: url, options: .atomic)
    }
}
#endif

#if !os(macOS)
/// The key-latency run drives an AppKit window and posts `NSEvent`s, so there is
/// nothing to drive here. The probe and its hooks still compile on every
/// platform so the code under test stays identical; `startIfRequested` is the
/// no-op the shared `onAppear` calls.
@MainActor
enum KeyLatencyDriver {
    static var diagnostics: [String: Any] = [:]

    static func startIfRequested() {}
}
#endif
