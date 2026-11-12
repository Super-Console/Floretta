import AppKit
import CoreText
import Foundation
import SwiftUI

// Mirrors Floretta's current CoreTextFontMetrics (no paragraph style).
func currentMetrics(text: String, fontName: String, fontSize: CGFloat, maxWidth: CGFloat?) -> (CGSize, CTFont) {
    let safeSize = max(fontSize, 1)
    let font = CTFontCreateWithName(fontName as CFString, safeSize, nil)
    let mutable = CFAttributedStringCreateMutable(kCFAllocatorDefault, 0)!
    let sample = text.isEmpty ? " " : text
    CFAttributedStringReplaceString(mutable, CFRange(location: 0, length: 0), sample as CFString)
    let range = CFRange(location: 0, length: CFAttributedStringGetLength(mutable))
    CFAttributedStringSetAttribute(mutable, range, kCTFontAttributeName, font)
    let framesetter = CTFramesetterCreateWithAttributedString(mutable)
    var fit = CFRange()
    let safeWidth = max(maxWidth ?? .greatestFiniteMagnitude, 1)
    let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
        framesetter, range, nil,
        CGSize(width: safeWidth, height: CGFloat.greatestFiniteMagnitude),
        &fit
    )
    return (suggested, font)
}

func systemFont(size: CGFloat, design: NSFontDescriptor.SystemDesign? = nil) -> CTFont {
    let base = NSFont.systemFont(ofSize: size)
    if let design, let descriptor = base.fontDescriptor.withDesign(design),
       let font = NSFont(descriptor: descriptor, size: size) {
        return font
    }
    return base
}

enum StyleKind: String {
    case currentHelveticaNoStyle
    case systemNoStyle
    case systemStandardStrategy
    case systemStandardCharWrap
}

func attributed(_ text: String, font: CTFont, kind: StyleKind) -> NSAttributedString {
    let attrs = NSMutableAttributedString(string: text, attributes: [
        .font: font
    ])
    guard kind != .currentHelveticaNoStyle && kind != .systemNoStyle else { return attrs }
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    style.lineBreakMode = (kind == .systemStandardCharWrap) ? .byCharWrapping : .byWordWrapping
    if #available(macOS 11.0, *) {
        style.lineBreakStrategy = .standard
    }
    attrs.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: attrs.length))
    return attrs
}

func lines(of text: String, font: CTFont, width: CGFloat, kind: StyleKind) -> (size: CGSize, lines: [String], firstChars: [String], lastChars: [String]) {
    let attr = attributed(text, font: font, kind: kind)
    let framesetter = CTFramesetterCreateWithAttributedString(attr)
    let range = CFRange(location: 0, length: attr.length)
    var fit = CFRange()
    let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
        framesetter, range, nil,
        CGSize(width: width, height: .greatestFiniteMagnitude),
        &fit
    )
    let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: max(suggested.height + 8, 8)), transform: nil)
    let frame = CTFramesetterCreateFrame(framesetter, range, path, nil)
    let ctLines = CTFrameGetLines(frame) as! [CTLine]
    var result: [String] = []
    var firsts: [String] = []
    var lasts: [String] = []
    let ns = text as NSString
    for line in ctLines {
        let r = CTLineGetStringRange(line)
        let sub = ns.substring(with: NSRange(location: r.location, length: r.length))
            .replacingOccurrences(of: "\n", with: "⏎")
        result.append(sub)
        if let f = sub.first { firsts.append(String(f)) } else { firsts.append("") }
        let trimmed = sub.replacingOccurrences(of: "⏎", with: "")
        if let l = trimmed.last { lasts.append(String(l)) } else { lasts.append("") }
    }
    return (suggested, result, firsts, lasts)
}

/// Characters that should not start a line (简体中文避头).
let noLineStart: Set<Character> = ["，", "。", "、", "！", "？", "；", "：", "）", "」", "』", "》", "】", "…", "”", "’", ",", ".", "!", "?", ")", "]", "}"]
/// Characters that should not end a line (避尾).
let noLineEnd: Set<Character> = ["（", "「", "『", "《", "【", "“", "‘", "(", "[", "{"]

