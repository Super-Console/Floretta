import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Petal expand / collapse for a map open or a single branch toggle.
///
/// Easing is CSS **easeOutBack** (not a spring). The closed form is
/// `1 + (c1 + 1) (t - 1)^3 + c1 (t - 1)^2` with `c1 = 1.70158`.
/// It starts at 0, overshoots to about 1.10, and finishes at 1.
/// A spring would need an integrator and leftover velocity between frames.
/// easeOutBack is one polynomial per sample, so playback does not allocate
/// and does not call `LayoutEngine`.
///
/// Motion is a scale and a translation along the ray from the parent center
/// (the small circle) out to the laid-out center. Branches are not rotated,
/// so this is not a butterfly-wing flap. Deeper petals wait a short step
/// before they leave the circle. When the clock finishes, drawing uses the
/// layout frames unchanged.
///
/// Performance: one layout produces the frames. Each animation frame only
/// samples this plan. At most one plan runs at a time. At most
/// `PetalExpandTiming.maxAnimated` nodes get their own pose; the rest stay
/// hidden until the clock ends, then appear at the layout position.
/// `layoutPassesDuringPlayback` counts layouts the canvas reports while the
/// clock is running. It must stay 0. Linux can time the pose math. It cannot
/// record SwiftUI frame rate; a Mac rechecks the 55 fps floor on device.
public enum PetalEasing {
    public static let name = "easeOutBack"
    /// Standard CSS overshoot. Peak of the curve is about 1.10.
    public static let overshoot = 1.70158

    public static func easeOutBack(_ t: Double) -> Double {
        let x = min(1, max(0, t))
        let c1 = overshoot
        let c3 = c1 + 1
        return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
    }
}

public enum PetalExpandTiming {
    /// How long one petal travels after its step delay.
    public static let petalDuration: TimeInterval = 0.28
    /// Wait between depth steps. The first ring does not wait.
    public static let stepDelay: TimeInterval = 0.06
    /// Depth steps that get their own delay. Deeper petals share the last step.
    public static let maxStep = 3
    /// Scale of the small circle at the start of a petal.
    public static let budScale: Double = 0.16
    /// Text stays off until the petal is mostly out, so early frames skip labels.
    public static let textGrowth = 0.72
    /// Cap on petals with their own pose. The tail waits for the settled layout.
    public static let maxAnimated = 48
    /// A new load or toggle replaces the one running plan. It does not stack.
    public static let maxConcurrent = 1
    /// easeOutBack peaks near 1.10. Keep a little headroom and no more.
    public static let maxGrowth = 1.12
    /// Layouts allowed while the clock is running. The transition layout happens before.
    public static let maxLayoutPassesDuringPlayback = 0
    /// Floor from the performance bar. Pose math has to fit under one frame.
    public static let minimumFramesPerSecond = 55

    public static var frameBudget: TimeInterval { 1 / TimeInterval(minimumFramesPerSecond) }
}

public enum PetalMotionKind: Equatable, Sendable {
    case mapOpen
    case expand(UUID)
    case collapse(UUID)
}

public enum PetalDocumentDelta: Equatable, Sendable {
    case none
    case unrelated
    case mapOpen
    case expand(UUID)
    case collapse(UUID)
}

/// Collapse flags and identity. Text, selection, drag, and pan are not in here,
/// so those edits cannot start a petal animation.
public struct CollapseFingerprint: Equatable, Sendable {
    public var ids: [UUID]
    public var collapsed: [UUID]
    public var roots: [UUID]

    public static let empty = CollapseFingerprint(ids: [], collapsed: [], roots: [])

    public static func capture(_ document: MindMapDocument) -> CollapseFingerprint {
        var ids: [UUID] = []
        var collapsed: [UUID] = []
        document.walkTopics { node in
            ids.append(node.id)
            if node.isCollapsed { collapsed.append(node.id) }
        }
        ids.sort { $0.uuidString < $1.uuidString }
        collapsed.sort { $0.uuidString < $1.uuidString }
        return CollapseFingerprint(ids: ids, collapsed: collapsed, roots: document.roots.map(\.id))
    }

