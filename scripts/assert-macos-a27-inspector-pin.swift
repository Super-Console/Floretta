import ApplicationServices
import AppKit
import Foundation

/// Launch a current-source Floretta-macOS.app (not an already-installed build)
/// and assert A27: the inspector「样式」segment's AXFrame.minY is readable in
/// both the selected and empty states, and the two values match.
///
/// Usage: assert-macos-a27-inspector-pin <Floretta-macOS.app>
/// Exit 0 only when both minY values are readable and within 1 pt.
/// If a state cannot be read, prints 无法读取 and exits 1. Never invents numbers.

func copy(_ e: AXUIElement, _ a: String) -> AnyObject? {
    var v: AnyObject?
    return AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success ? v : nil
}
func axString(_ e: AXUIElement, _ a: String) -> String? { copy(e, a) as? String }
func children(_ e: AXUIElement) -> [AXUIElement] { (copy(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }
func frame(_ e: AXUIElement) -> CGRect? {
    guard let v = copy(e, "AXFrame"), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
    var r = CGRect.zero
    return AXValueGetValue(v as! AXValue, .cgRect, &r) ? r : nil
}
func walk(_ e: AXUIElement, d: Int = 0, _ visit: (AXUIElement, Int) -> Void) {
    visit(e, d)
    if d < 40 { for c in children(e) { walk(c, d: d + 1, visit) } }
}
func findID(_ root: AXUIElement, _ id: String) -> AXUIElement? {
    var m: AXUIElement?
    walk(root) { e, _ in if m == nil, axString(e, kAXIdentifierAttribute) == id { m = e } }
    return m
}
func press(_ e: AXUIElement) -> Bool { AXUIElementPerformAction(e, kAXPressAction as CFString) == .success }
func wait(_ s: TimeInterval) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }
func windows(_ app: AXUIElement) -> [AXUIElement] { (copy(app, kAXWindowsAttribute) as? [AXUIElement]) ?? [] }
func identifiers(_ root: AXUIElement) -> [String] {
    var ids: [String] = []
    walk(root) { e, _ in if let id = axString(e, kAXIdentifierAttribute), !id.isEmpty { ids.append(id) } }
    return ids
}

func styleSegment(_ root: AXUIElement) -> AXUIElement? {
    if let group = findID(root, "inspector.tabs") {
        if let style = children(group).first(where: {
            axString($0, kAXTitleAttribute) == "样式" || axString($0, kAXDescriptionAttribute) == "样式"
        }) {
            return style
        }
        return group
    }
    return nil
}

struct Reading {
    var minY: CGFloat?
    var frame: CGRect?
    var headerMinY: CGFloat?
    var headerFrame: CGRect?
    var windowCount: Int
    var hasTabs: Bool
    var hasStyle: Bool
    var hasEmpty: Bool
    var hasEmptyCopy: Bool
    var hasCanvas: Bool
    var terminated: Bool
    var ids: [String]
}

func reading(ax: AXUIElement, running: NSRunningApplication) -> Reading {
    if running.isTerminated {
        return Reading(
            minY: nil, frame: nil, headerMinY: nil, headerFrame: nil,
            windowCount: 0, hasTabs: false, hasStyle: false, hasEmpty: false,
            hasEmptyCopy: false, hasCanvas: false, terminated: true, ids: []
        )
    }
    let wins = windows(ax)
    guard let root = wins.first else {
        return Reading(
            minY: nil, frame: nil, headerMinY: nil, headerFrame: nil,
            windowCount: 0, hasTabs: false, hasStyle: false, hasEmpty: false,
            hasEmptyCopy: false, hasCanvas: false, terminated: false, ids: []
        )
    }
    var emptyCopy = false
    var emptyID = false
    walk(root) { e, _ in
        if axString(e, kAXIdentifierAttribute) == "inspector.empty" { emptyID = true }
        let text = (axString(e, kAXTitleAttribute) ?? "")
            + (axString(e, kAXDescriptionAttribute) ?? "")
            + (axString(e, kAXValueAttribute) ?? "")
        if text.contains("选择一个主题") { emptyCopy = true }
    }
    let seg = styleSegment(root)
    let f = seg.flatMap(frame)
    let header = findID(root, "inspector.header")
    let hf = header.flatMap(frame)
    return Reading(
        minY: f?.minY,
        frame: f,
        headerMinY: hf?.minY,
        headerFrame: hf,
        windowCount: wins.count,
        hasTabs: findID(root, "inspector.tabs") != nil,
        hasStyle: findID(root, "inspector.style") != nil,
        hasEmpty: emptyID,
        hasEmptyCopy: emptyCopy,
        hasCanvas: findID(root, "editor.canvas") != nil,
        terminated: false,
        ids: identifiers(root)
    )
}

func printReading(_ r: Reading, label: String) {
    print("==== A27 \(label) ====")
    print("WINDOW_COUNT=\(r.windowCount)")
    print("TERMINATED=\(r.terminated)")
    if let y = r.minY, let f = r.frame {
        print("MINY=\(y)")
        print("FRAME=\(f.minX),\(f.minY),\(f.width),\(f.height)")
    } else {
        print("MINY=无法读取")
        if r.terminated {
            print("REASON=process-terminated")
        } else if r.windowCount == 0 {
            print("REASON=no-window")
        } else {
            print("REASON=no-style-segment")
        }
    }
    if let y = r.headerMinY, let f = r.headerFrame {
        print("HEADER_MINY=\(y)")
        print("HEADER_FRAME=\(f.minX),\(f.minY),\(f.width),\(f.height)")
    } else {
        print("HEADER_MINY=无法读取")
    }
    print("HAS_INSPECTOR_TABS=\(r.hasTabs)")
    print("HAS_INSPECTOR_STYLE=\(r.hasStyle)")
    print("HAS_INSPECTOR_EMPTY=\(r.hasEmpty)")
    print("HAS_EMPTY_COPY=\(r.hasEmptyCopy)")
    print("HAS_EDITOR_CANVAS=\(r.hasCanvas)")
}

func fail(_ message: String) -> Never {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
}

func cgPoint(fromAX p: CGPoint) -> CGPoint {
    let screens = NSScreen.screens
    let primary = screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.main
    let primaryTop = primary?.frame.maxY ?? 1440
    return CGPoint(x: p.x, y: primaryTop - p.y)
}

func clickCG(_ p: CGPoint) {
    let src = CGEventSource(stateID: .hidSystemState)
    if let down = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left),
       let up = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left) {
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}

