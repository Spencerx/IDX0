import Foundation

enum PaneSplitDirection: String, Codable {
    case horizontal
    case vertical
}

indirect enum PaneNode: Identifiable, Equatable {
    case terminal(id: UUID, controllerID: UUID)
    case split(id: UUID, direction: PaneSplitDirection, first: PaneNode, second: PaneNode, fraction: Double)

    var id: UUID {
        switch self {
        case .terminal(let id, _):
            return id
        case .split(let id, _, _, _, _):
            return id
        }
    }

    var terminalControllerIDs: [UUID] {
        switch self {
        case .terminal(_, let controllerID):
            return [controllerID]
        case .split(_, _, let first, let second, _):
            return first.terminalControllerIDs + second.terminalControllerIDs
        }
    }

    var terminalCount: Int {
        switch self {
        case .terminal:
            return 1
        case .split(_, _, let first, let second, _):
            return first.terminalCount + second.terminalCount
        }
    }

    /// Find the pane containing a given controller ID and split it
    func splitting(controllerID: UUID, direction: PaneSplitDirection, newControllerID: UUID) -> PaneNode {
        switch self {
        case .terminal(let id, let cID) where cID == controllerID:
            let newPane = PaneNode.terminal(id: UUID(), controllerID: newControllerID)
            return .split(id: UUID(), direction: direction, first: .terminal(id: id, controllerID: cID), second: newPane, fraction: 0.5)
        case .terminal:
            return self
        case .split(let id, let dir, let first, let second, let fraction):
            return .split(
                id: id,
                direction: dir,
                first: first.splitting(controllerID: controllerID, direction: direction, newControllerID: newControllerID),
                second: second.splitting(controllerID: controllerID, direction: direction, newControllerID: newControllerID),
                fraction: fraction
            )
        }
    }

    /// Remove a pane by controller ID, returning the remaining tree (or nil if this was the last pane)
    func removing(controllerID: UUID) -> PaneNode? {
        switch self {
        case .terminal(_, let cID) where cID == controllerID:
            return nil
        case .terminal:
            return self
        case .split(_, _, let first, let second, _):
            let newFirst = first.removing(controllerID: controllerID)
            let newSecond = second.removing(controllerID: controllerID)
            if let newFirst, let newSecond {
                return .split(id: UUID(), direction: self.splitDirection!, first: newFirst, second: newSecond, fraction: self.splitFraction!)
            }
            return newFirst ?? newSecond
        }
    }

    private var splitDirection: PaneSplitDirection? {
        if case .split(_, let dir, _, _, _) = self { return dir }
        return nil
    }

    private var splitFraction: Double? {
        if case .split(_, _, _, _, let f) = self { return f }
        return nil
    }
}