    public static func delta(from previous: CollapseFingerprint, to next: CollapseFingerprint) -> PetalDocumentDelta {
        if previous == next { return .none }
        let previousIDs = Set(previous.ids)
        let nextIDs = Set(next.ids)
        if !previousIDs.isEmpty, !nextIDs.isEmpty, previousIDs.isDisjoint(with: nextIDs) {
            return .mapOpen
        }
        guard previous.ids == next.ids, previous.roots == next.roots else { return .unrelated }
        let before = Set(previous.collapsed)
        let after = Set(next.collapsed)
        let opened = before.subtracting(after)
        let closed = after.subtracting(before)
        if opened.count == 1, closed.isEmpty, let id = opened.first {
            return .expand(id)
        }
        if closed.count == 1, opened.isEmpty, let id = closed.first {
            return .collapse(id)
        }
        return .unrelated
    }
}

public struct PetalPose: Equatable, Sendable {
    public var center: CGPoint
    public var scale: CGFloat
    public var opacity: Double
    public var growth: Double
    /// 1 draws a circle. 0 keeps the node's corner radius.
    public var cornerCircle: Double
    public var origin: CGPoint
    public var draws: Bool
    public var showsText: Bool

    public static func hidden(origin: CGPoint) -> PetalPose {
        PetalPose(
            center: origin,
            scale: CGFloat(PetalExpandTiming.budScale),
            opacity: 0,
            growth: 0,
            cornerCircle: 1,
            origin: origin,
            draws: false,
            showsText: false
        )
    }
}

public enum PetalExpandGeometry {
    /// Pulls the finished curve back toward `origin`. Growth 0 is a point.
    /// Growth 1 is the layout curve. Values above 1 overshoot along the same ray.
    public static func grow(_ link: LinkCurve, from origin: CGPoint, growth: Double) -> LinkCurve {
        let t = growth
        func mix(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: origin.x + (point.x - origin.x) * t,
                y: origin.y + (point.y - origin.y) * t
            )
        }
        return LinkCurve(
            start: mix(link.start),
            control1: mix(link.control1),
            control2: mix(link.control2),
            end: mix(link.end),
            lineWidth: link.lineWidth,
            color: link.color
        )
    }
}

public struct PetalGhost: Equatable, Sendable {
    public var frame: NodeFrame
    public var pose: PetalPose
}

public struct PetalPoseCost: Equatable, Sendable {
    public var nodes: Int
    public var samples: Int
    public var nanoseconds: UInt64
    public var nanosecondsPerFrame: UInt64
    public var easing: String
    public var duration: TimeInterval
    public var layoutPassesDuringPlayback: Int
    /// Sum of sampled growth values. Keeps the timed loop observable.
    public var checksum: Double
}

/// One load or toggle. Samples do not layout.
public struct PetalExpandDirector: Sendable {
    public var reduceMotion: Bool
    public private(set) var isPlaying = false
    public private(set) var kind: PetalMotionKind?
    public private(set) var duration: TimeInterval = 0
    public private(set) var animatedCount = 0
    public private(set) var hiddenCount = 0
    public private(set) var peakConcurrent = 0
    public private(set) var layoutPassCountAtStart = 0
    public private(set) var layoutPassesDuringPlayback = 0

    private var plan: PetalExpandPlan?
    private var startedAt: TimeInterval = 0

    public init(reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
    }

    public var easingName: String { PetalEasing.name }

    public var layoutBudgetExceeded: Bool {
        layoutPassesDuringPlayback > PetalExpandTiming.maxLayoutPassesDuringPlayback
    }

    public mutating func setReduceMotion(_ enabled: Bool) {
        reduceMotion = enabled
        if enabled {
            settle()
        }
    }

    public mutating func settle() {
        isPlaying = false
    }

    /// `layoutPassCount` is the canvas cache's count after the single transition layout.
    public mutating func openMap(frames: [NodeFrame], now: TimeInterval, layoutPassCount: Int) {
        begin(.mapOpen, previousFrames: [], finalFrames: frames, anchor: nil, now: now, layoutPassCount: layoutPassCount)
    }

