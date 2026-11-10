import Foundation

/// How many topics, words, and characters are in node titles.
///
/// Word count (字数) follows the XMind fixture. A title is scanned one extended
/// grapheme cluster at a time:
/// - Each character whose scalars include `otherLetter` counts as one word.
///   CJK ideographs, kana, and Hangul syllables are in that category, so each
///   one counts as one word and also ends a letter or digit run.
/// - A run of consecutive cased letters (`uppercaseLetter`, `lowercaseLetter`,
///   `titlecaseLetter`) counts as one word. That is the English-word rule,
///   and it includes accented and fullwidth Latin letters. 「Hello世界」 is 3.
/// - A run of consecutive decimal digits counts as one word. A single digit is
///   a run of one, so 「分支主题 1」 is 5, not 4. 「12」 and 「１２」 are one word
///   each; 「1 2」 is two. A digit grapheme is one whose scalars are all decimal
///   digits, so a keycap such as 「1️⃣」 is an emoji, not a digit. A decimal
///   point, hyphen, or apostrophe ends the run, so 「3.14」 and 「don't」 are two
///   words each.
/// - Spaces, newlines, punctuation, symbols, and emoji add no words. They end
///   a run. Emoji still counts as one character, including a ZWJ sequence, a
///   flag, or a keycap, because each of those is one grapheme cluster.
///
/// Character count (字符数) is one per extended grapheme cluster, including
/// spaces, tabs, punctuation, and emoji, and excluding newline graphemes
/// (`\n`, `\r`, `\r\n`, and the other separators `Character.isNewline` accepts).
///
/// Only topic titles are counted: `roots`, `freeNodes`, their children, and the
/// same fields on additional sheets. Notes, labels, markers, attachment names,
/// sticky text, relationship titles, summary text, boundary titles, the document
/// title, and sheet titles are not titles. Collapsed children are still titles.
public struct TopicTitleCensus: Equatable, Sendable {
    public var topics: Int
    public var words: Int
    public var characters: Int

    public static let zero = TopicTitleCensus(topics: 0, words: 0, characters: 0)

    public init(topics: Int, words: Int, characters: Int) {
        self.topics = topics
        self.words = words
        self.characters = characters
    }

    public static func tally(_ document: MindMapDocument) -> TopicTitleCensus {
        var census = tally(roots: document.roots, freeNodes: document.freeNodes)
        for canvas in document.additionalCanvases {
            census.add(tally(roots: canvas.roots, freeNodes: canvas.freeNodes))
        }
        return census
    }

    public static func tally(roots: [MindMapNode], freeNodes: [MindMapNode]) -> TopicTitleCensus {
        var census = TopicTitleCensus.zero
        walk(roots, into: &census)
        walk(freeNodes, into: &census)
        return census
    }

    public mutating func add(_ other: TopicTitleCensus) {
        topics += other.topics
        words += other.words
        characters += other.characters
    }

    private static func walk(_ nodes: [MindMapNode], into census: inout TopicTitleCensus) {
        for node in nodes {
            let measure = TopicTitleMeasure.measure(node.text)
            census.topics += 1
            census.words += measure.words
            census.characters += measure.characters
            walk(node.children, into: &census)
        }
    }
}

public extension MindMapDocument {
    /// Topic, word, and character counts for every node title. Same topic set as `topicCount`.
    public var titleCensus: TopicTitleCensus {
        TopicTitleCensus.tally(self)
    }
}

/// Word and character counts for one title.
public struct TopicTitleMeasure: Equatable, Sendable {
    public var words: Int
    public var characters: Int

    public init(words: Int, characters: Int) {
        self.words = words
        self.characters = characters
    }

    public static func measure(_ text: String) -> TopicTitleMeasure {
        var words = 0
        var characters = 0
        var run = WordRun.none
        for character in text {
            if character.isNewline {
                run = .none
                continue
            }
            characters += 1
            switch TopicTitleScript.piece(character) {
            case .ideograph:
                words += 1
                run = .none
            case .letter:
                if run != .letter {
                    words += 1
                    run = .letter
                }
            case .digit:
                if run != .digit {
                    words += 1
                    run = .digit
                }
            case .other:
                run = .none
            }
        }
        return TopicTitleMeasure(words: words, characters: characters)
    }
}

private enum WordRun {
    case none
    case letter
    case digit
}

private enum TopicTitleScript {
    case ideograph
    case letter
    case digit
    case other

