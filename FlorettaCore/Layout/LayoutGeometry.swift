import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Which edge of the parent a link leaves from. It fixes the cubic's start,
/// end, and control points, so every structure shares one curve builder.
public enum LinkAnchor: Equatable, Sendable {
    case left
    case right
    case down
}

/// Measurement and frame factory shared by every structure layout.
///
/// A `StructureLayout` decides *where* a topic goes. This type answers *how big*
/// a topic is and *what it looks like*: font resolution, attachment bands, fill
/// and border colors, and the `NodeFrame` that the canvas, hit testing, and the
/// PNG/PDF exporter all read. No layout may size a node by a second formula.
public struct LayoutGeometry: Sendable {
    public var cache: TextMeasurementCache
    public var metrics: LayoutMetrics
    public var appearance: LayoutAppearance
    /// Multiplier from the current appearance profile. 1 keeps theme sizes.
    public var fontSizeScale: CGFloat
    /// Painted family id (`eb-garamond`, `system-serif`, …). Empty keeps the
    /// historical Helvetica → system UI measurement path.
    public var fontFamilyID: String

    public init(
        cache: TextMeasurementCache,
        metrics: LayoutMetrics,
        appearance: LayoutAppearance,
        fontSizeScale: CGFloat = 1,
        fontFamilyID: String = ""
    ) {
        self.cache = cache
        self.metrics = metrics
        self.appearance = appearance
        self.fontSizeScale = fontSizeScale
        self.fontFamilyID = fontFamilyID
    }

    public func fontSize(depth: Int) -> CGFloat {
        metrics.fontSize(depth: depth) * max(fontSizeScale, 0.01)
    }

    /// Text the box must fit. Attachments add their own lines.
    public func measuredText(_ node: MindMapNode) -> String {
        NodeAttachmentDrawing.measuredText(node)
    }

    /// Same family + design the canvas will paint, so measured width matches glyphs.
    public func typography(for node: MindMapNode, depth: Int) -> (familyID: String, nodeDesign: String) {
        let design = node.style?.fontDesign
            ?? (depth == 0 ? appearance.rootFontDesign : appearance.bodyFontDesign)
        return (fontFamilyID, design)
    }

    public func resolvedFontSize(_ node: MindMapNode, depth: Int) -> CGFloat {
        let base: CGFloat
        if let size = node.style?.fontSize, size > 0 {
            base = CGFloat(size)
        } else {
            base = metrics.fontSize(depth: depth)
        }
        return base * max(fontSizeScale, 0.01)
    }

    public func subtitleSize(
        _ node: MindMapNode,
        fontSize: CGFloat,
        face: (familyID: String, nodeDesign: String)
    ) -> CGSize {
        guard !node.subtitle.isEmpty else { return .zero }
        return cache.size(
            text: node.subtitle,
            fontSize: max(1, fontSize * 0.72),
            maxWidth: metrics.maxTextWidth,
            fontFamilyID: face.familyID,
            nodeDesign: face.nodeDesign
        )
    }

    public func thumbnailBand(_ node: MindMapNode) -> CGFloat {
        let hasImage = node.attachments.contains { AttachmentKind.isImageExtension($0.fileExtension) }
        return CGFloat(ImageSlot.bandHeight(hasImage: hasImage))
    }

    /// Tallest measured topic at each depth. Level peers share a height, so a
    /// row of siblings lines up even when one title is longer.
    /// Manual positions and collapsed topics do not contribute their subtrees.
    public func collectHeights(_ node: MindMapNode, depth: Int, into heights: inout [Int: CGFloat]) {
        let face = typography(for: node, depth: depth)
        let raw = cache.size(
            text: measuredText(node),
            fontSize: resolvedFontSize(node, depth: depth),
            maxWidth: metrics.maxTextWidth,
            fontFamilyID: face.familyID,
            nodeDesign: face.nodeDesign
        )
        heights[depth] = max(
            heights[depth] ?? 0,
            raw.height + subtitleSize(node, fontSize: resolvedFontSize(node, depth: depth), face: face).height
        )
        if node.position != nil || node.isCollapsed { return }
        for child in node.children {
            collectHeights(child, depth: depth + 1, into: &heights)
        }
    }