func kinsokuViolations(_ lines: [String]) -> [String] {
    var issues: [String] = []
    for (i, line) in lines.enumerated() {
        let visible = line.replacingOccurrences(of: "⏎", with: "")
        if let f = visible.first, noLineStart.contains(f) {
            issues.append("line \(i+1) starts with forbidden \(f)")
        }
        if let l = visible.last, noLineEnd.contains(l) {
            issues.append("line \(i+1) ends with forbidden \(l)")
        }
    }
    return issues
}

func cacheSize(raw: CGSize, maxWidth: CGFloat) -> CGSize {
    // TextMeasurementCache.measure
    let safeWidth = max(maxWidth, 1)
    let width = min(safeWidth + 24, max(72, ceil(raw.width) + 24))
    let height = max(32, ceil(raw.height) + 16)
    return CGSize(width: width, height: height)
}

struct ProbeCanvas: View {
    var text: String
    var fontSize: CGFloat
    var nodeSize: CGSize
    var mode: Mode
    enum Mode { case currentAtCenter, proposedInRect }

    var body: some View {
        Canvas { context, _ in
            let rect = CGRect(origin: .zero, size: nodeSize)
            let path = Path(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerRadius: 8)
            context.fill(path, with: .color(Color(red: 0.15, green: 0.42, blue: 0.85)))
            var textRect = rect.insetBy(dx: 6, dy: 4)
            let styled = Text(text)
                .font(.system(size: fontSize))
                .foregroundStyle(.white)
            var layer = context
            layer.clip(to: Path(textRect))
            switch mode {
            case .currentAtCenter:
                layer.draw(styled, at: CGPoint(x: textRect.midX, y: textRect.midY), anchor: .center)
            case .proposedInRect:
                layer.draw(styled, in: textRect)
            }
        }
        .frame(width: nodeSize.width, height: nodeSize.height)
    }
}

struct LabeledShot: View {
    var title: String
    var text: String
    var fontSize: CGFloat
    var nodeSize: CGSize
    var mode: ProbeCanvas.Mode

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            ProbeCanvas(text: text, fontSize: fontSize, nodeSize: nodeSize, mode: mode)
                .background(
                    ImagePaintPattern()
                )
                .border(Color.black.opacity(0.25), width: 1)
        }
        .padding(8)
        .background(Color.white)
    }
}

struct ImagePaintPattern: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.94)))
            var x: CGFloat = 4
            while x < size.width {
                var y: CGFloat = 4
                while y < size.height {
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.2, height: 1.2)), with: .color(Color(white: 0.75)))
                    y += 8
                }
                x += 8
            }
        }
    }
}

@MainActor
func renderPNG(_ view: some View, to url: URL, size: CGSize) {
    let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
    renderer.scale = 2
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        fputs("failed to render \(url.path)\n", stderr)
        return
    }
    try! png.write(to: url)
}