    public mutating func noteDocumentChange(
        from previous: CollapseFingerprint,
        to next: CollapseFingerprint,
        previousFrames: [NodeFrame],
        finalFrames: [NodeFrame],
        now: TimeInterval,
        layoutPassCount: Int
    ) {
        switch CollapseFingerprint.delta(from: previous, to: next) {
        case .none, .unrelated:
            if isPlaying { settle() }
        case .mapOpen:
            begin(.mapOpen, previousFrames: [], finalFrames: finalFrames, anchor: nil, now: now, layoutPassCount: layoutPassCount)
        case .expand(let id):
            begin(.expand(id), previousFrames: previousFrames, finalFrames: finalFrames, anchor: id, now: now, layoutPassCount: layoutPassCount)
        case .collapse(let id):
            begin(.collapse(id), previousFrames: previousFrames, finalFrames: finalFrames, anchor: id, now: now, layoutPassCount: layoutPassCount)
        }
    }

    public func isActive(at time: TimeInterval) -> Bool {
        guard isPlaying, plan != nil, !reduceMotion else { return false }
        return time < startedAt + duration
    }

    public func playbackDidFinish(at time: TimeInterval) -> Bool {
        guard isPlaying else { return false }
        return reduceMotion || time >= startedAt + duration
    }

    public func layoutExtra(comparedTo layoutPassCount: Int) -> Int {
        guard isPlaying else { return 0 }
        return max(0, layoutPassCount - layoutPassCountAtStart)
    }

    public mutating func noteLayoutExtra(_ extra: Int) {
        layoutPassesDuringPlayback = max(0, extra)
    }

    public func hides(_ id: UUID, at time: TimeInterval) -> Bool {
        guard isActive(at: time), let plan else { return false }
        return plan.hiddenIDs.contains(id)
    }

    public func pose(for id: UUID, at time: TimeInterval) -> PetalPose? {
        guard isActive(at: time), let plan else { return nil }
        if plan.hiddenIDs.contains(id) {
            return PetalPose.hidden(origin: plan.origin)
        }
        guard let participant = plan.participants[id] else { return nil }
        return participant.pose(at: time, startedAt: startedAt, collapsing: plan.collapsing)
    }

    public func ghosts(at time: TimeInterval) -> [PetalGhost] {
        guard isActive(at: time), let plan else { return [] }
        var ghosts: [PetalGhost] = []
        ghosts.reserveCapacity(plan.ghosts.count)
        for participant in plan.ghosts {
            let pose = participant.pose(at: time, startedAt: startedAt, collapsing: true)
            guard pose.draws, let frame = participant.ghostFrame else { continue }
            ghosts.append(PetalGhost(frame: frame, pose: pose))
        }
        return ghosts
    }

    /// Layout rect once the clock is finished or the node is not in this plan.
    /// Hidden tail nodes report a zero rect only while the clock is running.
    public func presentationRect(of frame: NodeFrame, at time: TimeInterval) -> CGRect {
        guard let pose = pose(for: frame.id, at: time) else { return frame.frame }
        guard pose.draws else {
            return CGRect(x: pose.origin.x, y: pose.origin.y, width: 0, height: 0)
        }
        let width = frame.size.width * pose.scale
        let height = frame.size.height * pose.scale
        return CGRect(
            x: pose.center.x - width / 2,
            y: pose.center.y - height / 2,
            width: width,
            height: height
        )
    }

    /// Times pose and curve samples. Does not call `LayoutEngine`.
    public func measurePoseCost(frames: [NodeFrame], samples: Int) -> PetalPoseCost {
        let sampleCount = max(1, samples)
        var checksum = 0.0
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for step in 0..<sampleCount {
                let time = startedAt + duration * Double(step) / Double(sampleCount)
                for frame in frames {
                    guard let pose = pose(for: frame.id, at: time) else { continue }
                    checksum += pose.growth
                    if let link = frame.link {
                        let grown = PetalExpandGeometry.grow(link, from: pose.origin, growth: pose.growth)
                        checksum += grown.end.x
                    }
                }
                checksum += Double(ghosts(at: time).count)
            }
        }
        let nanos = Self.nanoseconds(elapsed)
        return PetalPoseCost(
            nodes: frames.count,
            samples: sampleCount,
            nanoseconds: nanos,
            nanosecondsPerFrame: nanos / UInt64(sampleCount),
            easing: easingName,
            duration: duration,
            layoutPassesDuringPlayback: layoutPassesDuringPlayback,
            checksum: checksum
        )
    }

    private mutating func begin(
        _ kind: PetalMotionKind,
        previousFrames: [NodeFrame],
        finalFrames: [NodeFrame],
        anchor: UUID?,
        now: TimeInterval,
        layoutPassCount: Int
    ) {
        layoutPassCountAtStart = layoutPassCount
        layoutPassesDuringPlayback = 0
        guard !reduceMotion else {
            plan = nil
            self.kind = nil
            duration = 0
            animatedCount = 0
            hiddenCount = 0
            isPlaying = false
            return
        }
        let built = PetalExpandPlan.build(
            kind: kind,
            previousFrames: previousFrames,
            finalFrames: finalFrames,
            anchor: anchor
        )
        guard !built.participants.isEmpty else {
            plan = nil
            self.kind = nil
            duration = 0
            animatedCount = 0
            hiddenCount = built.hiddenIDs.count
            isPlaying = false
            return
        }
        plan = built
        self.kind = kind
        duration = built.duration
        animatedCount = built.participants.count
        hiddenCount = built.hiddenIDs.count
        startedAt = now
        isPlaying = true
        peakConcurrent = max(peakConcurrent, 1)
    }

    private static func nanoseconds(_ duration: Duration) -> UInt64 {
        let parts = duration.components
        let seconds = UInt64(max(0, parts.seconds))
        let attoseconds = parts.attoseconds > 0 ? parts.attoseconds : 0
        return seconds * 1_000_000_000 + UInt64(attoseconds / 1_000_000_000)
    }
}

