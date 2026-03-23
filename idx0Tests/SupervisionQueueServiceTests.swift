import Foundation
import XCTest
@testable import idx0

final class SupervisionQueueServiceTests: XCTestCase {
    func testSortedUnresolvedItemsUsesUrgencyThenRecency() {
        let service = SupervisionQueueService()
        let sessionID = UUID()
        let now = Date()

        let items: [SupervisionQueueItem] = [
            SupervisionQueueItem(
                id: UUID(),
                sessionID: sessionID,
                relatedObjectID: nil,
                category: .informational,
                title: "Info",
                subtitle: nil,
                createdAt: now,
                isResolved: false,
                isPinned: false
            ),
            SupervisionQueueItem(
                id: UUID(),
                sessionID: sessionID,
                relatedObjectID: nil,
                category: .blocked,
                title: "Blocked",
                subtitle: nil,
                createdAt: now.addingTimeInterval(-40),
                isResolved: false,
                isPinned: false
            ),
            SupervisionQueueItem(
                id: UUID(),
                sessionID: sessionID,
                relatedObjectID: nil,
                category: .error,
                title: "Error old",
                subtitle: nil,
                createdAt: now.addingTimeInterval(-100),
                isResolved: false,
                isPinned: false
            ),
            SupervisionQueueItem(
                id: UUID(),
                sessionID: sessionID,
                relatedObjectID: nil,
                category: .error,
                title: "Error new",
                subtitle: nil,
                createdAt: now.addingTimeInterval(-10),
                isResolved: false,
                isPinned: false
            ),
            SupervisionQueueItem(
                id: UUID(),
                sessionID: sessionID,
                relatedObjectID: nil,
                category: .approvalNeeded,
                title: "Approval",
                subtitle: nil,
                createdAt: now.addingTimeInterval(-20),
                isResolved: false,
                isPinned: false
            ),
            SupervisionQueueItem(
                id: UUID(),
                sessionID: sessionID,
                relatedObjectID: nil,
                category: .reviewRequested,
                title: "Review",
                subtitle: nil,
                createdAt: now.addingTimeInterval(-30),
                isResolved: true,
                isPinned: false
            )
        ]

        let sorted = service.sortedUnresolvedItems(from: items)
        XCTAssertEqual(sorted.map(\.category), [.approvalNeeded, .error, .error, .blocked, .informational])
        XCTAssertEqual(sorted[1].title, "Error new")
        XCTAssertEqual(sorted[2].title, "Error old")
    }

    func testPruneExpiredInformationalDropsOnlyUnpinnedUnresolvedItems() {
        let service = SupervisionQueueService(informationalTTL: 60)
        let sessionID = UUID()
        let now = Date()

        let expired = now.addingTimeInterval(-120)
        let fresh = now.addingTimeInterval(-10)

        let items: [SupervisionQueueItem] = [
            SupervisionQueueItem(
                id: UUID(),
                sessionID: sessionID,
                relatedObjectID: nil,
                category: .informational,
                title: "Expired",
                subtitle: nil,
                createdAt: expired,
                isResolved: false,
                isPinned: false
            ),
            SupervisionQueueItem(
                id: UUID(),
                sessionID: sessionID,
                relatedObjectID: nil,
                category: .informational,
                title: "Pinned",
                subtitle: nil,
                createdAt: expired,
                isResolved: false,
                isPinned: true
            ),
            SupervisionQueueItem(
                id: UUID(),
                sessionID: sessionID,
                relatedObjectID: nil,
                category: .informational,
                title: "Resolved",
                subtitle: nil,
                createdAt: expired,
                isResolved: true,
                isPinned: false
            ),
            SupervisionQueueItem(
                id: UUID(),
                sessionID: sessionID,
                relatedObjectID: nil,
                category: .informational,
                title: "Fresh",
                subtitle: nil,
                createdAt: fresh,
                isResolved: false,
                isPinned: false
            )
        ]

        let pruned = service.pruneExpiredInformational(items, now: now)
        XCTAssertFalse(pruned.map(\.title).contains("Expired"))
        XCTAssertTrue(pruned.map(\.title).contains("Pinned"))
        XCTAssertTrue(pruned.map(\.title).contains("Resolved"))
        XCTAssertTrue(pruned.map(\.title).contains("Fresh"))
    }
}
