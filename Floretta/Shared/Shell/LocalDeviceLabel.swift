import Foundation
#if os(iOS)
import UIKit
#endif

/// Sidebar and browser title for this device's local documents folder.
struct LocalDeviceLabel: Equatable, Sendable {
    var title: String
    var systemImage: String

    static func make(for kind: Kind) -> LocalDeviceLabel {
        switch kind {
        case .iPhone:
            return LocalDeviceLabel(title: "我的 iPhone", systemImage: "iphone")
        case .iPad:
            return LocalDeviceLabel(title: "我的 iPad", systemImage: "ipad")
        case .mac:
            return LocalDeviceLabel(title: "我的 Mac", systemImage: "macbook")
        }
    }

    static var current: LocalDeviceLabel {
        make(for: currentKind)
    }

    static var currentKind: Kind {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone ? .iPhone : .iPad
        #elseif os(macOS)
        return .mac
        #else
        return .mac
        #endif
    }

    enum Kind: Equatable, Sendable {
        case iPhone
        case iPad
        case mac
    }
}
