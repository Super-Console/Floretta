import CoreGraphics

/// How every parent→child link is drawn. One token for the whole map: a branch line
/// belongs to the branch, so the inspector writes it on the document, not on a topic.
public enum BranchLineStyle: String, CaseIterable, Identifiable, Sendable {
    case curve
    case straight

    public var id: String { rawValue }

    public var titleKey: String {
        self == .curve ? "曲线" : "直线"
    }
}

/// Shape drawn where a branch meets its child. `none` draws nothing.
public enum BranchEndMarker: String, CaseIterable, Identifiable, Sendable {
    case none
    case arrow
    case dot

    public var id: String { rawValue }

    public var titleKey: String {
        switch self {
        case .none: "无"
        case .arrow: "箭头"
        case .dot: "圆点"
        }
    }
}

/// Stored tokens plus the geometry the canvas and the PNG/PDF export share.
/// `curve` and `none` are the defaults and are not written, so an untouched map
/// keeps the JSON it had before this option existed.
public enum BranchStyle {
    public static func line(_ token: String?) -> BranchLineStyle {
        guard let token, let parsed = BranchLineStyle(rawValue: token) else { return .curve }
        return parsed
    }

    public static func endMarker(_ token: String?) -> BranchEndMarker {
        guard let token, let parsed = BranchEndMarker(rawValue: token) else { return .none }
        return parsed
    }

    public static func persistedLine(_ style: BranchLineStyle) -> String? {
        style == .curve ? nil : style.rawValue
    }

    public static func persistedEndMarker(_ marker: BranchEndMarker) -> String? {
        marker == .none ? nil : marker.rawValue
    }

    /// Same triangle a relationship arrow uses, so both read as one drawing language.
    public static let arrowLength: CGFloat = 9

    /// Radius of the dot. Never thinner than the line it caps.
    public static func dotRadius(lineWidth: CGFloat) -> CGFloat {
        max(2, lineWidth * 1.6)
    }

    /// Left and right base corners of the arrow whose tip sits on the child.
    public static func arrow(tip: CGPoint, from: CGPoint) -> (left: CGPoint, right: CGPoint) {
        RelationshipGeometry.arrow(tip: tip, from: from, length: arrowLength)
    }
}
