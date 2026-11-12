import Foundation
import FlorettaCore
import QuartzCore
import SwiftUI
import os
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Canvas performance run. Off unless the app is launched with `-FlorettaPerfNodes <count>`.
///
/// The run opens `CanvasPerfFixture.document(nodeCount:)`, waits for the open animation, then drives the
/// same camera and document mutations the pan, pinch, and root-drag gestures make, once per display frame:
/// pan 3 s, zoom 50%↔200% two rounds (6 s), drag the fixture's free topic around a circle (3 s), using the same live-origin path as a user drag.
/// It records canvas draws, display-link ticks, and memory, prints one `FLORETTA_PERF_RESULT {json}` line,
/// writes the same JSON to the temporary directory, and quits.
/// `os_signpost` intervals named `InfiniteCanvas.draw` and events named `InfiniteCanvas.body` are emitted
/// under the Points of Interest category so Instruments shows the same spans.
enum CanvasPerfRun {
    static let nodesArgument = "-FlorettaPerfNodes"

    static let requestedNodeCount: Int? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: nodesArgument), index + 1 < arguments.count else { return nil }
        return Int(arguments[index + 1])
    }()

    static let isActive = requestedNodeCount != nil

    static let signposter = OSSignposter(subsystem: "net.timhuang.floretta", category: .pointsOfInterest)

    struct DrawToken {
        var start: CFTimeInterval
        var state: OSSignpostIntervalState
    }

    @MainActor
    static func noteBody() {
        guard isActive else { return }
        signposter.emitEvent("InfiniteCanvas.body")
        CanvasPerfRecorder.shared.bodyCount += 1
    }

    @MainActor
    static func beginDraw() -> DrawToken? {
        guard isActive else { return nil }
        return DrawToken(start: CACurrentMediaTime(), state: signposter.beginInterval("InfiniteCanvas.draw"))
    }

    @MainActor
    static func endDraw(_ token: DrawToken?) {
        guard let token else { return }
        let end = CACurrentMediaTime()
        signposter.endInterval("InfiniteCanvas.draw", token.state)
        CanvasPerfRecorder.shared.recordDraw(start: token.start, end: end)
    }

    @MainActor
    static func noteVisible(_ count: Int) {
        guard isActive else { return }
        CanvasPerfRecorder.shared.noteVisible(count)
    }
}

@MainActor
final class CanvasPerfRecorder {
    static let shared = CanvasPerfRecorder()

    struct Phase {
        var name: String
        var start: CFTimeInterval = 0
        var end: CFTimeInterval = 0
        var ticks: [CFTimeInterval] = []
        var drawEnds: [CFTimeInterval] = []
        var drawDurations: [Double] = []
        var bodyCount = 0
        var maxVisible = 0
        var peakFootprint: UInt64 = 0
    }

    var bodyCount = 0
    private(set) var phases: [Phase] = []
    private var current: Int?
    private var bodyAtPhaseStart = 0

    func begin(_ name: String, at time: CFTimeInterval) {
        finishCurrent(at: time)
        phases.append(Phase(name: name, start: time))
        current = phases.count - 1
        bodyAtPhaseStart = bodyCount
    }

    func finishCurrent(at time: CFTimeInterval) {
        guard let index = current else { return }
        phases[index].end = time
        phases[index].bodyCount = bodyCount - bodyAtPhaseStart
        current = nil
    }

    func recordTick(_ time: CFTimeInterval, sampleMemory: Bool) {
        guard let index = current else { return }
        phases[index].ticks.append(time)
        if sampleMemory {
            phases[index].peakFootprint = max(phases[index].peakFootprint, Self.footprint())
        }
    }

    func recordDraw(start: CFTimeInterval, end: CFTimeInterval) {
        guard let index = current else { return }
        phases[index].drawEnds.append(end)
        phases[index].drawDurations.append((end - start) * 1000)
    }

    func noteVisible(_ count: Int) {
        guard let index = current else { return }
        phases[index].maxVisible = max(phases[index].maxVisible, count)
    }