guard CommandLine.arguments.count >= 2 else {
    fputs("usage: assert-macos-a27-inspector-pin <Floretta-macOS.app>\n", stderr)
    exit(64)
}

let appURL = URL(fileURLWithPath: CommandLine.arguments[1])
print("APP=\(appURL.path)")
print("TIME=\(ISO8601DateFormatter().string(from: Date()))")
print("AXIsProcessTrusted=\(AXIsProcessTrusted())")
if !AXIsProcessTrusted() {
    fail("AXIsProcessTrusted=false; grant Accessibility to the runner and retry")
}

let config = NSWorkspace.OpenConfiguration()
// Do not pass -FlorettaEditChrome: that launch argument still leaves
// WindowGroup uncreated, so the AX tree has only the menu bar.
config.arguments = [
    "-ApplePersistenceIgnoreState", "YES",
    "-FlorettaUITest",
    "-FlorettaOpenInspector",
    "-FlorettaLanguage", "zh-Hans",
]
config.activates = true
config.createsNewApplicationInstance = true
let sem = DispatchSemaphore(value: 0)
var running: NSRunningApplication?
var launchErr: Error?
NSWorkspace.shared.openApplication(at: appURL, configuration: config) { app, err in
    running = app
    launchErr = err
    sem.signal()
}
_ = sem.wait(timeout: .now() + 30)
if let launchErr { print("LAUNCH_ERR=\(launchErr)") }
guard let running else { fail("launch failed") }
print("PID=\(running.processIdentifier)")
defer {
    if !running.isTerminated {
        running.terminate()
        wait(1)
        if !running.isTerminated { running.forceTerminate() }
    }
}
let ax = AXUIElementCreateApplication(running.processIdentifier)

