import Foundation

struct SupervisionQueueService {
    var informationalTTL: TimeInterval = 60 * 60 * 12

    func sortedUnresolvedItems(from items: [SupervisionQueueItem]) -> [SupervisionQueueItem] {
        pruneExpiredInformational(items)
            .filter { !$0.isResolved }
            .sorted { lhs, rhs in
                if lhs.category.urgencyRank != rhs.category.urgencyRank {
                    return lhs.category.urgencyRank < rhs.category.urgencyRank
                }
                return lhs.createdAt > rhs.createdAt
            }
    }

    func highestPriorityCategory(for sessionID: UUID, in items: [SupervisionQueueItem]) -> QueueItemCategory? {
        sortedUnresolvedItems(from: items)
            .first(where: { $0.sessionID == sessionID })?
            .category
    }

    func resolve(itemID: UUID, in items: [SupervisionQueueItem]) -> [SupervisionQueueItem] {
        items.map { item in
            guard item.id == itemID else { return item }
            var updated = item
            updated.isResolved = true
            return updated
        }
    }

    func resolveForRelatedObject(relatedObjectID: UUID, in items: [SupervisionQueueItem]) -> [SupervisionQueueItem] {
        items.map { item in
            guard item.relatedObjectID == relatedObjectID else { return item }
            var updated = item
            updated.isResolved = true
            return updated
        }
    }

    func pruneExpiredInformational(_ items: [SupervisionQueueItem], now: Date = Date()) -> [SupervisionQueueItem] {
        items.filter { item in
            guard item.category == .informational, !item.isPinned, !item.isResolved else {
                return true
            }
            return now.timeIntervalSince(item.createdAt) <= informationalTTL
        }
    }
}
