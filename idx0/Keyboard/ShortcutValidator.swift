import Foundation

struct ShortcutConflict: Identifiable, Hashable {
    let chord: KeyChord
    let actions: [ShortcutActionID]

    var id: String {
        let actionIDs = actions.map(\.rawValue).sorted().joined(separator: ",")
        return "\(chord.displayString)|\(actionIDs)"
    }

    var message: String {
        let titles = actions
            .compactMap { ShortcutRegistry.shared.descriptor(for: $0)?.title }
            .joined(separator: " and ")
        return "\(chord.displayString) conflicts between \(titles)."
    }
}

struct ShortcutValidator {
    let registry: ShortcutRegistry

    init(registry: ShortcutRegistry = .shared) {
        self.registry = registry
    }

    func conflicts(for settings: AppSettings) -> [ShortcutConflict] {
        var bindingsByChord: [KeyChord: [ShortcutActionID]] = [:]

        for descriptor in registry.descriptors where descriptor.remappable {
            let bindings = registry.activeBindings(for: descriptor.id, settings: settings)
            for binding in bindings {
                bindingsByChord[binding, default: []].append(descriptor.id)
            }
        }

        return bindingsByChord
            .compactMap { chord, actions in
                let uniqueActions = Array(Set(actions)).sorted { $0.rawValue < $1.rawValue }
                guard uniqueActions.count > 1 else {
                    return nil
                }
                return ShortcutConflict(chord: chord, actions: uniqueActions)
            }
            .sorted { lhs, rhs in
                lhs.chord.displayString < rhs.chord.displayString
            }
    }

    func canApply(settings: AppSettings) -> Bool {
        conflicts(for: settings).isEmpty
    }
}
