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
    var onEvent: (KeyEvent) -> Bool

    var body: some View {
        #if os(macOS)
        MacNodeTextEditor(text: $text, isComposing: $isComposing, onEvent: onEvent)
        #else
        IOSNodeTextEditor(text: $text, isComposing: $isComposing, onEvent: onEvent)
        #endif
    }
}

#if os(macOS)
private struct MacNodeTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var isComposing: Bool
    var onEvent: (KeyEvent) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isComposing: $isComposing, onEvent: onEvent)
    }

    func makeNSView(context: Context) -> NSTextView {
        let view = NSTextView()
        view.delegate = context.coordinator
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.isEditable = true
        view.isSelectable = true
        view.drawsBackground = true
        view.backgroundColor = .textBackgroundColor
        view.textColor = .labelColor
        view.font = .systemFont(ofSize: NSFont.systemFontSize)
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.textContainer?.widthTracksTextView = true
        view.string = text
        return view
    }

    func updateNSView(_ nsView: NSTextView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.isComposing = $isComposing
        context.coordinator.onEvent = onEvent
        if !nsView.hasMarkedText(), nsView.string != text {
            nsView.string = text
        }
        if nsView.window?.firstResponder !== nsView {
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var isComposing: Binding<Bool>
        var onEvent: (KeyEvent) -> Bool

        init(text: Binding<String>, isComposing: Binding<Bool>, onEvent: @escaping (KeyEvent) -> Bool) {
            self.text = text
            self.isComposing = isComposing
            self.onEvent = onEvent
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            text.wrappedValue = view.string
            isComposing.wrappedValue = view.hasMarkedText()
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
    var onEvent: (KeyEvent) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isComposing: $isComposing, onEvent: onEvent)
    }

    func makeUIView(context: Context) -> FlorettaTextView {
        let view = FlorettaTextView()
        view.delegate = context.coordinator
        view.font = .preferredFont(forTextStyle: .body)
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
        return view
    }

    func updateUIView(_ uiView: FlorettaTextView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.isComposing = $isComposing
        context.coordinator.onEvent = onEvent
        uiView.onEvent = onEvent
        if uiView.markedTextRange == nil, uiView.text != text {
            uiView.text = text
        }
        if !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        }
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        var isComposing: Binding<Bool>
        var onEvent: (KeyEvent) -> Bool

        init(text: Binding<String>, isComposing: Binding<Bool>, onEvent: @escaping (KeyEvent) -> Bool) {
            self.text = text
            self.isComposing = isComposing
            self.onEvent = onEvent
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text ?? ""
            isComposing.wrappedValue = textView.markedTextRange != nil
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
        case .keyboardReturnOrEnter, .keyboardKeypadEnter:
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
