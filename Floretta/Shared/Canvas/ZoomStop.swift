import CoreGraphics
import Foundation

/// Interactive zoom stops. 100% is scale 1: one logical point is one render point.
enum ZoomStop: Int, CaseIterable, Equatable, Sendable {
    case fifty = 50
    case seventyFive = 75
    case oneHundred = 100
    case oneTwentyFive = 125
    case oneFifty = 150
    case twoHundred = 200
    case threeHundred = 300
    case fourHundred = 400

    var percent: Int { rawValue }

    /// Scale passed straight to the viewport. No extra coefficient.
    var scale: CGFloat { CGFloat(percent) / 100 }

    static var legalPercents: [Int] { allCases.map(\.percent) }

    /// Nearest legal stop. Equal distance keeps the lower stop.
    /// Non-finite input snaps to 100%.
    static func nearest(to scale: CGFloat) -> ZoomStop {
        guard scale.isFinite else { return .oneHundred }
        var best = ZoomStop.allCases[0]
        var bestDistance = abs(best.scale - scale)
        for stop in ZoomStop.allCases.dropFirst() {
            let distance = abs(stop.scale - scale)
            if distance < bestDistance {
                best = stop
                bestDistance = distance
            }
        }
        return best
    }

    static func displayPercent(forScale scale: CGFloat) -> Int {
        nearest(to: scale).percent
    }

    func stepped(_ direction: Int) -> ZoomStop {
        let stops = Self.allCases
        guard let index = stops.firstIndex(of: self) else { return self }
        let next = index + direction
        if next <= 0 { return stops[0] }
        if next >= stops.count { return stops[stops.count - 1] }
        return stops[next]
    }
}
