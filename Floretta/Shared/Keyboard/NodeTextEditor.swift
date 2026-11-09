import FlorettaCore
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

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
        } else if press.characters.lowercased() == "z" {
            key = .character("z")
        } else {
            return nil
        }
        self.init(key: key, modifiers: modifiers, mode: mode, isComposing: isComposing)
    }
}

/// System text view over the node being edited. Shortcuts go through `KeyboardCommandMapper`.
/// Tab in edit mode is swallowed here so it neither creates a node nor moves focus.
struct NodeTextEditor: View {
    @Binding var text: String
    @Binding var isComposing: Bool
    @Binding var minimumWidth: CGFloat
    var fontSize: CGFloat
    var onEvent: (KeyEvent) -> Bool

    var body: some View {
        #if os(macOS)
        MacNodeTextEditor(
            text: $text,
            isComposing: $isComposing,
            minimumWidth: $minimumWidth,
            fontSize: fontSize,
            onEvent: onEvent
        )
        #else
        IOSNodeTextEditor(
            text: $text,
            isComposing: $isComposing,
            minimumWidth: $minimumWidth,
            fontSize: fontSize,
            onEvent: onEvent
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
    var onEvent: (KeyEvent) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            isComposing: $isComposing,
            minimumWidth: $minimumWidth,
            fontSize: fontSize,
            onEvent: onEvent
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
        view.backgroundColor = .textBackgroundColor
        view.textColor = .labelColor
        view.font = .systemFont(ofSize: max(fontSize, 1))
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
        nsView.onMarkedTextChange = { [weak nsView] in
            guard let nsView else { return }
            context.coordinator.compositionChanged(nsView)
        }
        if !nsView.hasMarkedText() {
            let font = NSFont.systemFont(ofSize: max(fontSize, 1))
            if nsView.font?.pointSize != font.pointSize {
                nsView.font = font
            }
            let ownsKeys = nsView.window?.firstResponder === nsView
            if nsView.string != text, !ownsKeys {
                nsView.string = text
            }
        }
        if !context.coordinator.didFocus {
            DispatchQueue.main.async { [weak nsView] in
                guard let nsView, let window = nsView.window else { return }
                if window.firstResponder !== nsView {
                    window.makeFirstResponder(nsView)
                }
                context.coordinator.didFocus = window.firstResponder === nsView
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var isComposing: Binding<Bool>
        var minimumWidth: Binding<CGFloat>
        var fontSize: CGFloat
        var onEvent: (KeyEvent) -> Bool
        var didFocus = false

        init(
            text: Binding<String>,
            isComposing: Binding<Bool>,
            minimumWidth: Binding<CGFloat>,
            fontSize: CGFloat,
            onEvent: @escaping (KeyEvent) -> Bool
        ) {
            self.text = text
            self.isComposing = isComposing
            self.minimumWidth = minimumWidth
            self.fontSize = fontSize
            self.onEvent = onEvent
        }

        func compositionChanged(_ view: NSTextView) {
            let composing = view.hasMarkedText()
            isComposing.wrappedValue = composing
            if view.string != text.wrappedValue {
                text.wrappedValue = view.string
            }
            if composing {
                let font = view.font ?? NSFont.systemFont(ofSize: max(fontSize, 1))
                let width = (view.string as NSString).size(withAttributes: [.font: font]).width + 24
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
    var onEvent: (KeyEvent) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            isComposing: $isComposing,
            minimumWidth: $minimumWidth,
            fontSize: fontSize,
            onEvent: onEvent
        )
    }

    func makeUIView(context: Context) -> FlorettaTextView {
        let view = FlorettaTextView()
        view.delegate = context.coordinator
        view.font = .systemFont(ofSize: max(fontSize, 1))
        view.backgroundColor = .systemBackground
        view.textColor = .label
        view.isScrollEnabled = false
        view.autocorrectionType = .no
        view.spellCheckingType = .no
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.smartInsertDeleteType = .no
        view.text = text
        view.onEvent = onEvent
        view.onMarkedTextChange = { [weak view] in
            guard let view else { return }
            context.coordinator.compositionChanged(view)
        }
        return view
    }

    func updateUIView(_ uiView: FlorettaTextView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.isComposing = $isComposing
        context.coordinator.minimumWidth = $minimumWidth
        context.coordinator.fontSize = fontSize
        context.coordinator.onEvent = onEvent
        uiView.onEvent = onEvent
        uiView.onMarkedTextChange = { [weak uiView] in
            guard let uiView else { return }
            context.coordinator.compositionChanged(uiView)
        }
        if uiView.markedTextRange == nil {
            let font = UIFont.systemFont(ofSize: max(fontSize, 1))
            if uiView.font?.pointSize != font.pointSize {
                uiView.font = font
            }
            if uiView.text != text, !uiView.isFirstResponder {
                uiView.text = text
            }
        }
        if !context.coordinator.didFocus {
            DispatchQueue.main.async { [weak uiView] in
                guard let uiView else { return }
                if !uiView.isFirstResponder {
                    uiView.becomeFirstResponder()
                }
                context.coordinator.didFocus = uiView.isFirstResponder
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        var isComposing: Binding<Bool>
        var minimumWidth: Binding<CGFloat>
        var fontSize: CGFloat
        var onEvent: (KeyEvent) -> Bool
        var didFocus = false

        init(
            text: Binding<String>,
            isComposing: Binding<Bool>,
            minimumWidth: Binding<CGFloat>,
            fontSize: CGFloat,
            onEvent: @escaping (KeyEvent) -> Bool
        ) {
            self.text = text
            self.isComposing = isComposing
            self.minimumWidth = minimumWidth
            self.fontSize = fontSize
            self.onEvent = onEvent
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
                let width = (value as NSString).size(withAttributes: [.font: font]).width + 24
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
            let event = KeyEvent(key: .enter, modifiers: [], mode: .edit, isComposing: composing)
            return !onEvent(event)
        }
    }
}

private final class FlorettaTextView: UITextView {
    var onEvent: ((KeyEvent) -> Bool)?
    var onMarkedTextChange: (() -> Void)?

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