    public func size(
        _ node: MindMapNode,
        depth: Int,
        heights: [Int: CGFloat],
        reservesChildBadge: Bool = false
    ) -> CGSize {
        let font = resolvedFontSize(node, depth: depth)
        let face = typography(for: node, depth: depth)
        let raw = cache.size(
            text: measuredText(node),
            fontSize: font,
            maxWidth: metrics.maxTextWidth,
            fontFamilyID: face.familyID,
            nodeDesign: face.nodeDesign
        )
        let band = thumbnailBand(node)
        let files = FileBadgeLayout.fileAttachments(in: node)
        let fileBand = CGFloat(FileBadgeMetrics.bandHeight(count: files.count))
        let tagBand = CGFloat(TopicTagLayout.bandHeight(
            labelCount: node.labels.count,
            markerCount: node.markers.count
        ))
        let imageWidth = band > 0 ? CGFloat(ImageSlot.maxWidth + ImageSlot.horizontalInset * 2) : 0
        var fileWidth: CGFloat = 0
        if !files.isEmpty {
            let label = files
                .map { "\($0.filename) \(AttachmentByteFormat.label($0.byteCount))" }
                .joined(separator: "\n")
            let measured = cache.size(
                text: label,
                fontSize: font,
                maxWidth: metrics.maxTextWidth,
                fontFamilyID: face.familyID,
                nodeDesign: face.nodeDesign
            )
            fileWidth = measured.width
                + CGFloat(FileBadgeMetrics.iconSide + FileBadgeMetrics.gap + FileBadgeMetrics.horizontalInset * 2)
        }
        let subtitle = subtitleSize(node, fontSize: font, face: face)
        // 「适应」 measures the text; a stored px width only applies while the topic is fixed.
        let storedWidth: CGFloat = node.style?.autoWidth == true ? 0 : CGFloat(node.style?.topicWidth ?? 0)
        let width = max(raw.width, subtitle.width, storedWidth, imageWidth, fileWidth)
        let badge: CGFloat = reservesChildBadge ? appearance.childCountBadgeInset : 0
        return CGSize(
            width: width + badge,
            height: (heights[depth] ?? raw.height + subtitle.height) + band + fileBand + tagBand
        )
    }

    public func frame(
        node: MindMapNode,
        origin: CGPoint,
        size: CGSize,
        depth: Int,
        isRoot: Bool,
        parentID: UUID?,
        branch: BranchColor,
        link: LinkCurve?,
        isFree: Bool = false,
        childBadgeInset: CGFloat = 0,
        childBadgeOnMinX: Bool = false
    ) -> NodeFrame {
        let palette = themeColors(depth: depth, branch: branch)
        let stored = node.style
        let fill = stored?.fillHex.flatMap(BranchColor.init(hex:)) ?? palette.fill
        let border = stored?.borderHex.flatMap(BranchColor.init(hex:)) ?? palette.border
        let text = stored?.textHex.flatMap(BranchColor.init(hex:)) ?? palette.text
        return NodeFrame(
            id: node.id,
            text: node.text,
            origin: origin,
            size: size,
            depth: depth,
            fontSize: resolvedFontSize(node, depth: depth),
            isRoot: isRoot,
            parentID: parentID,
            fill: fill,
            border: border,
            textColor: text,
            cornerRadius: CGFloat(stored?.cornerRadius ?? Double(appearance.cornerRadius)),
            borderWidth: CGFloat(
                stored?.borderWidth
                    ?? Double(appearance.uniformStrokeWidth ?? appearance.linkStroke ?? 1.5)
            ),
            hidesFill: stored?.fillStyle == "none",
            bold: stored?.bold ?? false,
            italic: stored?.italic ?? false,
            strikethrough: stored?.strikethrough ?? false,
            underline: stored?.underline ?? false,
            fontDesign: stored?.fontDesign ?? (isRoot ? appearance.rootFontDesign : appearance.bodyFontDesign),
            link: link,
            caption: node.attachmentSizeLabel ?? "",
            isFree: isFree,
            thumbnailHashes: node.attachments.compactMap { attachment in
                AttachmentKind.isImageExtension(attachment.fileExtension)
                    || NodeMediaKind.classify(filename: attachment.filename) == .video
                    ? attachment.sha256 : nil
            },
            audioWaveformHashes: node.attachments.compactMap { attachment in
                NodeMediaKind.classify(filename: attachment.filename) == .audio ? attachment.sha256 : nil
            },
            fileBadges: FileBadgeLayout.badges(
                attachments: node.attachments,
                nodeWidth: Double(size.width),
                nodeHeight: Double(size.height)
            ),
            labels: node.labels,
            markerIDs: node.markers.map(\.markerId),
            tagBandHeight: CGFloat(TopicTagLayout.bandHeight(
                labelCount: node.labels.count,
                markerCount: node.markers.count
            )),
            childBadgeInset: childBadgeInset,
            childBadgeOnMinX: childBadgeOnMinX,
            textAlignment: node.textAlignment,
            subtitle: node.subtitle,
            subtitleFontSize: resolvedFontSize(node, depth: depth) * 0.72,
            subtitleHeight: subtitleSize(
                node,
                fontSize: resolvedFontSize(node, depth: depth),
                face: typography(for: node, depth: depth)
            ).height
        )
    }

