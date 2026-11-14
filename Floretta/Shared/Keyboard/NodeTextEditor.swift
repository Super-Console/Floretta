import FlorettaCore
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Supplies the font-based height used by node-text vertical centering.
/// `previousVerticalInset` is explicit so the measurement contract can be
/// exercised with real prior-inset values; it must never affect the result.
enum EditorTextCenteringMeasurement {
    #if os(macOS)
    static func glyphHeight(
        font: NSFont,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer,
        previousVerticalInset: CGFloat
    ) -> CGFloat {
        _ = previousVerticalInset
        layoutManager.ensureLayout(for: textContainer)
        return layoutManager.defaultLineHeight(for: font)
    }
    #else
    static func glyphHeight(
        font: UIFont,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer,
        previousVerticalInset: CGFloat
    ) -> CGFloat {
        _ = previousVerticalInset
        layoutManager.ensureLayout(for: textContainer)
        return font.lineHeight
    }
    #endif
}

extension KeyModifiers {
    init(_ modifiers: EventModifiers) {
        self = []
        if modifiers.contains(.shift) { insert(.shift) }
        if modifiers.contains(.command) { insert(.command) }
        if modifiers.contains(.option) { insert(.option) }
        if modifiers.contains(.control) { insert(.control) }
    }
}

extension KeyEvent {
    /// Canvas command-mode keys. Returns nil for keys the mapper does not care about.
    init?(press: KeyPress, mode: KeyboardMode, isComposing: Bool) {
        let modifiers = KeyModifiers(press.modifiers)
        let key: KeyToken
        if press.key == .tab {
            key = .tab
        } else if press.key == .return {
            key = .enter
        } else if press.key == .space {
            key = .space
        } else if press.key == .escape {
            key = .escape
        } else if press.key == .delete {
            key = .backspace
        } else if press.key == .deleteForward {
            key = .delete
        } else if press.key == .upArrow {
            key = .up
        } else if press.key == .downArrow {
            key = .down
        } else if press.key == .leftArrow {
            key = .left
        } else if press.key == .rightArrow {
            key = .right
        } else if let mapped = KeyEvent.mappedCharacter(press.characters) {
            key = mapped
        } else if press.characters == "\u{F705}" || press.key == KeyEquivalent("\u{F705}") {
            key = .f2
        } else if press.characters == "\u{F708}" || press.key == KeyEquivalent("\u{F708}") {
            key = .f5
        } else {
            return nil
        }
        self.init(key: key, modifiers: modifiers, mode: mode, isComposing: isComposing)
    }

    /// Letters and the XMind single-key glyphs. Shifted characters already appear
    /// in `characters` as `+` or `*`.
    static func mappedCharacter(_ raw: String) -> KeyToken? {
        let lowered = raw.lowercased()
        guard lowered.count == 1, let character = lowered.first else {
            if raw == "+" { return .character("+") }
            if raw == "*" { return .character("*") }
            return nil
        }
        if "zayarl+-*/".contains(character) {
            return .character(character)
        }
        return nil
    }
}

/// System text view over the node being edited. Shortcuts go through `KeyboardCommandMapper`.
/// Tab in edit mode is swallowed here so it neither creates a node nor moves focus.
struct NodeTextEditor: View {
    @Binding var text: String
    @Binding var isComposing: Bool
    @Binding var minimumWidth: CGFloat
    var fontSize: CGFloat
    var fontMetrics: any FontMetricsPort = CoreTextFontMetrics()
    var onEvent: (KeyEvent) -> Bool
    /// Stickies take Return as another line. Nodes still commit on Return.
    var returnInsertsLine: Bool = false
    var paper: Color? = nil
    var ink: Color? = nil
    /// Non-zero asks the focused field to start system dictation once.
    var dictationToken: Int = 0
    /// Select the placeholder so the first dictated phrase replaces it.
    var dictationReplacesPlaceholder: Bool = false
    /// When set, the field paints this topic instead of the system text background.
    var nodeChrome: NodeEditSurface? = nil
    @Environment(\.appearanceProfile) private var appearanceProfile

    var body: some View {
        #if os(macOS)
        MacNodeTextEditor(
            text: $text,
            isComposing: $isComposing,
            minimumWidth: $minimumWidth,
            fontSize: fontSize,
            fontMetrics: fontMetrics,
            onEvent: onEvent,
            returnInsertsLine: returnInsertsLine,
            paper: paper,
            ink: ink,
            dictationToken: dictationToken,
            dictationReplacesPlaceholder: dictationReplacesPlaceholder,
            nodeChrome: nodeChrome,
            fontFamilyID: appearanceProfile.fontFamilyID
        )
        #else
        IOSNodeTextEditor(
            text: $text,
            isComposing: $isComposing,
            minimumWidth: $minimumWidth,
            fontSize: fontSize,
            fontMetrics: fontMetrics,
            onEvent: onEvent,
            returnInsertsLine: returnInsertsLine,
            paper: paper,
            ink: ink,
            dictationToken: dictationToken,
            dictationReplacesPlaceholder: dictationReplacesPlaceholder,
            nodeChrome: nodeChrome,
            fontFamilyID: appearanceProfile.fontFamilyID
        )
        #endif
    }
}

