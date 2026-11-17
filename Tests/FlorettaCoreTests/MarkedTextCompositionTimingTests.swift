import XCTest
@testable import FlorettaCore

final class MarkedTextCompositionTimingTests: XCTestCase {
    func testMeasuresNonEmptyMarkedTextUntilUnmarkAndIgnoresRepeatedUpdates() {
        var timing = MarkedTextCompositionTiming()

        timing.observe(markedTextLength: 2, at: 10)
        timing.observe(markedTextLength: 4, at: 10.25)
        XCTAssertNil(timing.duration, "an active marked range is not complete yet")

        timing.observe(markedTextLength: 0, at: 11.5)
        timing.observe(markedTextLength: 0, at: 12)

        XCTAssertTrue(timing.hasNonEmptyMarkedText)
        XCTAssertEqual(timing.maximumMarkedTextLength, 4)
        XCTAssertEqual(timing.duration ?? -1, 1.5, accuracy: 0.000_001)
    }

    func testSumsDistinctMarkedRangesWithoutCountingTheGap() {
        var timing = MarkedTextCompositionTiming()

        timing.observe(markedTextLength: 1, at: 1)
        timing.observe(markedTextLength: 0, at: 1.4)
        timing.observe(markedTextLength: 3, at: 2)
        timing.observe(markedTextLength: 0, at: 2.6)

        XCTAssertEqual(timing.duration ?? -1, 1, accuracy: 0.000_001)
    }

    func testEmptyMarkedRangesDoNotQualifyAsComposition() {
        var timing = MarkedTextCompositionTiming()

        timing.observe(markedTextLength: 0, at: 1)
        timing.observe(markedTextLength: 0, at: 2)

        XCTAssertFalse(timing.hasNonEmptyMarkedText)
        XCTAssertNil(timing.duration)
    }
}
