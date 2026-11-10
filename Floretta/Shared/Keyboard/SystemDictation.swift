import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Starts the system keyboard dictation already on this device.
///
/// macOS sends `startDictation:`, the same action as the system Edit menu.
/// iOS sends that keyboard action to the text view, and otherwise leaves the
/// system keyboard's microphone key as the way to dictate. This type does not
/// open the microphone, store audio, or load a speech model.
enum SystemDictation {
    static let startSelector = Selector(("startDictation:"))

    #if os(macOS)
    @discardableResult
    static func begin(on responder: NSResponder?) -> Bool {
        guard let responder, responder.responds(to: startSelector) else { return false }
        responder.perform(startSelector, with: nil)
        return true
    }
    #else
    @discardableResult
    static func begin(on responder: UIResponder?) -> Bool {
        guard let responder else { return false }
        if responder.responds(to: startSelector) {
            responder.perform(startSelector, with: nil)
            return true
        }
        return UIApplication.shared.sendAction(startSelector, to: nil, from: responder, for: nil)
    }
    #endif
}