#if os(macOS)
private struct MacNodeTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var isComposing: Bool
    @Binding var minimumWidth: CGFloat
    var fontSize: CGFloat
    var fontMetrics: any FontMetricsPort
    var onEvent: (KeyEvent) -> Bool
    var returnInsertsLine: Bool
    var paper: Color?
    var ink: Color?
    var dictationToken: Int
    var dictationReplacesPlaceholder: Bool
    var nodeChrome: NodeEditSurface?
    var fontFamilyID: String = "system-serif"

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            isComposing: $isComposing,
            minimumWidth: $minimumWidth,
            fontSize: fontSize,
            fontMetrics: fontMetrics,
            onEvent: onEvent,
            returnInsertsLine: returnInsertsLine,
            paper: paper,
            ink: ink,
            dictationToken: dictationToken,
            dictationReplacesPlaceholder: dictationReplacesPlaceholder
        )
    }

    func makeNSView(context: Context) -> EditingTextView {
        let view = EditingTextView()
        view.delegate = context.coordinator
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.isEditable = true
        view.isSelectable = true
        view.drawsBackground = true
        view.backgroundColor = paper.map { NSColor($0) } ?? .textBackgroundColor
        view.textColor = ink.map { NSColor($0) } ?? .labelColor
        view.insertionPointColor = view.textColor ?? .labelColor
        view.font = ThemeFontCascade.platformFont(familyID: fontFamilyID, nodeDesign: "default", size: fontSize)
        if let nodeChrome {
            applyNodeChrome(nodeChrome, to: view, ownsKeys: false)
        } else if paper != nil {
            view.textContainerInset = NSSize(width: 8, height: 6)
        }
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.textContainer?.widthTracksTextView = true
        view.string = text
        view.onMarkedTextChange = { [weak view] in
            guard let view else { return }
            context.coordinator.compositionChanged(view)
        }
        return view
    }

    func updateNSView(_ nsView: EditingTextView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.isComposing = $isComposing
        context.coordinator.minimumWidth = $minimumWidth
        context.coordinator.fontSize = fontSize
        context.coordinator.onEvent = onEvent
        context.coordinator.returnInsertsLine = returnInsertsLine
        context.coordinator.paper = paper
        context.coordinator.ink = ink
        let ownsKeys = nsView.window?.firstResponder === nsView
        if let nodeChrome {
            applyNodeChrome(nodeChrome, to: nsView, ownsKeys: ownsKeys)
        }
        if context.coordinator.dictationToken != dictationToken, dictationToken != 0 {
            context.coordinator.didFocus = false
        }
        context.coordinator.dictationToken = dictationToken
        context.coordinator.dictationReplacesPlaceholder = dictationReplacesPlaceholder
        if nodeChrome == nil {
            if let paper {
                nsView.drawsBackground = true
                nsView.backgroundColor = NSColor(paper)
            }
            if let ink {
                nsView.textColor = NSColor(ink)
                nsView.insertionPointColor = NSColor(ink)
            }
        }
        nsView.onMarkedTextChange = { [weak nsView] in
            guard let nsView else { return }
            context.coordinator.compositionChanged(nsView)
        }
        if !nsView.hasMarkedText(), !context.coordinator.isComposing.wrappedValue {
            if let nodeChrome {
                assignEditingFont(nodeChrome, familyID: fontFamilyID, to: nsView)
            } else {
                assignEditingFont(
                    signature: EditingFontSignature(
                        familyID: fontFamilyID,
                        design: "default",
                        size: max(fontSize, 1),
                        bold: false,
                        italic: false
                    ),
                    font: ThemeFontCascade.platformFont(familyID: fontFamilyID, nodeDesign: "default", size: fontSize),
                    to: nsView
                )
            }
            if nsView.string != text, !ownsKeys {
                nsView.string = text
                if let nodeChrome {
                    applyNodeChrome(nodeChrome, to: nsView, ownsKeys: false)
                }
            }
        }
        if !context.coordinator.didFocus {
            DispatchQueue.main.async { [weak nsView] in
                guard let nsView, let window = nsView.window else { return }
                if window.firstResponder !== nsView {
                    window.makeFirstResponder(nsView)
                }
                context.coordinator.didFocus = window.firstResponder === nsView
                context.coordinator.noteDictation(on: nsView)
            }
        } else {
            context.coordinator.noteDictation(on: nsView)
        }
    }

    /// Focus must not swap the topic for the system text background or font.
    private func applyNodeChrome(_ chrome: NodeEditSurface, to view: EditingTextView, ownsKeys: Bool) {
        let fill = NSColor(
            srgbRed: CGFloat(chrome.fill.red),
            green: CGFloat(chrome.fill.green),
            blue: CGFloat(chrome.fill.blue),
            alpha: chrome.hidesFill ? 0 : 1
        )
        let ink = NSColor(
            srgbRed: CGFloat(chrome.textColor.red),
            green: CGFloat(chrome.textColor.green),
            blue: CGFloat(chrome.textColor.blue),
            alpha: 1
        )
        view.lockedBackground = fill
        view.lockedTextColor = ink
        view.locksChrome = true
        view.centersInNode = true
        view.backgroundColor = fill
        view.drawsBackground = !chrome.hidesFill
        view.textColor = ink
        view.insertionPointColor = ink
        view.focusRingType = .none
        assignEditingFont(chrome, familyID: fontFamilyID, to: view)
        view.wantsLayer = true
        view.layer?.cornerRadius = chrome.cornerRadius
        view.layer?.masksToBounds = true
        view.layer?.borderWidth = 0
        view.textContainer?.lineFragmentPadding = 0
        let style = NodeTextTypography.paragraphStyle()
        if view.defaultParagraphStyle?.alignment != .center
            || view.defaultParagraphStyle?.lineBreakMode != .byWordWrapping {
            view.defaultParagraphStyle = style
        }
        if (view.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.alignment != .center {
            var typing = view.typingAttributes
            typing[.paragraphStyle] = style
            view.typingAttributes = typing
        }
        if let storage = view.textStorage, storage.length > 0, !view.hasMarkedText(),
           storageNeedsCenteredParagraph(storage) {
            storage.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: storage.length))
        }
        if !ownsKeys, view.alignment != .center {
            view.alignment = .center
        }
        view.publishChromeProbe()
    }

    /// One font assignment per signature. Comparing `NSFont` stays false after
    /// AppKit substitutes a fallback for the cascade face, and assigning again
    /// dirties layout while the editor body is already on the stack.
    private func assignEditingFont(_ chrome: NodeEditSurface, familyID: String, to view: EditingTextView) {
        assignEditingFont(
            signature: EditingFontSignature(
                familyID: familyID,
                design: chrome.fontDesign,
                size: max(chrome.fontSize, 1),
                bold: chrome.bold,
                italic: chrome.italic
            ),
            font: Self.editingFont(chrome, familyID: familyID),
            to: view
        )
    }

    private func assignEditingFont(signature: EditingFontSignature, font: NSFont, to view: EditingTextView) {
        guard EditorLayoutConvergence.shouldAssignFont(requested: signature, lastAssigned: view.appliedFontSignature) else {
            return
        }
        view.appliedFontSignature = signature
        view.lockedFont = font
        if view.font != font {
            view.font = font
        }
    }

    private func storageNeedsCenteredParagraph(_ storage: NSTextStorage) -> Bool {
        guard let style = storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle else {
            return true
        }
        return style.alignment != .center || style.lineBreakMode != .byWordWrapping
    }

    private static func editingFont(_ chrome: NodeEditSurface, familyID: String) -> NSFont {
        let size = max(chrome.fontSize, 1)
        var font = ThemeFontCascade.platformFont(familyID: familyID, nodeDesign: chrome.fontDesign, size: size)
        if chrome.bold || chrome.italic {
            var traits = font.fontDescriptor.symbolicTraits
            if chrome.bold { traits.insert(.bold) }
            if chrome.italic { traits.insert(.italic) }
            let descriptor = font.fontDescriptor.withSymbolicTraits(traits)
            font = NSFont(descriptor: descriptor, size: size) ?? font
        }
        return font
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var isComposing: Binding<Bool>
        var minimumWidth: Binding<CGFloat>
        var fontSize: CGFloat
        var fontMetrics: any FontMetricsPort
        var onEvent: (KeyEvent) -> Bool
        var returnInsertsLine: Bool
        var paper: Color?
        var ink: Color?
        var dictationToken: Int
        var dictationReplacesPlaceholder: Bool
        var didFocus = false
        private var handledDictationToken = 0

        init(
            text: Binding<String>,
            isComposing: Binding<Bool>,
            minimumWidth: Binding<CGFloat>,
            fontSize: CGFloat,
            fontMetrics: any FontMetricsPort,
            onEvent: @escaping (KeyEvent) -> Bool,
            returnInsertsLine: Bool,
            paper: Color?,
            ink: Color?,
            dictationToken: Int,
            dictationReplacesPlaceholder: Bool
        ) {
            self.text = text
            self.isComposing = isComposing
            self.minimumWidth = minimumWidth
            self.fontSize = fontSize
            self.fontMetrics = fontMetrics
            self.onEvent = onEvent
            self.returnInsertsLine = returnInsertsLine
            self.paper = paper
            self.ink = ink
            self.dictationToken = dictationToken
            self.dictationReplacesPlaceholder = dictationReplacesPlaceholder
        }

        /// Select the new-topic placeholder, then start system dictation.
        /// Spoken characters still arrive through `textDidChange`, like typing.
        func noteDictation(on view: NSTextView) {
            guard dictationToken != 0, dictationToken != handledDictationToken else { return }
            guard view.window?.firstResponder === view else { return }
            handledDictationToken = dictationToken
            if dictationReplacesPlaceholder {
                view.selectAll(nil)
            }
            SystemDictation.begin(on: view)
        }

        func compositionChanged(_ view: NSTextView) {
            let composing = view.hasMarkedText()
            isComposing.wrappedValue = composing
            if view.string != text.wrappedValue {
                text.wrappedValue = view.string
            }
            if composing {
                let font = view.font ?? NSFont.systemFont(ofSize: max(fontSize, 1))
                let width = CGFloat(fontMetrics.measure(text: view.string, fontName: font.fontName, fontSize: font.pointSize, maxWidth: nil).width) + 24
                minimumWidth.wrappedValue = width
            } else {
                minimumWidth.wrappedValue = 0
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            compositionChanged(view)
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            let composing = textView.hasMarkedText()
            isComposing.wrappedValue = composing
            guard let event = KeyEvent(macCommand: commandSelector, mode: .edit, isComposing: composing) else {
                return false
            }
            // Shift+Enter must land at the caret. The session command only appends
            // a newline at the end of the buffer and would also swallow this key.
            if NodeEditLineBreak.textViewInsertsLine(for: event) {
                return false
            }
            if returnInsertsLine, event.key == .enter, !event.modifiers.contains(.command) {
                return false
            }
            if returnInsertsLine, event.key == .enter, event.modifiers.contains(.command) {
                var commit = event
                commit.modifiers = []
                return onEvent(commit)
            }
            if onEvent(event) {
                return true
            }
            return event.key == .tab
        }
    }
}

