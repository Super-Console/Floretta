import AppKit
import SwiftUI

// Offscreen size/pixel probe for the macOS leading navigation capsule.
//
// It renders the *shipped* `DocumentTitleCapsule` (extracted verbatim from
// Floretta/Shared/Shell/DocumentEditor.swift by
// scripts/measure-title-capsule.sh), measures its natural width, and checks the
// actual NSToolbar plate against the offscreen window's bounds.
//
// Two measurements:
//   default    the capsule content rendered alone; its full layout width and
//              the title's ink width expose space not accounted for by content.
//   --toolbar  the same capsule installed as a real NSToolbar item in a wide
//              offscreen window; the plate must remain within the actual window.
//
// Nothing is launched, shown, or screenshotted: no window is ever ordered
// front, and the process runs with the activation policy `.prohibited`.
//
// Usage: measure-title-capsule [--baseline | --toolbar | --narrow] [--verbose]
//   --baseline renders the earlier `[返回][名]` row for width comparison; that
//   shape is no longer in the product.

// MARK: - Titles under test

struct Case {
    var label: String
    var title: String
}

let cases: [Case] = [
    Case(label: "未命名 (3 CJK)", title: "未命名"),
    Case(
        label: "20 字中文",
        title: "第一单元知识梳理与重点概念笔记汇总整理"
    ),
    Case(
        label: "60 字含 .floretta",
        title: "项目复盘与结构整理笔记-长期维护版本-第二稿-补充材料-归档副本.floretta"
    ),
]

let limit: CGFloat = 240
let verbose = CommandLine.arguments.contains("--verbose")

// MARK: - Drawing and scanning

@MainActor
func makeHost<V: View>(_ view: V, constrainedWidth: CGFloat? = nil) -> NSHostingView<V> {
    let host = NSHostingView(rootView: view)
    host.appearance = NSAppearance(named: .aqua)
    host.frame = NSRect(x: 0, y: 0, width: 400, height: 40)
    // A window gives the hosting view a real layout/display context; it is
    // never ordered front, so nothing appears on any display.
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: max(400, constrainedWidth ?? 0), height: 40),
        styleMask: .borderless,
        backing: .buffered,
        defer: true
    )
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    if let constrainedWidth {
        host.frame = NSRect(x: 0, y: 0, width: constrainedWidth, height: 40)
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        return host
    }
    let fit = host.fittingSize
    let size = NSSize(width: max(1, ceil(fit.width)), height: max(1, ceil(fit.height)))
    host.frame = NSRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    host.displayIfNeeded()
    return host
}

func isInk(_ color: NSColor) -> Bool {
    guard let rgb = color.usingColorSpace(.deviceRGB), rgb.alphaComponent >= 0.5 else { return false }
    let luma = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
    return luma < 0.5
}

/// Pixel columns that carry ink, merged across sub-3 pt gaps, in points.
func inkRuns(_ rep: NSBitmapImageRep, scale: CGFloat) -> [(min: CGFloat, max: CGFloat)] {
    var columns = [Int](repeating: 0, count: rep.pixelsWide)
    for x in 0..<rep.pixelsWide {
        for y in 0..<rep.pixelsHigh {
            guard let color = rep.colorAt(x: x, y: y) else { continue }
            if isInk(color) { columns[x] += 1 }
        }
    }
    let mergeGap = Int((3 * scale).rounded())
    var runs: [(min: CGFloat, max: CGFloat)] = []
    var runStart: Int?
    var lastInk = -1
    for (x, count) in columns.enumerated() {
        guard count > 0 else { continue }
        if let start = runStart, x - lastInk > mergeGap {
            runs.append((CGFloat(start) / scale, CGFloat(lastInk + 1) / scale))
            runStart = x
        } else if runStart == nil {
            runStart = x
        }
        lastInk = x
    }
    if let start = runStart {
        runs.append((CGFloat(start) / scale, CGFloat(lastInk + 1) / scale))
    }
    return runs
}

struct Reading {
    var width: CGFloat
    var titleMinX: CGFloat
    var titleMaxX: CGFloat
    var runs: [(min: CGFloat, max: CGFloat)]

    var titleWidth: CGFloat { titleMaxX - titleMinX }
}

@MainActor
func measure<V: View>(_ view: V, constrainedWidth: CGFloat? = nil) -> Reading? {
    let host = makeHost(view, constrainedWidth: constrainedWidth)
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
    host.cacheDisplay(in: host.bounds, to: rep)
    let scale = CGFloat(rep.pixelsWide) / max(1, host.bounds.width)
    let runs = inkRuns(rep, scale: scale)
    guard runs.count >= 2 else { return nil }
    // The first run is the back glyph; the name is everything to its right.
    let title = runs.dropFirst()
    let minX = title.map(\.min).min() ?? 0
    let maxX = title.map(\.max).max() ?? 0
    return Reading(width: host.bounds.width, titleMinX: minX, titleMaxX: maxX, runs: runs)
}

