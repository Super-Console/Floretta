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

/// Resolves a face for content text. Serif is a property of the face the user
/// picked in the font list, not of an appearance mode.
public enum ThemeFontResolver {
    public static func spec(script: ThemeScript, isSerif: Bool) -> ThemeFontSpec {
        let candidates: [String]

        switch (isSerif, script) {
        case (true, .cjk):
            candidates = ["Songti SC", "STSong", "Songti TC"]
        case (true, .latin):
            candidates = ["EB Garamond", "Source Serif 4", "New York", "Times New Roman"]
        case (false, .cjk):
            candidates = ["PingFang SC", "Heiti SC"]
        case (false, .latin):
            candidates = ["Inter", "Helvetica Neue"]
        }

        return ThemeFontSpec(familyCandidates: candidates, isSerif: isSerif)
    }

    public static func spec(script: ThemeScript, familyID: String) -> ThemeFontSpec {
        spec(script: script, isSerif: AppearanceCatalog.family(id: familyID)?.kind == .serif)
    }
}