/// Marked text does not call `textDidChange`. Publishing it here lets the node
/// widen before the line wraps. The hook is the same idea as Mindscape 0.7.0;
/// this view does not include their editor.
private final class EditingTextView: NSTextView {
    var onMarkedTextChange: (() -> Void)?
    var locksChrome = false
    var centersInNode = false
    var lockedBackground: NSColor = .clear
    var lockedTextColor: NSColor = .labelColor
    var lockedFont: NSFont?
    var appliedFontSignature: EditingFontSignature?
    var centeringPass = TextCenteringPass.idle
    private var applyingChrome = false

    override var backgroundColor: NSColor {
        get { super.backgroundColor }
        set { super.backgroundColor = locksChrome ? lockedBackground : newValue }
    }

    override var drawsBackground: Bool {
        get { super.drawsBackground }
        set {
            if locksChrome {
                super.drawsBackground = lockedBackground.alphaComponent > 0.01
            } else {
                super.drawsBackground = newValue
            }
        }
    }

    override var textColor: NSColor? {
        get { super.textColor }
        set { super.textColor = locksChrome ? lockedTextColor : newValue }
    }

    override var focusRingType: NSFocusRingType {
        get { centersInNode ? .none : super.focusRingType }
        set { if !centersInNode { super.focusRingType = newValue } }
    }