@main
struct LineBreakProbe {
    static func main() {
        let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var log = ""
        func say(_ s: String) {
            print(s)
            log += s + "\n"
        }
        say("LineBreakProbe \(Date()) CST machine local")
        say("")

        let poem = "春眠不觉晓处处闻啼鸟夜来风雨声花落知多少"
        let zh40t = String(repeating: poem, count: 2) // 40
        let zh80t = String(repeating: poem, count: 4) // 80
        let zh120t = String(repeating: poem, count: 6) // 120
        let en80 = "The quick brown fox jumps over the lazy dog again and again while rain falls softly over the quiet hill."
        let longWord = "supercalifragilisticexpialidocious"
        // Construct CJK with punctuation near likely wrap points.
        let kinsoku = "学习时我们总是说，坚持下去就会成功。可是（有时候）事情并没有那么简单，对吗？"
        let kinsoku2 = "这句话专门用来把句号和逗号顶到行首看看，。以及把左括号留在行尾（然后继续写足够长的正文让它折行。"
        let manual = "第一行手动换行\n第二行还在"

        let maxWidth: CGFloat = 240
        let fontSize: CGFloat = 20 // level-1 topic
        let cases: [(String, String)] = [
            ("A-zh40", zh40t),
            ("A-zh80", zh80t),
            ("A-zh120", zh120t),
            ("A-en80", en80),
            ("B-manual", manual),
            ("C-kinsoku", kinsoku),
            ("C-kinsoku2", kinsoku2),
            ("D-longword", longWord),
            ("D-longword-in-sentence", "The word is \(longWord) indeed."),
        ]

        let kinds: [StyleKind] = [.currentHelveticaNoStyle, .systemNoStyle, .systemStandardStrategy, .systemStandardCharWrap]

        for (name, text) in cases {
            say("======= \(name) =======")
            say("text(\(text.count) chars): \(text.debugDescription)")
            for kind in kinds {
                let font: CTFont
                if kind == .currentHelveticaNoStyle {
                    font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
                } else {
                    font = systemFont(size: fontSize)
                }
                let result = lines(of: text, font: font, width: maxWidth, kind: kind)
                let node = cacheSize(raw: result.size, maxWidth: maxWidth)
                let overflows = result.size.width > maxWidth + 0.5
                let violations = kinsokuViolations(result.lines)
                say("  [\(kind.rawValue)] measured=\(fmt(result.size)) cacheNode=\(fmt(node)) overflow=\(overflows) lines=\(result.lines.count)")
                for (i, line) in result.lines.enumerated() {
                    say("    L\(i+1) first=\(result.firstChars[i]) last=\(result.lastChars[i]) |\(line)|")
                }
                if !violations.isEmpty {
                    say("    KINSKU ISSUES: \(violations.joined(separator: "; "))")
                } else if name.hasPrefix("C-") {
                    say("    kinsoku: no violations at width \(maxWidth)")
                }
            }
            say("")
        }

        // Zoom consistency: same text, width*scale and font*scale
        say("======= E-zoom reflow (system + standard strategy) =======")
        let zoomText = zh80t
        var zoomLineCounts: [CGFloat: Int] = [:]
        var zoomLines: [CGFloat: [String]] = [:]
        for scale in [0.5, 1.0, 2.0] as [CGFloat] {
            let font = systemFont(size: fontSize * scale)
            let result = lines(of: zoomText, font: font, width: maxWidth * scale, kind: .systemStandardStrategy)
            zoomLineCounts[scale] = result.lines.count
            zoomLines[scale] = result.lines
            say("  scale=\(scale) font=\(fontSize * scale) width=\(maxWidth * scale) size=\(fmt(result.size)) lines=\(result.lines.count)")
            for (i, line) in result.lines.enumerated() { say("    L\(i+1) |\(line)|") }
        }
        let counts = Set(zoomLineCounts.values)
        say("  line-count consistent across 50/100/200%: \(counts.count == 1) counts=\(zoomLineCounts)")
        // Compare actual break positions (strip scale by comparing string content)
        if let a = zoomLines[0.5], let b = zoomLines[1.0], let c = zoomLines[2.0] {
            say("  50% vs 100% same breaks: \(a == b)")
            say("  100% vs 200% same breaks: \(b == c)")
        }
        say("")

        // LOD note
        say("======= E-LOD (on-screen point size < 9 hides title) =======")
        for (depth, size) in [("root", 30), ("level1", 20), ("level2", 18), ("deeper", 16)] as [(String, CGFloat)] {
            for scale in [0.5, 1.0, 2.0] as [CGFloat] {
                let onScreen = size * scale
                let lod = onScreen < 9 ? "blocks (title hidden)" : (onScreen < 14 ? "title" : "full")
                say("  \(depth) font=\(size) scale=\(scale) onScreen=\(onScreen) lod=\(lod)")
            }
        }
        say("")

        // Edit vs non-edit typography: TextKit vs CoreText height
        say("======= G-edit vs measure height =======")
        let samples = [("zh80", zh80t), ("manual", manual), ("longword", longWord), ("en80", en80)]
        for (name, text) in samples {
            let helvetica = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
            let system = systemFont(size: fontSize)
            let current = lines(of: text, font: helvetica, width: maxWidth, kind: .currentHelveticaNoStyle)
            let proposed = lines(of: text, font: system, width: maxWidth, kind: .systemStandardStrategy)
            let nodeCurrent = cacheSize(raw: current.size, maxWidth: maxWidth)
            let nodeProposed = cacheSize(raw: proposed.size, maxWidth: maxWidth)

            // TextKit used by the editor (system font, center, inset 6, width = node width - 12)
            func textKitHeight(text: String, font: NSFont, boxWidth: CGFloat) -> CGFloat {
                let storage = NSTextStorage(string: text, attributes: [
                    .font: font,
                    .paragraphStyle: {
                        let s = NSMutableParagraphStyle()
                        s.alignment = .center
                        s.lineBreakMode = .byWordWrapping
                        if #available(macOS 11.0, *) { s.lineBreakStrategy = .standard }
                        return s
                    }()
                ])
                let manager = NSLayoutManager()
                let container = NSTextContainer(size: CGSize(width: max(1, boxWidth - 12), height: 10_000))
                container.lineFragmentPadding = 0
                manager.addTextContainer(container)
                storage.addLayoutManager(manager)
                manager.glyphRange(for: container)
                return manager.usedRect(for: container).height
            }
            let tkCurrentBox = textKitHeight(text: text, font: NSFont.systemFont(ofSize: fontSize), boxWidth: nodeCurrent.width)
            let tkProposedBox = textKitHeight(text: text, font: NSFont.systemFont(ofSize: fontSize), boxWidth: nodeProposed.width)
            say("  \(name): currentHelvetica measureH=\(fmt(current.size.height)) nodeH=\(fmt(nodeCurrent.height)) textKitInThatNode=\(fmt(tkCurrentBox)) delta(node-tk)=\(fmt(nodeCurrent.height - tkCurrentBox))")
            say("           proposedSystem measureH=\(fmt(proposed.size.height)) nodeH=\(fmt(nodeProposed.height)) textKitInThatNode=\(fmt(tkProposedBox)) delta=\(fmt(nodeProposed.height - tkProposedBox))")
            say("           current lines=\(current.lines.count) proposed lines=\(proposed.lines.count)")
        }
        say("")

        // Natural width of long word vs maxWidth
        say("======= D overflow numbers =======")
        for kind in kinds {
            let font: CTFont = kind == .currentHelveticaNoStyle
                ? CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
                : systemFont(size: fontSize)
            let unconstrained = lines(of: longWord, font: font, width: 10_000, kind: kind)
            let constrained = lines(of: longWord, font: font, width: maxWidth, kind: kind)
            say("  \(kind.rawValue) unconstrainedW=\(fmt(unconstrained.size.width)) constrained=\(fmt(constrained.size)) lines=\(constrained.lines.count) overflow=\(constrained.size.width > maxWidth + 0.5)")
        }
        say("")

        try? log.write(to: out.appendingPathComponent("probe-log.txt"), atomically: true, encoding: .utf8)
        say("wrote \(out.appendingPathComponent("probe-log.txt").path)")

        // Visual reconstructions of InfiniteCanvas current vs proposed / export
        MainActor.assumeIsolated {
            renderCases(out: out, zh40t: zh40t, zh80t: zh80t, zh120t: zh120t, en80: en80, longWord: longWord, kinsoku: kinsoku, kinsoku2: kinsoku2, manual: manual, maxWidth: maxWidth, fontSize: fontSize)
        }
    }
}