    static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }

    func summary(nodeCount: Int, displayMaxFPS: Int) -> [String: Any] {
        func round1(_ value: Double) -> Double { (value * 10).rounded() / 10 }
        var list: [[String: Any]] = []
        var peak: UInt64 = 0
        for phase in phases where phase.name != "settle" {
            let duration = max(phase.end - phase.start, 0.001)
            let drawFPS = Double(phase.drawEnds.count) / duration
            let tickFPS = Double(max(phase.ticks.count - 1, 0)) / max((phase.ticks.last ?? 0) - (phase.ticks.first ?? 0), 0.001)
            var buckets: [Int] = []
            let bucket = 0.5
            let bucketCount = Int(duration / bucket)
            if bucketCount > 0 {
                buckets = Array(repeating: 0, count: bucketCount)
                for end in phase.drawEnds {
                    let slot = Int((end - phase.start) / bucket)
                    if slot >= 0, slot < bucketCount { buckets[slot] += 1 }
                }
            }
            let minFPS = buckets.map { Double($0) / bucket }.min() ?? drawFPS
            var longestGap = 0.0
            for (a, b) in zip(phase.ticks, phase.ticks.dropFirst()) { longestGap = max(longestGap, b - a) }
            let sorted = phase.drawDurations.sorted()
            let p95 = sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
            let mean = sorted.isEmpty ? 0 : sorted.reduce(0, +) / Double(sorted.count)
            peak = max(peak, phase.peakFootprint)
            list.append([
                "name": phase.name,
                "seconds": round1(duration),
                "avgFPS": round1(drawFPS),
                "minFPS": round1(minFPS),
                "tickFPS": round1(tickFPS),
                "longestMainThreadFrameMs": round1(longestGap * 1000),
                "maxDrawMs": round1(sorted.last ?? 0),
                "p95DrawMs": round1(p95),
                "meanDrawMs": round1(mean),
                "draws": phase.drawEnds.count,
                "ticks": phase.ticks.count,
                "bodyEvaluations": phase.bodyCount,
                "maxVisibleNodes": phase.maxVisible,
                "peakFootprintMB": round1(Double(phase.peakFootprint) / 1_048_576),
            ])
        }
        #if os(macOS)
        let platform = "macOS"
        #else
        let platform = UIDevice.current.userInterfaceIdiom == .pad ? "iPadOS" : "iOS"
        #endif
        return [
            "platform": platform,
            "nodes": nodeCount,
            "displayMaxFPS": displayMaxFPS,
            "phases": list,
            "peakFootprintMB": round1(Double(peak) / 1_048_576),
        ]
    }
}

/// Drives the camera and document from a display link. See `CanvasPerfRun`.
@MainActor
final class CanvasPerfDriver: NSObject {
    struct Hooks {
        var viewSize: () -> CGSize
        var offset: () -> CGPoint
        var setOffset: (CGPoint) -> Void
        var scale: () -> CGFloat
        var zoom: (CGFloat, CGPoint) -> Void
        var dragTarget: () -> (id: UUID, origin: CGPoint)?
        var move: (UUID, CGPoint) -> Void
    }

    private static var running: CanvasPerfDriver?

    static func start(nodeCount: Int, hooks: Hooks) {
        guard running == nil else { return }
        let driver = CanvasPerfDriver(nodeCount: nodeCount, hooks: hooks)
        running = driver
        driver.attach()
    }

    private enum Step: String {
        case settle, pan, zoom, drag
        var seconds: Double {
            switch self {
            case .settle: 3
            case .pan: 3
            case .zoom: 6
            case .drag: 3
            }
        }
    }

    private let nodeCount: Int
    private let hooks: Hooks
    private let steps: [Step] = [.settle, .pan, .zoom, .drag]
    private var stepIndex = 0
    private var stepStart: CFTimeInterval?
    private var startOffset = CGPoint.zero
    private var startScale: CGFloat = 1
    private var dragTarget: (id: UUID, origin: CGPoint)?
    private var tickCount = 0
    private var link: CADisplayLink?
    private var displayMaxFPS = 60