    override func drawFocusRingMask() {
        if centersInNode { return }
        super.drawFocusRingMask()
    }

    override var focusRingMaskBounds: NSRect {
        centersInNode ? .zero : super.focusRingMaskBounds
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        guard locksChrome else { return ok }
        super.backgroundColor = lockedBackground
        super.drawsBackground = lockedBackground.alphaComponent > 0.01
        super.textColor = lockedTextColor
        if let lockedFont, font != lockedFont {
            font = lockedFont
        }
        insertionPointColor = lockedTextColor
        focusRingType = .none
        return ok
    }

    override func layout() {
        super.layout()
        guard centersInNode, !applyingChrome else {
            publishChromeProbe()
            return
        }
        guard centeringPass.shouldApply(to: bounds.size, text: string) else {
            publishChromeProbe()
            return
        }
        guard let layoutManager, let textContainer else {
            publishChromeProbe()
            return
        }
        // Latch before the inset write. The write re-enters layout, and a
        // second pass for the same bounds and string must not write again.
        centeringPass = TextCenteringPass(bounds: bounds.size, text: string)
        let font = self.font ?? NSFont.systemFont(ofSize: 12)
        let glyphHeight = EditorTextCenteringMeasurement.glyphHeight(
            font: font,
            layoutManager: layoutManager,
            textContainer: textContainer,
            previousVerticalInset: textContainerInset.height
        )
        let vertical = EditorLayoutConvergence.centeredVerticalInset(
            boundsHeight: bounds.height,
            glyphHeight: glyphHeight
        )
        let next = NSSize(width: NodeEditChrome.textInset.width, height: vertical)
        if EditorLayoutConvergence.shouldWriteVerticalInset(current: textContainerInset.height, proposed: vertical)
            || abs(textContainerInset.width - next.width) > 0.5 {
            applyingChrome = true
            textContainerInset = next
            applyingChrome = false
        }
        publishChromeProbe()
    }

    func publishChromeProbe() {
        guard locksChrome, bounds.width > 1, bounds.height > 1 else { return }
        let rgb = backgroundColor.usingColorSpace(.sRGB) ?? lockedBackground
        let fill = BranchColor(
            red: Double(rgb.redComponent),
            green: Double(rgb.greenComponent),
            blue: Double(rgb.blueComponent)
        )
        let value = NodeEditChrome.accessibilityValue(editing: true, fill: fill, size: bounds.size)
        setAccessibilityIdentifier(NodeEditChrome.accessibilityIdentifier)
        setAccessibilityLabel("node")
        if accessibilityValue() as? String != value {
            setAccessibilityValue(value)
        }
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        onMarkedTextChange?()
    }

    override func unmarkText() {
        super.unmarkText()
        onMarkedTextChange?()
    }
}

