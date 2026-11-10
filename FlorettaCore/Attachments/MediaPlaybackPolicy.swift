import Foundation

/// A small ownership registry shared by media surfaces. Replacing the active owner always
/// tears down its player first; callers release their lease when a player is dismissed.
@MainActor
public final class MediaPlaybackRegistry {
    public static let shared = MediaPlaybackRegistry()

    private var activeID: UUID?
    private var stopActive: (() -> Void)?

    public init() {}

    public func acquire(stop: @escaping () -> Void) -> UUID {
        stopActive?()
        let id = UUID()
        activeID = id
        stopActive = stop
        return id
    }

    public func release(_ id: UUID) {
        guard activeID == id else { return }
        let stop = stopActive
        activeID = nil
        stopActive = nil
        stop?()
    }

    public var hasActivePlayer: Bool { activeID != nil }
}

public enum MediaFileAvailability: Equatable, Sendable {
    case available
    case missing
    case unreadable

    public static func state(fileExists: Bool, isReadable: Bool) -> MediaFileAvailability {
        guard fileExists else { return .missing }
        return isReadable ? .available : .unreadable
    }
}
