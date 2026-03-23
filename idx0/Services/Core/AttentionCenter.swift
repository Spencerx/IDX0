import Foundation

struct AttentionCenter {
    private(set) var items: [AttentionItem]

    init(items: [AttentionItem] = []) {
        self.items = items
    }

    var unresolvedItems: [AttentionItem] {
        items
            .filter { !$0.isResolved }
            .sorted(by: Self.attentionSort)
    }

    mutating func replaceItems(_ items: [AttentionItem]) {
        self.items = items
    }

    mutating func removeItems(for sessionID: UUID) {
        items.removeAll(where: { $0.sessionID == sessionID })
    }

    mutating func record(sessionID: UUID, reason: AttentionReason, message: String?) {
        items.removeAll(where: { !$0.isResolved && $0.sessionID == sessionID })
        items.append(
            AttentionItem(
                id: UUID(),
                sessionID: sessionID,
                reason: reason,
                message: message,
                createdAt: Date(),
                isResolved: false
            )
        )
    }

    mutating func resolveIfNotError(sessionID: UUID) -> Bool {
        var changed = false
        for index in items.indices where items[index].sessionID == sessionID && !items[index].isResolved {
            if items[index].reason != .error {
                items[index].isResolved = true
                changed = true
            }
        }
        return changed
    }

    mutating func resolveOnVisit(sessionID: UUID) -> Bool {
        var changed = false
        for index in items.indices where items[index].sessionID == sessionID && !items[index].isResolved {
            switch items[index].reason {
            case .error:
                continue
            case .needsInput, .completed, .notification:
                items[index].isResolved = true
                changed = true
            }
        }
        return changed
    }

    func unresolvedReason(for sessionID: UUID) -> AttentionReason? {
        items
            .filter { !$0.isResolved && $0.sessionID == sessionID }
            .sorted(by: Self.attentionSort)
            .first?
            .reason
    }

    private static func attentionSort(_ lhs: AttentionItem, _ rhs: AttentionItem) -> Bool {
        if lhs.reason.urgencyRank != rhs.reason.urgencyRank {
            return lhs.reason.urgencyRank < rhs.reason.urgencyRank
        }
        return lhs.createdAt > rhs.createdAt
    }
}