private extension KeyEvent {
    init?(macCommand selector: Selector, mode: KeyboardMode, isComposing: Bool) {
        var modifiers = KeyModifiers()
        let flags = NSEvent.modifierFlags
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        let name = NSStringFromSelector(selector)
        let key: KeyToken
        switch name {
        case "insertTab:", "insertBacktab:":
            key = .tab
        case "insertLineBreak:":
            modifiers.insert(.shift)
            key = .enter
        case "insertNewline:", "insertNewlineIgnoringFieldEditor:":
            key = .enter
        case "cancelOperation:":
            key = .escape
        case "deleteBackward:":
            key = .backspace
        case "deleteForward:":
            key = .delete
        case "moveUp:":
            key = .up
        case "moveDown:":
            key = .down
        case "moveLeft:":
            key = .left
        case "moveRight:":
            key = .right
        default:
            return nil
        }
        self.init(key: key, modifiers: modifiers, mode: mode, isComposing: isComposing)
    }
}
#else
private struct IOSNodeTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var isComposing: Bool
    @Binding var minimumWidth: CGFloat
    var fontSize: CGFloat
    var fontMetrics: any FontMetricsPort
    var onEvent: (KeyEvent) -> Bool
    var returnInsertsLine: Bool
    var paper: Color?
    var ink: Color?
    var dictationToken: Int
    var dictationReplacesPlaceholder: Bool
    var nodeChrome: NodeEditSurface?
    var fontFamilyID: String = "system-serif"

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            isComposing: $isComposing,
            minimumWidth: $minimumWidth,
            fontSize: fontSize,
            fontMetrics: fontMetrics,
            onEvent: onEvent,
            returnInsertsLine: returnInsertsLine,
            dictationToken: dictationToken,
            dictationReplacesPlaceholder: dictationReplacesPlaceholder
        )
    }

    func makeUIView(context: Context) -> FlorettaTextView {
        let view = FlorettaTextView()
        view.delegate = context.coordinator
        view.font = ThemeFontCascade.platformFont(familyID: fontFamilyID, nodeDesign: "default", size: fontSize)
        view.backgroundColor = paper.map { UIColor($0) } ?? .systemBackground
        view.textColor = ink.map { UIColor($0) } ?? .label
        view.tintColor = view.textColor
        view.isScrollEnabled = returnInsertsLine
        view.autocorrectionType = .no
        view.spellCheckingType = .no
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.smartInsertDeleteType = .no
        view.text = text
        view.returnInsertsLine = returnInsertsLine
        view.onEvent = onEvent
        if let nodeChrome {
            applyNodeChrome(nodeChrome, to: view, ownsKeys: false)
        } else if paper != nil {
            view.textContainerInset = UIEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        }
        view.onMarkedTextChange = { [weak view] in
            guard let view else { return }
            context.coordinator.compositionChanged(view)
        }
        view.onDictationPhrase = { [weak view] phrase in
            guard let view else { return false }
            return context.coordinator.acceptDictation(phrase, in: view)
        }
        return view
    }

    func updateUIView(_ uiView: FlorettaTextView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.isComposing = $isComposing
        context.coordinator.minimumWidth = $minimumWidth
        context.coordinator.fontSize = fontSize
        context.coordinator.onEvent = onEvent
        context.coordinator.returnInsertsLine = returnInsertsLine
        let ownsKeys = uiView.isFirstResponder
        if let nodeChrome {
            applyNodeChrome(nodeChrome, to: uiView, ownsKeys: ownsKeys)
        }
        if context.coordinator.dictationToken != dictationToken, dictationToken != 0 {
            context.coordinator.didFocus = false
        }
        context.coordinator.dictationToken = dictationToken
        context.coordinator.dictationReplacesPlaceholder = dictationReplacesPlaceholder
        uiView.returnInsertsLine = returnInsertsLine
        uiView.onEvent = onEvent
        uiView.onDictationPhrase = { [weak uiView] phrase in
            guard let uiView else { return false }
            return context.coordinator.acceptDictation(phrase, in: uiView)
        }
        if nodeChrome == nil {
            if let paper {
                uiView.backgroundColor = UIColor(paper)
            }
            if let ink {
                uiView.textColor = UIColor(ink)
                uiView.tintColor = UIColor(ink)
            }
        }
        uiView.onMarkedTextChange = { [weak uiView] in
            guard let uiView else { return }
            context.coordinator.compositionChanged(uiView)
        }
        if uiView.markedTextRange == nil, !context.coordinator.isComposing.wrappedValue {
            if let nodeChrome {
                assignEditingFont(nodeChrome, familyID: fontFamilyID, to: uiView)
            } else {
                assignEditingFont(
                    signature: EditingFontSignature(
                        familyID: fontFamilyID,
                        design: "default",
                        size: max(fontSize, 1),
                        bold: false,
                        italic: false
                    ),
                    font: ThemeFontCascade.platformFont(familyID: fontFamilyID, nodeDesign: "default", size: fontSize),
                    to: uiView
                )
            }
            if uiView.text != text, !ownsKeys {
                uiView.text = text
                if let nodeChrome {
                    applyNodeChrome(nodeChrome, to: uiView, ownsKeys: false)
                }
            }
        }
        if !context.coordinator.didFocus {
            DispatchQueue.main.async { [weak uiView] in
                guard let uiView else { return }
                if !uiView.isFirstResponder {
                    uiView.becomeFirstResponder()
                }
                context.coordinator.didFocus = uiView.isFirstResponder
                context.coordinator.noteDictation(on: uiView)
            }
        } else {
            context.coordinator.noteDictation(on: uiView)
        }
    }

    /// Focus must not swap the topic for the system text background or font.
    private func applyNodeChrome(_ chrome: NodeEditSurface, to view: FlorettaTextView, ownsKeys: Bool) {
        let fill = UIColor(
            red: CGFloat(chrome.fill.red),
            green: CGFloat(chrome.fill.green),
            blue: CGFloat(chrome.fill.blue),
            alpha: chrome.hidesFill ? 0 : 1
        )
        let ink = UIColor(
            red: CGFloat(chrome.textColor.red),
            green: CGFloat(chrome.textColor.green),
            blue: CGFloat(chrome.textColor.blue),
            alpha: 1
        )
        view.lockedBackground = fill
        view.lockedTextColor = ink
        view.locksChrome = true
        view.centersInNode = true
        view.backgroundColor = fill
        view.textColor = ink
        view.tintColor = ink
        view.isOpaque = !chrome.hidesFill
        assignEditingFont(chrome, familyID: fontFamilyID, to: view)
        view.clipsToBounds = true
        view.layer.cornerRadius = chrome.cornerRadius
        view.layer.borderWidth = 0
        view.textContainer.lineFragmentPadding = 0
        let style = NodeTextTypography.paragraphStyle()
        if (view.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.alignment != .center {
            var typing = view.typingAttributes
            typing[.paragraphStyle] = style
            view.typingAttributes = typing
        }
        if view.markedTextRange == nil, view.textStorage.length > 0, storageNeedsCenteredParagraph(view.textStorage) {
            view.textStorage.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: view.textStorage.length))
        }
        if !ownsKeys, view.textAlignment != .center {
            view.textAlignment = .center
        }
        view.publishChromeProbe()
    }

    private func assignEditingFont(_ chrome: NodeEditSurface, familyID: String, to view: FlorettaTextView) {
        assignEditingFont(
            signature: EditingFontSignature(
                familyID: familyID,
                design: chrome.fontDesign,
                size: max(chrome.fontSize, 1),
                bold: chrome.bold,
                italic: chrome.italic
            ),
            font: Self.editingFont(chrome, familyID: familyID),
            to: view
        )
    }

    private func assignEditingFont(signature: EditingFontSignature, font: UIFont, to view: FlorettaTextView) {
        guard EditorLayoutConvergence.shouldAssignFont(requested: signature, lastAssigned: view.appliedFontSignature) else {
            return
        }
        view.appliedFontSignature = signature
        view.lockedFont = font
        if view.font != font {
            view.font = font
        }
    }

    private func storageNeedsCenteredParagraph(_ storage: NSTextStorage) -> Bool {
        guard let style = storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle else {
            return true
        }
        return style.alignment != .center || style.lineBreakMode != .byWordWrapping
    }

    private static func editingFont(_ chrome: NodeEditSurface, familyID: String) -> UIFont {
        let size = max(chrome.fontSize, 1)
        var font = ThemeFontCascade.platformFont(familyID: familyID, nodeDesign: chrome.fontDesign, size: size)
        if chrome.bold {
            var traits = font.fontDescriptor.symbolicTraits
            traits.insert(.traitBold)
            if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
                font = UIFont(descriptor: descriptor, size: size)
            }
        }
        if chrome.italic {
            var traits = font.fontDescriptor.symbolicTraits
            traits.insert(.traitItalic)
            if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
                font = UIFont(descriptor: descriptor, size: size)
            }
        }
        return font
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        var isComposing: Binding<Bool>
        var minimumWidth: Binding<CGFloat>
        var fontSize: CGFloat
        var fontMetrics: any FontMetricsPort
        var onEvent: (KeyEvent) -> Bool
        var returnInsertsLine: Bool
        var dictationToken: Int
        var dictationReplacesPlaceholder: Bool
        var didFocus = false
        private var handledDictationToken = 0

        init(
            text: Binding<String>,
            isComposing: Binding<Bool>,
            minimumWidth: Binding<CGFloat>,
            fontSize: CGFloat,
            fontMetrics: any FontMetricsPort,
            onEvent: @escaping (KeyEvent) -> Bool,
            returnInsertsLine: Bool,
            dictationToken: Int,
            dictationReplacesPlaceholder: Bool
        ) {
            self.text = text
            self.isComposing = isComposing
            self.minimumWidth = minimumWidth
            self.fontSize = fontSize
            self.fontMetrics = fontMetrics
            self.onEvent = onEvent
            self.returnInsertsLine = returnInsertsLine
            self.dictationToken = dictationToken
            self.dictationReplacesPlaceholder = dictationReplacesPlaceholder
        }

        /// Select the new-topic placeholder, then start system dictation.
        func noteDictation(on view: UITextView) {
            guard dictationToken != 0, dictationToken != handledDictationToken else { return }
            guard view.isFirstResponder else { return }
            handledDictationToken = dictationToken
            if dictationReplacesPlaceholder {
                let length = (view.text as NSString?)?.length ?? 0
                view.selectedRange = NSRange(location: 0, length: length)
            }
            SystemDictation.begin(on: view)
        }

        /// System dictation delivers a phrase. Write it with the same insertion
        /// rule typed text uses, then show that string in the field.
        func acceptDictation(_ phrase: String, in view: UITextView) -> Bool {
            let existing = view.text ?? ""
            let nsLength = (existing as NSString).length
            let selected = view.selectedRange
            guard selected.location >= 0,
                  selected.length >= 0,
                  selected.location <= nsLength,
                  selected.length <= nsLength - selected.location
            else {
                return false
            }
            let selection = selected.location..<(selected.location + selected.length)
            let replacing = dictationReplacesPlaceholder && existing == MindMapKeyboardSession.newTopicText
            guard let next = DictationNodeInput.inserted(
                existing: existing,
                phrase: phrase,
                utf16Selection: selection,
                replacesPlaceholder: replacing
            ) else {
                return false
            }
            if text.wrappedValue != next {
                text.wrappedValue = next
            }
            if view.text != next {
                view.text = next
            }
            let end = (next as NSString).length
            view.selectedRange = NSRange(location: end, length: 0)
            dictationReplacesPlaceholder = false
            return true
        }

        func compositionChanged(_ view: UITextView) {
            let composing = view.markedTextRange != nil
            isComposing.wrappedValue = composing
            let value = view.text ?? ""
            if value != text.wrappedValue {
                text.wrappedValue = value
            }
            if composing {
                let font = view.font ?? UIFont.systemFont(ofSize: max(fontSize, 1))
                let width = CGFloat(fontMetrics.measure(text: value, fontName: font.fontName, fontSize: font.pointSize, maxWidth: nil).width) + 24
                minimumWidth.wrappedValue = width
            } else {
                minimumWidth.wrappedValue = 0
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            compositionChanged(textView)
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText string: String) -> Bool {
            _ = range
            let composing = textView.markedTextRange != nil
            isComposing.wrappedValue = composing
            guard string == "\n" else { return true }
            if returnInsertsLine { return true }
            let event = KeyEvent(key: .enter, modifiers: [], mode: .edit, isComposing: composing)
            return !onEvent(event)
        }
    }
}

