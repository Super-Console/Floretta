public enum ThemeTextRole: Sendable {
    case title
    case body
    case caption
}

public enum ThemeScript: Sendable {
    case cjk
    case latin
}

public struct ThemeFontSpec: Equatable, Sendable {
    public let familyCandidates: [String]
    public let isSerif: Bool

    public init(familyCandidates: [String], isSerif: Bool) {
        self.familyCandidates = familyCandidates
        self.isSerif = isSerif
    }
}

public enum ThemeFontResolver {
    public static func spec(
        for mode: ThemeMode,
        script: ThemeScript,
        serifOverride: Bool? = nil
    ) -> ThemeFontSpec {
        let usesClassicFonts = mode != .modern
        let candidates: [String]

        switch (usesClassicFonts, script) {
        case (true, .cjk):
            candidates = ["Songti SC", "STSong", "Songti TC"]
        case (true, .latin):
            candidates = ["EB Garamond", "Source Serif 4", "New York", "Times New Roman"]
        case (false, .cjk):
            candidates = ["PingFang SC", "Heiti SC"]
        case (false, .latin):
            candidates = ["Inter", "Helvetica Neue"]
        }

        return ThemeFontSpec(
            familyCandidates: candidates,
            isSerif: serifOverride ?? usesClassicFonts
        )
    }
}
