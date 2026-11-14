public enum ThemeMode: String, CaseIterable, Codable, Sendable {
    case classic
    case modern
    case custom

    public static let `default`: ThemeMode = .classic

    public var displayKey: String {
        switch self {
        case .classic: "经典模式"
        case .modern: "现代模式"
        case .custom: "自定义"
        }
    }
}
