import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// One structure of the map. A layout reads the tree and returns placed frames.
///
/// The seam exists so a new XMind structure (矩阵图, 鱼骨图, 时间轴 …) is one new
/// file plus one registry line. A layout may not measure a node by its own
/// formula: sizes, colors, and links all come from `LayoutGeometry`, which is what
/// the canvas and the PNG/PDF exporter both read.
public protocol StructureLayout: Sendable {
    var kind: LayoutKind { get }
    /// Sizing, colors, and the link builder. Set once when the layout is made.
    var geometry: LayoutGeometry { get }
    init(geometry: LayoutGeometry)
    /// Place every topic of the document, free nodes included.
    func place(_ document: MindMapDocument) -> [NodeFrame]
}
