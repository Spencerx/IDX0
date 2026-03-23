import Foundation

struct SessionRestoreCoordinator {
    static let metadataOnlyStatusText = "Restored metadata only. Select to relaunch."

    func apply(
        behavior: RestoreBehavior,
        selectedSessionID: UUID?,
        sessions: inout [Session],
        relaunchSession: (UUID) -> Void,
        relaunchAllSessions: () -> Void
    ) {
        switch behavior {
        case .restoreMetadataOnly:
            markSessionsAsRestoredWithoutRuntime(sessions: &sessions, excluding: nil)
        case .relaunchSelectedSession:
            markSessionsAsRestoredWithoutRuntime(
                sessions: &sessions,
                excluding: selectedSessionID.map { Set([$0]) }
            )
            if let selectedSessionID {
                relaunchSession(selectedSessionID)
            }
        case .relaunchAllSessions:
            relaunchAllSessions()
        }
    }

    private func markSessionsAsRestoredWithoutRuntime(
        sessions: inout [Session],
        excluding excluded: Set<UUID>?
    ) {
        for index in sessions.indices {
            if let excluded, excluded.contains(sessions[index].id) {
                continue
            }
            sessions[index].statusText = Self.metadataOnlyStatusText
        }
    }
}