private final class FlorettaTextView: UITextView {
    var onEvent: ((KeyEvent) -> Bool)?
    var onMarkedTextChange: (() -> Void)?
    /// Return true when the phrase was written into the topic. False lets the
    /// system text view insert it the way it inserts typed characters.
    var onDictationPhrase: ((String) -> Bool)?
    var returnInsertsLine = false
    var locksChrome = false
    var centersInNode = false
    var lockedBackground: UIColor = .clear
    var lockedTextColor: UIColor = .label
    var lockedFont: UIFont?
    var appliedFontSignature: EditingFontSignature?
    var centeringPass = TextCenteringPass.idle
    private var applyingChrome = false

    override var backgroundColor: UIColor? {
        get { super.backgroundColor }
        set { super.backgroundColor = locksChrome ? lockedBackground : newValue }
    }

    override var textColor: UIColor? {
        get { super.textColor }
        set { super.textColor = locksChrome ? lockedTextColor : newValue }
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        guard locksChrome else { return ok }
        super.backgroundColor = lockedBackground
        super.textColor = lockedTextColor
        if let lockedFont, font != lockedFont {
            font = lockedFont
        }
        tintColor = lockedTextColor
        return ok
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard centersInNode, !applyingChrome else {
            publishChromeProbe()
            return
        }
        guard centeringPass.shouldApply(to: bounds.size, text: text) else {
            publishChromeProbe()
            return
        }
        centeringPass = TextCenteringPass(bounds: bounds.size, text: text)
        let font = self.font ?? UIFont.systemFont(ofSize: 12)
        let glyphHeight = EditorTextCenteringMeasurement.glyphHeight(
            font: font,
            layoutManager: layoutManager,
            textContainer: textContainer,
            previousVerticalInset: textContainerInset.top
        )
        let vertical = EditorLayoutConvergence.centeredVerticalInset(
            boundsHeight: bounds.height,
            glyphHeight: glyphHeight
        )
        let next = UIEdgeInsets(
            top: vertical,
            left: NodeEditChrome.textInset.width,
            bottom: vertical,
            right: NodeEditChrome.textInset.width
        )
        let current = textContainerInset
        if EditorLayoutConvergence.shouldWriteVerticalInset(current: current.top, proposed: vertical)
            || abs(current.left - next.left) > 0.5 {
            applyingChrome = true
            textContainerInset = next
            applyingChrome = false
        }
        publishChromeProbe()
    }

