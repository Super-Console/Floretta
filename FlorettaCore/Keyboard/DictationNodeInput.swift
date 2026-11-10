import Foundation

/// Turns text the system has already dictated into a topic edit.
///
/// Callers pass a `String` from keyboard dictation. This type does not record
/// audio, open a microphone, or load a speech model. A new phrase in command
/// mode creates one child through the same command as Tab, then replaces the
/// placeholder the way a selected title is replaced by typing. An editor that
/// is already open keeps that object and inserts the phrase the way typed text does.
public enum DictationNodeInput {
    /// Where the dictated phrase landed.
    public enum Target: Equatable, Sendable {
        /// A child was created and is the editor. Its title is the phrase.
        case newChild(UUID)
        /// The phrase was written into the editor that was already open.
        case currentEditor(UUID)
        case unavailable
    }

    public struct Preparation: Equatable, Sendable {
        public var target: Target
        /// True when the new child's placeholder should be replaced, not appended to.
        public var replacesPlaceholder: Bool

        public static let unavailable = Preparation(target: .unavailable, replacesPlaceholder: false)
    }

    /// Opens an editor for system dictation. Does not invent text.
    /// Command mode with an ordinary topic creates one child and starts editing it.
    /// An open editor, a free topic, or a sticky stays on that text.
    public static func prepare(
        session: inout MindMapKeyboardSession,
        document: inout MindMapDocument
    ) -> Preparation {
        if session.isComposing {
            return .unavailable
        }
        if session.mode == .edit {
            guard let id = currentEditorID(session) else { return .unavailable }
            return Preparation(target: .currentEditor(id), replacesPlaceholder: false)
        }
        if let parentID = session.selectedNodeID,
           document.node(parentID) != nil,
           !document.isInFreeNodeTree(parentID) {
            session.apply(.createChild, document: &document, frames: [])
            guard session.mode == .edit,
                  let childID = session.selectedNodeID,
                  childID != parentID,
                  document.node(childID) != nil
            else {
                return .unavailable
            }
            return Preparation(target: .newChild(childID), replacesPlaceholder: true)
        }
        session.apply(.beginEdit, document: &document, frames: [])
        guard session.mode == .edit, let id = currentEditorID(session) else {
            return .unavailable
        }
        return Preparation(target: .currentEditor(id), replacesPlaceholder: false)
    }

    /// The field text after the system inserts `phrase` over a UTF-16 selection.
    /// `nil` when `phrase` is empty, so a blank result does not change the field.
    /// A new-child placeholder is replaced wholesale. Any other selection is
    /// replaced the way an ordinary insertion replaces it. No selection appends.
    public static func inserted(
        existing: String,
        phrase: String,
        utf16Selection: Range<Int>?,
        replacesPlaceholder: Bool,
        placeholder: String = MindMapKeyboardSession.newTopicText
    ) -> String? {
        if phrase.isEmpty { return nil }
        if replacesPlaceholder, existing == placeholder {
            return phrase
        }
        guard let utf16Selection, utf16Selection.lowerBound >= 0 else {
            return existing + phrase
        }
        let location = utf16Selection.lowerBound
        let length = utf16Selection.count
        let ns = existing as NSString
        guard location <= ns.length, length >= 0, location + length <= ns.length else {
            return existing + phrase
        }
        return ns.replacingCharacters(in: NSRange(location: location, length: length), with: phrase)
    }

    /// Creates or edits one topic from a finished dictation phrase.
    /// Blank speech in command mode does not create a topic. Marked text is left alone.
    @discardableResult
    public static func apply(
        phrase: String,
        session: inout MindMapKeyboardSession,
        document: inout MindMapDocument
    ) -> Preparation {
        if session.isComposing || phrase.isEmpty {
            return .unavailable
        }
        if session.mode == .command,
           phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .unavailable
        }
        let preparation = prepare(session: &session, document: &document)
        guard preparation.target != .unavailable else { return preparation }
        let selection: Range<Int>?
        if preparation.replacesPlaceholder {
            selection = 0..<(session.editingText as NSString).length
        } else {
            selection = nil
        }
        guard let next = inserted(
            existing: session.editingText,
            phrase: phrase,
            utf16Selection: selection,
            replacesPlaceholder: preparation.replacesPlaceholder
        ) else {
            return preparation
        }
        session.replaceEditingText(next, document: &document)
        return preparation
    }

    private static func currentEditorID(_ session: MindMapKeyboardSession) -> UUID? {
        if let id = session.editingRelationshipID { return id }
        if let id = session.editingSummaryID { return id }
        if let id = session.editingBoundaryID { return id }
        if let id = session.selectedStickyID { return id }
        return session.selectedNodeID
    }
}