    static func piece(_ character: Character) -> TopicTitleScript {
        var sawIdeograph = false
        var sawLetter = false
        var allDigits = true
        var sawScalar = false
        for scalar in character.unicodeScalars {
            sawScalar = true
            switch scalar.properties.generalCategory {
            case .otherLetter:
                sawIdeograph = true
                allDigits = false
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter:
                sawLetter = true
                allDigits = false
            default:
                if scalar.properties.numericType != .decimal {
                    allDigits = false
                }
            }
        }
        if !sawScalar { return .other }
        if sawIdeograph { return .ideograph }
        if sawLetter { return .letter }
        if allDigits { return .digit }
        return .other
    }
}

/// Remembers title measurements so a keystroke remeasures the edited title
/// and does not walk sheets that were not edited.
///
/// The active sheet (`roots` and `freeNodes`) is walked on every update, because
/// an in-place edit keeps the same array storage. Each unchanged title is a
/// pointer compare against the stored string. Additional sheets are retained by
/// copy-on-write and skipped while that storage is still the one last counted.
/// Editing one of those sheets copies its array, which is what makes the next
/// update count it again. Empty additional-sheet lists do not allocate.
public struct TopicTitleCensusCache: Sendable {
    private struct StoredTitle: Equatable, Sendable {
        var text: String
        var words: Int
        var characters: Int
    }

    private struct ExtraSheet: Sendable {
        var roots: [MindMapNode]
        var freeNodes: [MindMapNode]
        var census: TopicTitleCensus
    }

    private var titles: [UUID: StoredTitle] = [:]
    private var extraSheets: [UUID: ExtraSheet] = [:]

    /// Titles on the active sheet whose text was measured during the last `update`.
    public private(set) var remeasuredActiveTitles = 0
    /// Additional sheets whose node trees were walked during the last `update`.
    public private(set) var recountedExtraSheets = 0

    public init() {}

    public mutating func update(_ document: MindMapDocument) -> TopicTitleCensus {
        remeasuredActiveTitles = 0
        recountedExtraSheets = 0
        var active = TopicTitleCensus.zero
        var seen = Set<UUID>()
        seen.reserveCapacity(titles.count)
        walk(document.roots, seen: &seen, census: &active)
        walk(document.freeNodes, seen: &seen, census: &active)
        if titles.count != seen.count {
            titles = titles.filter { seen.contains($0.key) }
        }
        let extra = extraCensus(document.additionalCanvases)
        return TopicTitleCensus(
            topics: active.topics + extra.topics,
            words: active.words + extra.words,
            characters: active.characters + extra.characters
        )
    }

    private mutating func walk(_ nodes: [MindMapNode], seen: inout Set<UUID>, census: inout TopicTitleCensus) {
        for node in nodes {
            seen.insert(node.id)
            let measure = cachedMeasure(node.id, node.text)
            census.topics += 1
            census.words += measure.words
            census.characters += measure.characters
            walk(node.children, seen: &seen, census: &census)
        }
    }

    private mutating func cachedMeasure(_ id: UUID, _ text: String) -> TopicTitleMeasure {
        if let stored = titles[id], stored.text == text {
            return TopicTitleMeasure(words: stored.words, characters: stored.characters)
        }
        let measured = TopicTitleMeasure.measure(text)
        titles[id] = StoredTitle(text: text, words: measured.words, characters: measured.characters)
        remeasuredActiveTitles += 1
        return measured
    }

    private mutating func extraCensus(_ canvases: [MindMapCanvas]) -> TopicTitleCensus {
        var total = TopicTitleCensus.zero
        var next: [UUID: ExtraSheet] = [:]
        next.reserveCapacity(canvases.count)
        for canvas in canvases {
            if let held = extraSheets[canvas.id],
               sameStorage(canvas.roots, held.roots),
               sameStorage(canvas.freeNodes, held.freeNodes) {
                total.add(held.census)
                next[canvas.id] = held
                continue
            }
            let census = TopicTitleCensus.tally(roots: canvas.roots, freeNodes: canvas.freeNodes)
            total.add(census)
            next[canvas.id] = ExtraSheet(roots: canvas.roots, freeNodes: canvas.freeNodes, census: census)
            recountedExtraSheets += 1
        }
        extraSheets = next
        return total
    }

    /// True when both arrays are the same copy-on-write buffer.
    /// Holding `held` keeps that buffer alive, so an in-place edit of a shared
    /// array copies it and the addresses diverge.
    private func sameStorage<T>(_ current: [T], _ held: [T]) -> Bool {
        if current.count != held.count { return false }
        if current.isEmpty { return true }
        let currentAddress = current.withUnsafeBufferPointer { Int(bitPattern: $0.baseAddress) }
        let heldAddress = held.withUnsafeBufferPointer { Int(bitPattern: $0.baseAddress) }
        return currentAddress != 0 && currentAddress == heldAddress
    }
}