    func publishChromeProbe() {
        guard locksChrome, bounds.width > 1, bounds.height > 1 else { return }
        let source = backgroundColor ?? lockedBackground
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        let fill: BranchColor
        if source.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            fill = BranchColor(red: Double(red), green: Double(green), blue: Double(blue))
        } else {
            fill = BranchColor(red: 1, green: 1, blue: 1)
        }
        let value = NodeEditChrome.accessibilityValue(editing: true, fill: fill, size: bounds.size)
        accessibilityIdentifier = NodeEditChrome.accessibilityIdentifier
        accessibilityLabel = "node"
        if (accessibilityValue as? String) != value {
            accessibilityValue = value
        }
    }

    override func insertDictationResult(_ dictationResult: [UIDictationPhrase]) {
        let phrase = dictationResult.map(\.text).joined()
        if onDictationPhrase?(phrase) == true {
            return
        }
        super.insertDictationResult(dictationResult)
    }

    override func setMarkedText(_ markedText: String?, selectedRange: NSRange) {
        super.setMarkedText(markedText, selectedRange: selectedRange)
        onMarkedTextChange?()
    }

    override func unmarkText() {
        super.unmarkText()
        onMarkedTextChange?()
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let composing = markedTextRange != nil
        if let key = presses.first?.key, let mapped = KeyEvent(uiKey: key, isComposing: composing) {
            if NodeEditLineBreak.textViewInsertsLine(for: mapped) {
                super.pressesBegan(presses, with: event)
                return
            }
            if returnInsertsLine, mapped.key == .enter, !mapped.modifiers.contains(.command) {
                super.pressesBegan(presses, with: event)
                return
            }
            if returnInsertsLine, mapped.key == .enter, mapped.modifiers.contains(.command) {
                var commit = mapped
                commit.modifiers = []
                if onEvent?(commit) == true { return }
            }
            if onEvent?(mapped) == true || mapped.key == .tab {
                return
            }
        }
        super.pressesBegan(presses, with: event)
    }
}

private extension KeyEvent {
    init?(uiKey: UIKey, isComposing: Bool) {
        var modifiers = KeyModifiers()
        if uiKey.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        if uiKey.modifierFlags.contains(.command) { modifiers.insert(.command) }
        if uiKey.modifierFlags.contains(.alternate) { modifiers.insert(.option) }
        if uiKey.modifierFlags.contains(.control) { modifiers.insert(.control) }
        let key: KeyToken
        switch uiKey.keyCode {
        case .keyboardTab:
            key = .tab
        case .keyboardReturnOrEnter, .keypadEnter:
            key = .enter
        case .keyboardEscape:
            key = .escape
        case .keyboardDeleteOrBackspace:
            key = .backspace
        case .keyboardUpArrow:
            key = .up
        case .keyboardDownArrow:
            key = .down
        case .keyboardLeftArrow:
            key = .left
        case .keyboardRightArrow:
            key = .right
        case .keyboardSpacebar:
            key = .space
        case .keyboardZ:
            key = .character("z")
        default:
            if uiKey.charactersIgnoringModifiers == "\u{F728}" {
                key = .delete
            } else {
                return nil
            }
        }
        self.init(key: key, modifiers: modifiers, mode: .edit, isComposing: isComposing)
    }
}
#endif

/// Collapses a physical key that SwiftUI `onKeyPress` and `UIKeyCommand` both
/// deliver, so one press cannot insert two siblings.
@MainActor
final class KeyDeliveryCoalescer {
    private var last: (KeyEvent, TimeInterval)?

    func shouldApply(_ event: KeyEvent) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        if let last, last.0 == event, now - last.1 < 0.05 {
            return false
        }
        self.last = (event, now)
        return true
    }
}

enum MindMapKeyDispatch {
    @MainActor
    static func handle(
        _ event: KeyEvent,
        keyboard: inout MindMapKeyboardSession,
        document: inout MindMapDocument,
        frames: [NodeFrame],
        surface: KeyboardSurface = .canvas,
        coalescer: KeyDeliveryCoalescer? = nil,
        onChrome: (MindMapCommand) -> Void = { _ in }
    ) -> Bool {
        if let coalescer, !coalescer.shouldApply(event) {
            return true
        }
        let command = keyboard.handle(event, document: &document, frames: frames, surface: surface)
        guard let command else { return false }
        switch command {
        case .openProperties, .showShortcutHelp, .jumpToCentralTopic:
            onChrome(command)
        default:
            break
        }
        return true
    }
}

#if os(iOS)
/// Hardware-keyboard commands for iPad. `canPerformAction` refuses single-key
/// shortcuts while a text field is focused or IME composition is active.
struct HardwareShortcutHost: UIViewRepresentable {
    var mode: KeyboardMode
    var isComposing: Bool
    var isEnabled: Bool
    var coalescer: KeyDeliveryCoalescer
    var onEvent: (KeyEvent) -> Bool

    func makeCoordinator() -> HardwareShortcutView {
        HardwareShortcutView()
    }

    func makeUIView(context: Context) -> HardwareShortcutView {
        let view = context.coordinator
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        apply(view)
        return view
    }

    func updateUIView(_ uiView: HardwareShortcutView, context: Context) {
        apply(uiView)
        if isEnabled, mode == .command, !isComposing {
            uiView.claimFirstResponder()
        } else {
            uiView.resignIfFirstResponder()
        }
    }

    private func apply(_ view: HardwareShortcutView) {
        view.mode = mode
        view.isComposing = isComposing
        view.coalescer = coalescer
        view.onEvent = onEvent
    }
}

final class HardwareShortcutView: UIView {
    var mode: KeyboardMode = .command
    var isComposing = false
    var coalescer: KeyDeliveryCoalescer?
    var onEvent: ((KeyEvent) -> Bool)?

