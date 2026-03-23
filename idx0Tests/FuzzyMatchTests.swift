import SwiftUI
import XCTest
@testable import idx0

final class FuzzyMatchTests: XCTestCase {
    func testMatchesSubsequence() {
        XCTAssertTrue(FuzzyMatch.matches(query: "idx", text: "index"))
        XCTAssertFalse(FuzzyMatch.matches(query: "xyz", text: "index"))
    }

    func testScoreRewardsTighterMatches() {
        let contiguous = FuzzyMatch.score(query: "app", text: "app shell")
        let spreadOut = FuzzyMatch.score(query: "app", text: "a p p shell")

        XCTAssertGreaterThan(contiguous, spreadOut)
    }

    func testScoreReturnsZeroWhenQueryCannotBeMatched() {
        XCTAssertEqual(FuzzyMatch.score(query: "zzz", text: "index"), 0)
    }

    func testHighlightMarksMatchedCharacters() {
        let highlighted = FuzzyMatch.highlight(query: "abc", in: "a b c")
        let coloredRuns = highlighted.runs.filter { $0.foregroundColor != nil }
        XCTAssertFalse(coloredRuns.isEmpty)
    }

    func testHighlightWithBlankQueryLeavesTextUnstyled() {
        let highlighted = FuzzyMatch.highlight(query: "   ", in: "abc")
        let coloredRuns = highlighted.runs.filter { $0.foregroundColor != nil }
        XCTAssertTrue(coloredRuns.isEmpty)
    }
}