// MARK: - Real toolbar, still offscreen

final class ToolbarDelegate: NSObject, NSToolbarDelegate {
    static let itemIdentifier = NSToolbarItem.Identifier("document.navigation")
    var host: NSView?

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard itemIdentifier == Self.itemIdentifier, let host else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.view = host
        item.label = "nav"
        return item
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.itemIdentifier, .flexibleSpace]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.itemIdentifier, .flexibleSpace]
    }
}

func typeName(_ view: NSView) -> String { String(describing: type(of: view)) }

struct ToolbarReading {
    var itemWidth: CGFloat
    var itemMinX: CGFloat
    var windowWidth: CGFloat
    var contentMinX: CGFloat
    var contentWidth: CGFloat
    var viewerClass: String

    var itemMaxX: CGFloat { itemMinX + itemWidth }
}

@MainActor
func measureInToolbar(_ title: String, windowWidth: CGFloat) -> (reading: ToolbarReading?, note: String) {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: 600),
        styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
        backing: .buffered,
        defer: true
    )
    window.appearance = NSAppearance(named: .aqua)
    window.title = "Floretta"
    window.isReleasedWhenClosed = false

    let host = NSHostingView(rootView: DocumentTitleCapsule(
        title: title,
        titleWidthLimit: limit,
        backLabel: "返回",
        backHint: "返回导图列表",
        renameHint: "为这份导图重新命名",
        onBack: {},
        onRename: {}
    ))
    let delegate = ToolbarDelegate()
    delegate.host = host
    let toolbar = NSToolbar(identifier: "probe.navigation")
    toolbar.delegate = delegate
    toolbar.displayMode = .iconOnly
    toolbar.allowsUserCustomization = false
    window.toolbar = toolbar
    window.toolbarStyle = .unified
    window.layoutIfNeeded()
    toolbar.validateVisibleItems()
    window.layoutIfNeeded()

    guard let frameView = window.contentView?.superview else {
        return (nil, "no theme frame")
    }
    frameView.layoutSubtreeIfNeeded()
    guard host.superview != nil, host.window === window else {
        return (nil, "the bar did not build an item view offscreen")
    }
    if verbose {
        var chain: [String] = []
        var up: NSView? = host
        while let view = up {
            chain.append(String(format: "%@ w=%.1f", typeName(view), view.frame.width))
            up = view.superview
        }
        print("    chain: " + chain.joined(separator: " <- "))
    }
    // The plate: the capsule the bar draws around this item.
    var plate: NSView = host
    var itemViewer: NSView?
    var up = host.superview
    while let view = up {
        if typeName(view).contains("PlatterView") { plate = view; break }
        if typeName(view).contains("ItemViewer") { itemViewer = view }
        up = view.superview
    }
    let plateView = plate === host ? (itemViewer ?? host) : plate
    let plateFrame = plateView.convert(plateView.bounds, to: frameView)
    let contentFrame = host.convert(host.bounds, to: frameView)
    return (
        ToolbarReading(
            itemWidth: plateFrame.width,
            itemMinX: plateFrame.minX,
            windowWidth: frameView.bounds.width,
            contentMinX: contentFrame.minX,
            contentWidth: contentFrame.width,
            viewerClass: typeName(plateView)
        ),
        "plate \(typeName(plateView))"
    )
}

// MARK: - Views

let baseline = CommandLine.arguments.contains("--baseline")
let toolbarMode = CommandLine.arguments.contains("--toolbar")
let narrowMode = CommandLine.arguments.contains("--narrow")

func titleText(_ title: String) -> some View {
    CappedWidthLayout(maxWidth: limit) {
        Text(verbatim: title)
            .lineLimit(1)
            .truncationMode(.middle)
    }
}

func backControl() -> some View {
    Button(action: {}) {
        Image(systemName: "chevron.backward")
    }
}

