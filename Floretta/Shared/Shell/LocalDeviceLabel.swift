import Foundation
import FlorettaCore

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
        #if os(macOS)
        return currentKind(using: ApplePlatformPorts.current().device, isMacOS: true)
        #else
        return currentKind(using: ApplePlatformPorts.current().device, isMacOS: false)
        #endif
    }

    static func currentKind(using device: any DeviceInfoPort, isMacOS: Bool) -> Kind {
        if isMacOS { return .mac }
        return device.isPhone ? .iPhone : .iPad
    }

    enum Kind: Equatable, Sendable {
        case iPhone
        case iPad
        case mac
    }
}