    override var canBecomeFirstResponder: Bool { true }

    func claimFirstResponder() {
        if !isFirstResponder {
            _ = becomeFirstResponder()
        }
    }

    func resignIfFirstResponder() {
        if isFirstResponder {
            _ = resignFirstResponder()
        }
    }

    override var keyCommands: [UIKeyCommand]? {
        HardwareShortcutCatalog.commands(action: #selector(performHardwareShortcut(_:)))
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        guard action == #selector(performHardwareShortcut(_:)) else {
            return super.canPerformAction(action, withSender: sender)
        }
        guard let keyCommand = sender as? UIKeyCommand,
              let event = KeyEvent(keyCommand: keyCommand, mode: mode, isComposing: isComposing) else {
            return false
        }
        if isComposing { return false }
        if mode == .edit, HardwareShortcutCatalog.isSingleKey(keyCommand) { return false }
        return KeyboardCommandMapper.map(event) != nil
    }

    @objc func performHardwareShortcut(_ sender: UIKeyCommand) {
        guard let event = KeyEvent(keyCommand: sender, mode: mode, isComposing: isComposing) else { return }
        _ = onEvent?(event)
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if let key = presses.first?.key, let mapped = KeyEvent(uiKey: key, isComposing: isComposing, mode: mode) {
            if KeyboardCommandMapper.map(mapped) != nil, onEvent?(mapped) == true {
                return
            }
        }
        super.pressesBegan(presses, with: event)
    }
}

enum HardwareShortcutCatalog {
    static func commands(action: Selector) -> [UIKeyCommand] {
        bindings.map { input, flags, title in
            let command = UIKeyCommand(title: title, action: action, input: input, modifierFlags: flags)
            command.wantsPriorityOverSystemBehavior = true
            command.discoverabilityTitle = title
            return command
        }
    }

    static func isSingleKey(_ command: UIKeyCommand) -> Bool {
        let flags = command.modifierFlags.intersection([.command, .alternate, .control])
        return flags.isEmpty
    }

    private static var bindings: [(String, UIKeyModifierFlags, String)] {
        [
            (" ", [], "编辑主题"),
            ("\r", [], "新建同级"),
            ("\t", [], "新建子级"),
            ("\r", .shift, "新建同级（前）"),
            ("\r", .command, "新建父级"),
            ("\r", .alternate, "属性"),
            ("a", [.command, .shift], "全选同级"),
            ("a", [.command, .alternate], "全选子级"),
            ("a", .command, "全选主题"),
            ("r", .command, "跳到中心主题"),
            ("y", .command, "重做"),
            ("l", [.command, .shift], "快捷键一览"),
            ("+", [], "展开分支"),
            ("-", [], "收起分支"),
            ("*", [], "展开全部"),
            ("/", [], "收起全部"),
            (UIKeyCommand.inputUpArrow, .alternate, "上移主题"),
            (UIKeyCommand.inputDownArrow, .alternate, "下移主题"),
        ]
    }
}

private extension KeyEvent {
    init?(keyCommand: UIKeyCommand, mode: KeyboardMode, isComposing: Bool) {
        guard let input = keyCommand.input else { return nil }
        var modifiers = KeyModifiers()
        if keyCommand.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        if keyCommand.modifierFlags.contains(.command) { modifiers.insert(.command) }
        if keyCommand.modifierFlags.contains(.alternate) { modifiers.insert(.option) }
        if keyCommand.modifierFlags.contains(.control) { modifiers.insert(.control) }
        let key: KeyToken
        switch input {
        case "\t":
            key = .tab
        case "\r", "\n":
            key = .enter
        case " ":
            key = .space
        case UIKeyCommand.inputEscape:
            key = .escape
        case UIKeyCommand.inputUpArrow:
            key = .up
        case UIKeyCommand.inputDownArrow:
            key = .down
        case UIKeyCommand.inputLeftArrow:
            key = .left
        case UIKeyCommand.inputRightArrow:
            key = .right
        default:
            if let mapped = KeyEvent.mappedCharacter(input) {
                key = mapped
            } else {
                return nil
            }
        }
        self.init(key: key, modifiers: modifiers, mode: mode, isComposing: isComposing)
    }

    init?(uiKey: UIKey, isComposing: Bool, mode: KeyboardMode) {
        var modifiers = KeyModifiers()
        if uiKey.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        if uiKey.modifierFlags.contains(.command) { modifiers.insert(.command) }
        if uiKey.modifierFlags.contains(.alternate) { modifiers.insert(.option) }
        if uiKey.modifierFlags.contains(.control) { modifiers.insert(.control) }
        let key: KeyToken
        switch uiKey.keyCode {
        case .keyboardTab:
            key = .tab
        case .keyboardReturnOrEnter, .keypadEnter:
            key = .enter
        case .keyboardEscape:
            key = .escape
        case .keyboardDeleteOrBackspace:
            key = .backspace
        case .keyboardUpArrow:
            key = .up
        case .keyboardDownArrow:
            key = .down
        case .keyboardLeftArrow:
            key = .left
        case .keyboardRightArrow:
            key = .right
        case .keyboardSpacebar:
            key = .space
        case .keyboardF2:
            key = .f2
        case .keyboardF5:
            key = .f5
        default:
            if let mapped = KeyEvent.mappedCharacter(uiKey.characters) {
                key = mapped
            } else if uiKey.charactersIgnoringModifiers == "\u{F728}" {
                key = .delete
            } else {
                return nil
            }
        }
        self.init(key: key, modifiers: modifiers, mode: mode, isComposing: isComposing)
    }
}
#endif

/// Shift+Enter belongs to the focused text view so the break lands at the caret.
enum NodeEditLineBreak {
    static func textViewInsertsLine(for event: KeyEvent) -> Bool {
        event.key == .enter && event.modifiers.contains(.shift)
    }
}