    private init(nodeCount: Int, hooks: Hooks) {
        self.nodeCount = nodeCount
        self.hooks = hooks
    }

    private func attach() {
        #if os(macOS)
        let screen = NSApplication.shared.windows.first(where: { $0.isVisible && $0.frame.height > 100 })?.screen ?? NSScreen.main
        guard let screen else { return }
        displayMaxFPS = screen.maximumFramesPerSecond
        let link = screen.displayLink(target: self, selector: #selector(tick(_:)))
        #else
        displayMaxFPS = UIScreen.main.maximumFramesPerSecond
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        #endif
        let top = Float(displayMaxFPS)
        link.preferredFrameRateRange = CAFrameRateRange(minimum: min(30, top), maximum: top, preferred: top)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        let recorder = CanvasPerfRecorder.shared
        if stepStart == nil {
            stepStart = now
            recorder.begin(steps[stepIndex].rawValue, at: now)
        }
        guard let started = stepStart else { return }
        var local = now - started
        if local >= steps[stepIndex].seconds {
            stepIndex += 1
            guard stepIndex < steps.count else {
                finish(at: now)
                return
            }
            stepStart = now
            local = 0
            recorder.begin(steps[stepIndex].rawValue, at: now)
            prepare(steps[stepIndex])
        }
        tickCount += 1
        recorder.recordTick(now, sampleMemory: tickCount % 6 == 0)
        apply(steps[stepIndex], at: local)
    }

    private func prepare(_ step: Step) {
        switch step {
        case .pan:
            startOffset = hooks.offset()
            startScale = hooks.scale()
        case .zoom:
            hooks.setOffset(startOffset)
        case .drag:
            hooks.zoom(startScale, center)
            hooks.setOffset(startOffset)
            dragTarget = hooks.dragTarget()
        case .settle:
            break
        }
    }

    private var center: CGPoint {
        let size = hooks.viewSize()
        return CGPoint(x: size.width / 2, y: size.height / 2)
    }

    private func apply(_ step: Step, at t: Double) {
        let phase = 2 * Double.pi * t / step.seconds
        switch step {
        case .settle:
            break
        case .pan:
            hooks.setOffset(CGPoint(
                x: startOffset.x - 420 * CGFloat(sin(phase)),
                y: startOffset.y - 220 * CGFloat(sin(2 * phase))
            ))
        case .zoom:
            // Two rounds, each 50% → 200% → 50%, interpolated on a log scale.
            let round = (t.truncatingRemainder(dividingBy: step.seconds / 2)) / (step.seconds / 2)
            let triangle = 1 - abs(2 * round - 1)
            hooks.zoom(CGFloat(0.5 * pow(4, triangle)), center)
        case .drag:
            guard let dragTarget else { return }
            let radius: CGFloat = 150
            hooks.move(dragTarget.id, CGPoint(
                x: dragTarget.origin.x + radius * (CGFloat(cos(phase)) - 1),
                y: dragTarget.origin.y + radius * CGFloat(sin(phase))
            ))
        }
    }

    private func finish(at time: CFTimeInterval) {
        link?.invalidate()
        link = nil
        let recorder = CanvasPerfRecorder.shared
        recorder.finishCurrent(at: time)
        var summary = recorder.summary(nodeCount: nodeCount, displayMaxFPS: displayMaxFPS)
        summary["finishedAt"] = ISO8601DateFormatter().string(from: Date())
        let data = (try? JSONSerialization.data(withJSONObject: summary, options: [.sortedKeys])) ?? Data()
        let text = String(decoding: data, as: UTF8.self)
        print("FLORETTA_PERF_RESULT \(text)")
        fflush(stdout)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("canvas-perf-\(nodeCount).json")
        try? data.write(to: url)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exit(0) }
    }
}
