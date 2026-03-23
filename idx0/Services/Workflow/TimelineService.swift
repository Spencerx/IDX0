import Foundation

struct TimelineService {
    let maxItems: Int

    init(maxItems: Int = 1000) {
        self.maxItems = maxItems
    }

    func append(
        _ item: TimelineItem,
        to items: [TimelineItem]
    ) -> [TimelineItem] {
        var next = items
        next.append(item)
        if next.count > maxItems {
            next.removeFirst(next.count - maxItems)
        }
        return next
    }

    func sortedLatestFirst(_ items: [TimelineItem]) -> [TimelineItem] {
        items.sorted { lhs, rhs in
            lhs.createdAt > rhs.createdAt
        }
    }
}