var home: AXUIElement?
for _ in 0..<40 {
    if let w = windows(ax).first, findID(w, "home.newMap") != nil { home = w; break }
    wait(0.2)
}
guard let home, let newMap = findID(home, "home.newMap") else {
    fail("no home.newMap (AX tree empty or still on a no-window launch path)")
}
print("PRESS_NEWMAP=\(press(newMap))")
var ready = false
for _ in 0..<40 {
    if let w = windows(ax).first, findID(w, "inspector.tabs") != nil {
        ready = true
        break
    }
    wait(0.2)
}
guard ready else { fail("inspector.tabs did not appear after home.newMap") }

let selected = reading(ax: ax, running: running)
printReading(selected, label: "selected")
guard let selectedMinY = selected.minY, let selectedFrame = selected.frame else {
    fail("selected-state MINY=无法读取")
}
let requiredIDs = ["editor.canvas", "inspector.header", "inspector.tabs", "basicChain.back"]
let missing = requiredIDs.filter { !selected.ids.contains($0) }
if !missing.isEmpty {
    fail("selected-state missing accessibility identifiers: \(missing.joined(separator: ", "))")
}

// Escape does not clear the central topic. A blank-canvas click does.
guard let window = windows(ax).first, let canvas = findID(window, "editor.canvas"), let f = frame(canvas) else {
    fail("editor.canvas frame 无法读取; cannot clear selection")
}
let axP = CGPoint(x: f.minX + f.width * 0.20, y: f.minY + f.height * 0.40)
let cg = cgPoint(fromAX: axP)
print("CLICK_CANVAS ax=\(axP.x),\(axP.y) cg=\(cg.x),\(cg.y) canvas=\(f.minX),\(f.minY),\(f.width),\(f.height)")
clickCG(cg)
var empty: Reading?
for _ in 0..<20 {
    wait(0.2)
    let r = reading(ax: ax, running: running)
    if r.hasEmpty || r.hasEmptyCopy { empty = r; break }
    if r.terminated || r.windowCount == 0 { empty = r; break }
}
let emptyReading = empty ?? reading(ax: ax, running: running)
printReading(emptyReading, label: "empty")
guard let emptyMinY = emptyReading.minY, let emptyFrame = emptyReading.frame else {
    fail("empty-state MINY=无法读取")
}
if !emptyReading.hasEmpty && !emptyReading.hasEmptyCopy {
    fail("cleared the canvas but inspector.empty / 「选择一个主题」 were not in the AX tree")
}

let delta = abs(selectedMinY - emptyMinY)
print("DELTA_MINY=\(delta)")
print("SELECTED_MINY=\(selectedMinY)")
print("EMPTY_MINY=\(emptyMinY)")
print("SELECTED_FRAME=\(selectedFrame.minX),\(selectedFrame.minY),\(selectedFrame.width),\(selectedFrame.height)")
print("EMPTY_FRAME=\(emptyFrame.minX),\(emptyFrame.minY),\(emptyFrame.width),\(emptyFrame.height)")
guard delta <= 1.0 else {
    fail("A27 pin failed: selected minY \(selectedMinY) vs empty minY \(emptyMinY)")
}
if let sh = selected.headerMinY, let eh = emptyReading.headerMinY, abs(sh - eh) > 1.0 {
    fail("A27 header pin failed: selected header minY \(sh) vs empty \(eh)")
}
print("PASS")
