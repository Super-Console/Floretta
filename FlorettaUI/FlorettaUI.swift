import Foundation
import FlorettaCore

/// SwiftUI views move here in a later step. This target depends on Core so the
/// dependency direction is fixed before any view is relocated.
public enum FlorettaUILayer {
    public static let name = "FlorettaUI"

    public static func now(clock: any ClockPort) -> Date {
        clock.now()
    }
}
