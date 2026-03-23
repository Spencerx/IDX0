import XCTest
@testable import idx0

final class WorkflowModelsTests: XCTestCase {
    func testQueueItemCategoryDisplayLabelsAndUrgencyAreStable() {
        XCTAssertEqual(QueueItemCategory.approvalNeeded.displayLabel, "Approval Needed")
        XCTAssertEqual(QueueItemCategory.reviewRequested.displayLabel, "Review Requested")
        XCTAssertEqual(QueueItemCategory.blocked.displayLabel, "Blocked")
        XCTAssertEqual(QueueItemCategory.completed.displayLabel, "Completed")
        XCTAssertEqual(QueueItemCategory.error.displayLabel, "Error")
        XCTAssertEqual(QueueItemCategory.informational.displayLabel, "Info")

        XCTAssertLessThan(QueueItemCategory.approvalNeeded.urgencyRank, QueueItemCategory.error.urgencyRank)
    }

    func testJSONValueDecodesAllSupportedShapes() throws {
        let data = #"""
        {
          "string": "value",
          "number": 42,
          "bool": true,
          "array": [1, "two", false],
          "object": { "nested": "ok" },
          "null": null
        }
        """#.data(using: .utf8)!

        let decoded = try JSONDecoder().decode([String: JSONValue].self, from: data)

        XCTAssertEqual(decoded["string"]?.stringValue, "value")
        XCTAssertEqual(decoded["number"]?.intValue, 42)
        XCTAssertEqual(decoded["bool"]?.boolValue, true)
        XCTAssertEqual(decoded["object"]?.objectValue?["nested"]?.stringValue, "ok")
        XCTAssertEqual(decoded["array"]?.arrayValue?.count, 3)
        XCTAssertEqual(decoded["null"], .null)
    }

    func testJSONValueRoundTripsViaCodable() throws {
        let original: [String: JSONValue] = [
            "name": .string("idx0"),
            "count": .number(3),
            "enabled": .bool(true),
            "items": .array([.string("a"), .number(1)]),
            "meta": .object(["k": .string("v")]),
            "none": .null
        ]

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([String: JSONValue].self, from: encoded)

        XCTAssertEqual(decoded, original)
    }

    func testSessionUsageDefaultsAreZero() {
        let usage = SessionUsage()
        XCTAssertEqual(usage.totalInputTokens, 0)
        XCTAssertEqual(usage.totalOutputTokens, 0)
        XCTAssertEqual(usage.totalEstimatedCostUSD, 0)
        XCTAssertEqual(usage.eventCount, 0)
    }
}
