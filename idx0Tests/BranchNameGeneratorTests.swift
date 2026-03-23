import XCTest
@testable import idx0

final class BranchNameGeneratorTests: XCTestCase {
    func testSlugifyCollapsesUnsupportedCharacters() {
        let value = BranchNameGenerator.slugify("Fix Prompt Glitch!!! / spaces")
        XCTAssertEqual(value, "fix-prompt-glitch-spaces")
    }

    func testGenerateUsesPrefixAndTimestampShape() {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 13, hour: 10, minute: 35))!
        let branch = BranchNameGenerator.generate(sessionTitle: "Fix Prompt Glitch", repoName: "idx0", now: date)
        XCTAssertTrue(branch.hasPrefix("idx0/fix-prompt-glitch-"))
        XCTAssertEqual(branch.count, "idx0/fix-prompt-glitch-20260313-1035".count)
    }

    func testGenerateFallsBackToRepoSlugWhenTitleSlugIsEmpty() {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 13, hour: 10, minute: 35))!
        let branch = BranchNameGenerator.generate(sessionTitle: "!!!", repoName: "idx0-repo", now: date)
        XCTAssertTrue(branch.hasPrefix("idx0/idx0-repo-"))
    }
}
