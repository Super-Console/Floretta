import Foundation

/// Five paper colors. A sixth case would be a new color, which this batch does not allow.
public enum StickyColor: String, Codable, CaseIterable, Equatable, Sendable {
    case yellow
    case pink
    case green
    case blue
    case orange

    public static let palette: [StickyColor] = [.yellow, .pink, .green, .blue, .orange]

    public var fill: BranchColor {
        switch self {
        case .yellow: return BranchColor(red: 0.965, green: 0.906, blue: 0.631)
        case .pink: return BranchColor(red: 0.965, green: 0.788, blue: 0.831)
        case .green: return BranchColor(red: 0.804, green: 0.910, blue: 0.769)
        case .blue: return BranchColor(red: 0.788, green: 0.867, blue: 0.965)
        case .orange: return BranchColor(red: 0.973, green: 0.827, blue: 0.690)
        }
    }

    public var ink: BranchColor {
        switch self {
        case .yellow: return BranchColor(red: 0.247, green: 0.204, blue: 0.125)
        case .pink: return BranchColor(red: 0.290, green: 0.141, blue: 0.188)
        case .green: return BranchColor(red: 0.118, green: 0.227, blue: 0.141)
        case .blue: return BranchColor(red: 0.110, green: 0.180, blue: 0.290)
        case .orange: return BranchColor(red: 0.290, green: 0.180, blue: 0.078)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let color = StickyColor(rawValue: raw), Self.palette.contains(color) else {
            throw FlorettaCodecError.corrupt(
                "Unknown sticky color \"\(raw)\". Stickies use yellow, pink, green, blue, or orange."
            )
        }
        self = color
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Width and height caps. A sticky is a card, not a page the user can stretch across the map.
public enum StickyLimits {
    public static let minWidth = 120.0
    public static let minHeight = 88.0
    public static let maxWidth = 320.0
    public static let maxHeight = 240.0
    public static let defaultWidth = 176.0
    public static let defaultHeight = 132.0
    /// Bottom-right square, in canvas points, that resizes instead of moving.
    public static let resizeHandle = 22.0

    public static func clampWidth(_ width: Double) -> Double {
        guard width.isFinite else { return defaultWidth }
        return min(max(width, minWidth), maxWidth)
    }

    public static func clampHeight(_ height: Double) -> Double {
        guard height.isFinite else { return defaultHeight }
        return min(max(height, minHeight), maxHeight)
    }
}

/// A canvas card. It is not a topic: no parent, no children, no place in `roots` or `freeNodes`.
public struct StickyNote: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var text: String
    public var color: StickyColor
    public var origin: MindMapPoint
    public var width: Double {
        didSet {
            let clamped = StickyLimits.clampWidth(width)
            if clamped != width { width = clamped }
        }
    }
    public var height: Double {
        didSet {
            let clamped = StickyLimits.clampHeight(height)
            if clamped != height { height = clamped }
        }
    }

    public init(
        id: UUID = UUID(),
        text: String = "便签",
        color: StickyColor = .yellow,
        origin: MindMapPoint,
        width: Double = StickyLimits.defaultWidth,
        height: Double = StickyLimits.defaultHeight
    ) {
        self.id = id
        self.text = text
        self.color = color
        if origin.x.isFinite, origin.y.isFinite {
            self.origin = origin
        } else {
            self.origin = MindMapPoint(
                x: origin.x.isFinite ? origin.x : 0,
                y: origin.y.isFinite ? origin.y : 0
            )
        }
        self.width = StickyLimits.clampWidth(width)
        self.height = StickyLimits.clampHeight(height)
    }

    public func contains(x: Double, y: Double) -> Bool {
        guard x.isFinite, y.isFinite else { return false }
        return x >= origin.x && y >= origin.y && x <= origin.x + width && y <= origin.y + height
    }

    public func hitsResizeHandle(x: Double, y: Double) -> Bool {
        guard contains(x: x, y: y) else { return false }
        return x >= origin.x + width - StickyLimits.resizeHandle
            && y >= origin.y + height - StickyLimits.resizeHandle
    }
}

extension StickyNote: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case text
        case color
        case origin
        case width
        case height
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let text = try container.decode(String.self, forKey: .text)
        let color = try container.decode(StickyColor.self, forKey: .color)
        let origin = try container.decode(MindMapPoint.self, forKey: .origin)
        guard origin.x.isFinite, origin.y.isFinite else {
            throw FlorettaCodecError.corrupt("Sticky \(id.uuidString) has a non-finite origin.")
        }
        let width = try container.decode(Double.self, forKey: .width)
        let height = try container.decode(Double.self, forKey: .height)
        self.init(id: id, text: text, color: color, origin: origin, width: width, height: height)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(color, forKey: .color)
        try container.encode(origin, forKey: .origin)
        try container.encode(StickyLimits.clampWidth(width), forKey: .width)
        try container.encode(StickyLimits.clampHeight(height), forKey: .height)
    }
}

/// Which part of a sticky the pointer is on. Later notes are painted above earlier ones.
public enum StickyHit: Equatable, Sendable {
    case body(UUID)
    case resize(UUID)
}

public enum StickyGeometry {
    public static func hit(x: Double, y: Double, in stickies: [StickyNote]) -> StickyHit? {
        for sticky in stickies.reversed() {
            if sticky.hitsResizeHandle(x: x, y: y) { return .resize(sticky.id) }
            if sticky.contains(x: x, y: y) { return .body(sticky.id) }
        }
        return nil
    }
}