private struct PetalParticipant: Sendable {
    var id: UUID
    var origin: CGPoint
    var finalCenter: CGPoint
    var delayStep: Int
    var ghostFrame: NodeFrame?

    func pose(at time: TimeInterval, startedAt: TimeInterval, collapsing: Bool) -> PetalPose {
        let elapsed = time - startedAt
        let local = (elapsed - Double(delayStep) * PetalExpandTiming.stepDelay) / PetalExpandTiming.petalDuration
        if local < 0 {
            if collapsing {
                return resting(opacity: 1, showsText: true)
            }
            return PetalPose.hidden(origin: origin)
        }
        let eased = PetalEasing.easeOutBack(min(local, 1))
        let growth = collapsing ? max(0, 1 - eased) : min(PetalExpandTiming.maxGrowth, max(0, eased))
        let bud = PetalExpandTiming.budScale
        let scale = bud + (1 - bud) * min(growth, PetalExpandTiming.maxGrowth)
        let visibleGrowth = min(1, max(0, growth))
        let opacity = min(1, 0.35 + 0.65 * visibleGrowth)
        let draws = collapsing ? growth > 0.04 : true
        return PetalPose(
            center: mix(origin, finalCenter, growth),
            scale: CGFloat(scale),
            opacity: draws ? opacity : 0,
            growth: growth,
            cornerCircle: 1 - visibleGrowth,
            origin: origin,
            draws: draws,
            showsText: draws && growth >= PetalExpandTiming.textGrowth
        )
    }

    private func resting(opacity: Double, showsText: Bool) -> PetalPose {
        PetalPose(
            center: finalCenter,
            scale: 1,
            opacity: opacity,
            growth: 1,
            cornerCircle: 0,
            origin: origin,
            draws: true,
            showsText: showsText
        )
    }

    private func mix(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}

private struct PetalExpandPlan: Sendable {
    var collapsing: Bool
    var duration: TimeInterval
    var origin: CGPoint
    var participants: [UUID: PetalParticipant]
    var ghosts: [PetalParticipant]
    var hiddenIDs: Set<UUID>