@MainActor
func runContent() {
    print("mode: \(baseline ? "baseline ([back][title], pre-fix)" : "shipped DocumentTitleCapsule")")
    print("title                         contentW titleInk  extraW")
    var failures: [String] = []
    for item in cases {
        let view: AnyView
        if baseline {
            view = AnyView(
                HStack(spacing: 8) {
                    backControl()
                    Button(action: {}) { titleText(item.title) }
                        .buttonStyle(.borderless)
                }
            )
        } else {
            view = AnyView(
                DocumentTitleCapsule(
                    title: item.title,
                    titleWidthLimit: limit,
                    backLabel: "返回",
                    backHint: "返回导图列表",
                    renameHint: "为这份导图重新命名",
                    onBack: {},
                    onRename: {}
                )
            )
        }
        guard let r = measure(view) else {
            print("\(item.label): no ink found")
            failures.append("\(item.label): no ink found")
            continue
        }
        let name = item.label.padding(toLength: 30, withPad: " ", startingAt: 0)
        print(String(
            format: "%@ %8.2f %8.2f %7.2f",
            name, r.width, r.titleWidth, r.width - r.titleWidth
        ))
        if verbose {
            print("    runs: " + r.runs.map { String(format: "[%.1f,%.1f]", $0.min, $0.max) }.joined(separator: " "))
        }
        if r.titleMinX < 1 || r.titleMaxX > r.width - 1 {
            failures.append("\(item.label): text leaves the capsule")
        }
        if r.titleWidth > limit + 0.5 {
            failures.append("\(item.label): text wider than the cap")
        }
        if item.title.count <= 3 && r.width - r.titleWidth > 72 {
            failures.append("\(item.label): short-title chrome adds \(r.width - r.titleWidth) pt beyond the visible title")
        }
        if item.title.count > 3 && r.width > limit + 80 {
            failures.append("\(item.label): capsule width \(r.width) exceeds title cap plus controls")
        }
    }
    report(failures, pass: "short titles hug their controls and long titles stay within the width cap")
}

@MainActor
func runToolbar() {
    print("mode: real NSToolbar item (wide offscreen window, never ordered front)")
    print("title                         requestW actualW  plateX  plateW  plateR  titleW")
    var failures: [String] = []
    var note = ""
    for requestedWidth in [900.0] as [CGFloat] {
        for item in cases {
            let (reading, message) = measureInToolbar(item.title, windowWidth: requestedWidth)
            note = message
            guard let r = reading else {
                print("\(item.label) @ \(requestedWidth): \(message)")
                failures.append("\(item.label) @ \(requestedWidth): \(message)")
                continue
            }
            let name = item.label.padding(toLength: 30, withPad: " ", startingAt: 0)
            print(String(
                format: "%@ %8.0f %7.2f %7.2f %7.2f %7.2f %7.2f",
                name, requestedWidth, r.windowWidth, r.itemMinX, r.itemWidth, r.itemMaxX, r.contentWidth
            ))
            if r.itemMinX < -0.5 || r.itemMaxX > r.windowWidth + 0.5 {
                failures.append("\(item.label) @ \(requestedWidth): toolbar plate [\(r.itemMinX), \(r.itemMaxX)] exceeds window width \(r.windowWidth)")
            }
            if item.title.count > 3 && r.contentWidth > limit + 80 {
                failures.append("\(item.label) @ \(requestedWidth): title capsule content \(r.contentWidth) exceeds the width cap plus controls")
            }
        }
    }
    if verbose { print("    \(note)") }
    report(failures, pass: "every title capsule remains inside its actual toolbar window")
}

@MainActor
func runNarrow() {
    print("mode: constrained offscreen title capsule (no ordered-front window)")
    print("title                         hostW titleMin titleMax titleW")
    var failures: [String] = []
    for width in [280.0, 240.0] as [CGFloat] {
        for item in cases.dropFirst() {
            let view = DocumentTitleCapsule(
                title: item.title,
                titleWidthLimit: limit,
                backLabel: "返回",
                backHint: "返回导图列表",
                renameHint: "为这份导图重新命名",
                onBack: {},
                onRename: {}
            )
            guard let reading = measure(view, constrainedWidth: width) else {
                failures.append("\(item.label) @ \(width): no rendered title ink")
                continue
            }
            let name = item.label.padding(toLength: 30, withPad: " ", startingAt: 0)
            print(String(
                format: "%@ %5.0f %8.2f %8.2f %7.2f",
                name, width, reading.titleMinX, reading.titleMaxX, reading.titleWidth
            ))
            if reading.titleMinX < 0.5 || reading.titleMaxX > width - 0.5 {
                failures.append("\(item.label) @ \(width): title ink exceeds the available window width")
            }
            if reading.titleWidth > min(limit, width) + 0.5 {
                failures.append("\(item.label) @ \(width): title ink exceeds its width cap")
            }
        }
    }
    report(failures, pass: "long titles stay visible within narrow available widths")
}

func report(_ failures: [String], pass: String) {
    if failures.isEmpty {
        print("RESULT: \(pass)")
    } else {
        print("RESULT: FAILED")
        for failure in failures { print("  - \(failure)") }
        exit(1)
    }
}

@main
struct Probe {
    static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        MainActor.assumeIsolated {
            if toolbarMode {
                runToolbar()
            } else if narrowMode {
                runNarrow()
            } else {
                runContent()
            }
        }
    }
}
