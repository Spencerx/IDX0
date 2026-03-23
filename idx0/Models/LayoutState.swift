import Foundation

enum WorkflowRailSurface: String, Codable, CaseIterable {
    case checkpoints
    case handoffs
    case review
    case compare
}

struct SessionStack: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var sessionIDs: [UUID]
    var visibleSessionID: UUID?

    init(
        id: UUID = UUID(),
        title: String = "Stack",
        sessionIDs: [UUID] = [],
        visibleSessionID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.sessionIDs = sessionIDs
        self.visibleSessionID = visibleSessionID ?? sessionIDs.first
    }
}

struct LayoutState: Codable, Equatable {
    var schemaVersion: Int
    var focusedSessionID: UUID?
    var focusModeEnabled: Bool
    var parkedSessionIDs: [UUID]
    var pinnedSessionIDs: [UUID]
    var stacks: [SessionStack]
    var lastVisibleSupportingSurfaceBySession: [UUID: SessionSurfaceFocus]
    var lastRailSurfaceBySession: [UUID: WorkflowRailSurface]

    init(
        schemaVersion: Int = PersistenceSchema.currentVersion,
        focusedSessionID: UUID? = nil,
        focusModeEnabled: Bool = false,
        parkedSessionIDs: [UUID] = [],
        pinnedSessionIDs: [UUID] = [],
        stacks: [SessionStack] = [],
        lastVisibleSupportingSurfaceBySession: [UUID: SessionSurfaceFocus] = [:],
        lastRailSurfaceBySession: [UUID: WorkflowRailSurface] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.focusedSessionID = focusedSessionID
        self.focusModeEnabled = focusModeEnabled
        self.parkedSessionIDs = parkedSessionIDs
        self.pinnedSessionIDs = pinnedSessionIDs
        self.stacks = stacks
        self.lastVisibleSupportingSurfaceBySession = lastVisibleSupportingSurfaceBySession
        self.lastRailSurfaceBySession = lastRailSurfaceBySession
    }
}

struct LayoutFilePayload: Codable {
    var schemaVersion: Int
    var layoutState: LayoutState

    init(
        schemaVersion: Int = PersistenceSchema.currentVersion,
        layoutState: LayoutState = LayoutState()
    ) {
        self.schemaVersion = schemaVersion
        self.layoutState = layoutState
    }
}