    static func build(
        kind: PetalMotionKind,
        previousFrames: [NodeFrame],
        finalFrames: [NodeFrame],
        anchor: UUID?
    ) -> PetalExpandPlan {
        let collapsing: Bool
        if case .collapse = kind { collapsing = true } else { collapsing = false }
        let source = collapsing ? previousFrames : finalFrames
        let centers = centersByID(source)
        let finalCenters = centersByID(finalFrames)
        let anchorCenter = anchor.flatMap { finalCenters[$0] ?? centers[$0] } ?? .zero
        var candidates: [Candidate] = []
        switch kind {
        case .mapOpen:
            for frame in finalFrames {
                let center = center(of: frame)
                let origin = frame.isFree || frame.parentID == nil ? center : (centers[frame.parentID ?? frame.id] ?? center)
                let step = frame.isFree ? 0 : min(PetalExpandTiming.maxStep, frame.depth)
                candidates.append(Candidate(id: frame.id, origin: origin, finalCenter: center, depthStep: step, ghostFrame: nil))
            }
        case .expand(let id):
            let anchorDepth = finalFrames.first { $0.id == id }?.depth ?? 0
            let parents = parentsByID(finalFrames)
            for frame in finalFrames where isDescendant(frame.id, of: id, parents: parents) {
                let center = center(of: frame)
                let origin = frame.parentID.flatMap { finalCenters[$0] } ?? anchorCenter
                let relative = max(0, frame.depth - anchorDepth - 1)
                candidates.append(Candidate(
                    id: frame.id,
                    origin: origin,
                    finalCenter: center,
                    depthStep: min(PetalExpandTiming.maxStep, relative),
                    ghostFrame: nil
                ))
            }
        case .collapse(let id):
            let kept = Set(finalFrames.map(\.id))
            let anchorDepth = previousFrames.first { $0.id == id }?.depth ?? 0
            let parents = parentsByID(previousFrames)
            for frame in previousFrames where !kept.contains(frame.id) && isDescendant(frame.id, of: id, parents: parents) {
                let center = center(of: frame)
                let origin = frame.parentID.flatMap { finalCenters[$0] ?? centers[$0] } ?? anchorCenter
                let relative = max(0, frame.depth - anchorDepth - 1)
                candidates.append(Candidate(
                    id: frame.id,
                    origin: origin,
                    finalCenter: center,
                    depthStep: min(PetalExpandTiming.maxStep, relative),
                    ghostFrame: frame
                ))
            }
        }
        candidates.sort { lhs, rhs in
            if lhs.depthStep != rhs.depthStep { return lhs.depthStep < rhs.depthStep }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        let keptCount = min(PetalExpandTiming.maxAnimated, candidates.count)
        let chosen = Array(candidates.prefix(keptCount))
        let limit = chosen.map(\.depthStep).max() ?? 0
        var participants: [UUID: PetalParticipant] = [:]
        var ghosts: [PetalParticipant] = []
        participants.reserveCapacity(chosen.count)
        for candidate in chosen {
            let delay = collapsing ? limit - candidate.depthStep : candidate.depthStep
            let participant = PetalParticipant(
                id: candidate.id,
                origin: candidate.origin,
                finalCenter: candidate.finalCenter,
                delayStep: delay,
                ghostFrame: candidate.ghostFrame
            )
            participants[candidate.id] = participant
            if candidate.ghostFrame != nil {
                ghosts.append(participant)
            }
        }
        var hidden: Set<UUID> = []
        if candidates.count > keptCount {
            for candidate in candidates.dropFirst(keptCount) where candidate.ghostFrame == nil {
                hidden.insert(candidate.id)
            }
        }
        let maxDelay = chosen.map { collapsing ? limit - $0.depthStep : $0.depthStep }.max() ?? 0
        let duration = chosen.isEmpty
            ? 0
            : Double(maxDelay) * PetalExpandTiming.stepDelay + PetalExpandTiming.petalDuration
        return PetalExpandPlan(
            collapsing: collapsing,
            duration: duration,
            origin: anchorCenter,
            participants: participants,
            ghosts: ghosts,
            hiddenIDs: hidden
        )
    }

    private struct Candidate {
        var id: UUID
        var origin: CGPoint
        var finalCenter: CGPoint
        var depthStep: Int
        var ghostFrame: NodeFrame?
    }

    private static func center(of frame: NodeFrame) -> CGPoint {
        CGPoint(x: frame.frame.midX, y: frame.frame.midY)
    }

    private static func centersByID(_ frames: [NodeFrame]) -> [UUID: CGPoint] {
        var centers: [UUID: CGPoint] = [:]
        centers.reserveCapacity(frames.count)
        for frame in frames {
            centers[frame.id] = center(of: frame)
        }
        return centers
    }

    private static func parentsByID(_ frames: [NodeFrame]) -> [UUID: UUID] {
        var parents: [UUID: UUID] = [:]
        for frame in frames {
            if let parentID = frame.parentID {
                parents[frame.id] = parentID
            }
        }
        return parents
    }

    private static func isDescendant(_ id: UUID, of ancestor: UUID, parents: [UUID: UUID]) -> Bool {
        var current = parents[id]
        var steps = 0
        while let cursor = current, steps < 64 {
            if cursor == ancestor { return true }
            current = parents[cursor]
            steps += 1
        }
        return false
    }
}
