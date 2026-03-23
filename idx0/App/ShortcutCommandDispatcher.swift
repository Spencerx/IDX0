import Foundation

@MainActor
final class ShortcutCommandDispatcher {
    func perform(_ action: ShortcutActionID, coordinator: AppCoordinator) -> Bool {
        coordinator.performShortcutAction(action)
    }
}
