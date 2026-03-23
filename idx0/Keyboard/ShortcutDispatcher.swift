import AppKit
import Foundation

struct ShortcutDispatcher {
    let registry: ShortcutRegistry

    init(registry: ShortcutRegistry = .shared) {
        self.registry = registry
    }

    func resolveAction(for event: NSEvent, settings: AppSettings) -> ShortcutActionID? {
        for descriptor in registry.descriptors where descriptor.remappable {
            let bindings = registry.activeBindings(for: descriptor.id, settings: settings)
            if bindings.contains(where: { $0.matches(event: event) }) {
                return descriptor.id
            }
        }
        return nil
    }

    func displayLabel(for action: ShortcutActionID, settings: AppSettings) -> String? {
        registry.displayLabel(for: action, settings: settings)
    }
}