    /// A free node keeps its stored point and has no hierarchy link.
    /// It is not measured into the level heights of any structure.
    public func appendFree(_ node: MindMapNode, into frames: inout [NodeFrame]) {
        let font = resolvedFontSize(node, depth: 1)
        let face = typography(for: node, depth: 1)
        let raw = cache.size(
            text: measuredText(node),
            fontSize: font,
            maxWidth: metrics.maxTextWidth,
            fontFamilyID: face.familyID,
            nodeDesign: face.nodeDesign
        )
        let size = size(
            node,
            depth: 1,
            heights: [1: raw.height + subtitleSize(node, fontSize: font, face: face).height],
            reservesChildBadge: false
        )
        let origin = CGPoint(x: node.position?.x ?? 0, y: node.position?.y ?? 0)
        frames.append(
            frame(
                node: node,
                origin: origin,
                size: size,
                depth: 1,
                isRoot: false,
                parentID: nil,
                branch: appearance.palette.color(at: 0),
                link: nil,
                isFree: true
            )
        )
    }

    public func themeColors(
        depth: Int,
        branch: BranchColor
    ) -> (fill: BranchColor, border: BranchColor, text: BranchColor) {
        let text: BranchColor
        if depth == 0 {
            text = appearance.centerText
        } else if depth == 1 {
            text = appearance.level1Text
        } else {
            text = appearance.deeperText
        }
        if appearance.uniformFill == nil, appearance.uniformStroke == nil {
            if depth == 0 {
                return (appearance.centerFill, appearance.centerBorder, text)
            }
            if depth == 1 {
                return (branch, branch, text)
            }
            return (branch.lightened(by: appearance.deeperFillMix), branch, text)
        }
        let fill: BranchColor
        if let uniform = appearance.uniformFill {
            fill = uniform
        } else if depth == 0 {
            fill = appearance.centerFill
        } else if depth == 1 {
            fill = branch
        } else {
            fill = branch.lightened(by: appearance.deeperFillMix)
        }
        let border: BranchColor
        if let uniform = appearance.uniformStroke {
            border = uniform
        } else if depth == 0 {
            border = appearance.centerBorder
        } else {
            border = branch
        }
        return (fill, border, text)
    }

    /// Hierarchy link between a placed parent and a placed child.
    /// `anchor` names the parent edge the curve leaves from.
    public func link(
        from parent: CGRect,
        to child: CGRect,
        anchor: LinkAnchor,
        depth: Int,
        color: BranchColor
    ) -> LinkCurve {
        let start: CGPoint
        let end: CGPoint
        let control1: CGPoint
        let control2: CGPoint
        switch anchor {
        case .right, .left:
            start = CGPoint(x: anchor == .right ? parent.maxX : parent.minX, y: parent.midY)
            end = CGPoint(x: anchor == .right ? child.minX : child.maxX, y: child.midY)
            let dx = end.x - start.x
            control1 = CGPoint(x: start.x + dx * 0.5, y: start.y)
            control2 = CGPoint(x: end.x - dx * 0.5, y: end.y)
        case .down:
            start = CGPoint(x: parent.midX, y: parent.maxY)
            end = CGPoint(x: child.midX, y: child.minY)
            let dy = end.y - start.y
            control1 = CGPoint(x: start.x, y: start.y + dy * 0.5)
            control2 = CGPoint(x: end.x, y: end.y - dy * 0.5)
        }
        let startWidth = appearance.edgeStartWidth ?? appearance.linkStroke ?? metrics.linkWidth(depth: depth)
        let endWidth = appearance.edgeEndWidth ?? startWidth
        return LinkCurve(
            start: start,
            control1: control1,
            control2: control2,
            end: end,
            lineWidth: startWidth,
            endWidth: endWidth,
            color: appearance.edgeColor ?? color
        )
    }

    public func childIndex(of child: MindMapNode, in parent: MindMapNode) -> Int {
        parent.children.firstIndex(where: { $0.id == child.id }) ?? 0
    }
}