@MainActor
func renderCases(
    out: URL,
    zh40t: String, zh80t: String, zh120t: String, en80: String,
    longWord: String, kinsoku: String, kinsoku2: String, manual: String,
    maxWidth: CGFloat, fontSize: CGFloat
) {
    func nodeSize(for text: String) -> CGSize {
        let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let r = lines(of: text, font: font, width: maxWidth, kind: .currentHelveticaNoStyle)
        return cacheSize(raw: r.size, maxWidth: maxWidth)
    }

    struct Pair: View {
        var caption: String
        var text: String
        var fontSize: CGFloat
        var node: CGSize
        var body: some View {
            HStack(alignment: .top, spacing: 16) {
                LabeledShot(title: "BEFORE canvas: draw(at:center) + clip  \(Int(node.width))×\(Int(node.height))", text: text, fontSize: fontSize, nodeSize: node, mode: .currentAtCenter)
                LabeledShot(title: "AFTER / export: draw(in: textRect)  \(Int(node.width))×\(Int(node.height))", text: text, fontSize: fontSize, nodeSize: node, mode: .proposedInRect)
            }
            .padding(12)
            .background(Color(white: 0.97))
        }
    }

    let shots: [(String, String)] = [
        ("A-zh40", zh40t),
        ("A-zh80", zh80t),
        ("A-zh120", zh120t),
        ("A-en80", en80),
        ("B-manual", manual),
        ("C-kinsoku", kinsoku),
        ("C-kinsoku2", kinsoku2),
        ("D-longword", longWord),
        ("D-longword-sentence", "The word is \(longWord) indeed."),
    ]
    for (name, text) in shots {
        let node = nodeSize(for: text)
        let view = Pair(caption: name, text: text, fontSize: fontSize, node: node)
        let size = CGSize(width: max(node.width * 2 + 80, 700), height: node.height + 80)
        renderPNG(view, to: out.appendingPathComponent("\(name)-before-after.png"), size: size)
        print("wrote \(name)-before-after.png node=\(Int(node.width))x\(Int(node.height))")
    }

    // Zoom panel for zh80 at 50/100/200 using proposed in-rect, font and size scaled
    let base = nodeSize(for: zh80t)
    struct ZoomRow: View {
        var text: String
        var base: CGSize
        var fontSize: CGFloat
        var body: some View {
            HStack(alignment: .bottom, spacing: 12) {
                ForEach([0.5, 1.0, 2.0], id: \.self) { scale in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("scale \(scale)  font=\(fontSize * scale)  \(Int(base.width * scale))×\(Int(base.height * scale))")
                            .font(.system(size: 10, design: .monospaced))
                        ProbeCanvas(
                            text: text,
                            fontSize: fontSize * scale,
                            nodeSize: CGSize(width: base.width * scale, height: base.height * scale),
                            mode: .proposedInRect
                        )
                    }
                }
            }
            .padding(12)
            .background(Color.white)
        }
    }
    renderPNG(
        ZoomRow(text: zh80t, base: base, fontSize: fontSize),
        to: out.appendingPathComponent("E-zoom-zh80-inrect.png"),
        size: CGSize(width: base.width * 2 + base.width * 0.5 + 80, height: base.height * 2 + 60)
    )
    print("wrote E-zoom-zh80-inrect.png")

    // Edit vs idle: show current at-center vs in-rect as proxy for the jump
    struct Jump: View {
        var text: String
        var fontSize: CGFloat
        var node: CGSize
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("G: same node box. Left is idle canvas today (draw at center). Right is edit-like wrapping (draw in rect, matching export).")
                    .font(.system(size: 11))
                    .frame(maxWidth: 680, alignment: .leading)
                Pair(caption: "G", text: text, fontSize: fontSize, node: node)
            }
            .padding(8)
            .background(Color(white: 0.97))
        }
    }
    let gNode = nodeSize(for: zh80t)
    renderPNG(Jump(text: zh80t, fontSize: fontSize, node: gNode), to: out.appendingPathComponent("G-edit-vs-idle-zh80.png"), size: CGSize(width: 760, height: gNode.height + 110))
    print("wrote G-edit-vs-idle-zh80.png")
}

func fmt(_ n: CGFloat) -> String { String(format: "%.1f", n) }
func fmt(_ s: CGSize) -> String { "\(fmt(s.width))x\(fmt(s.height))" }

// Silence unused warning helper in Pair - already used
