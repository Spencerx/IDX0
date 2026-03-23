import Foundation

enum AppCommandSurface: String, CaseIterable, Hashable {
    case shortcut
    case menu
    case palette
}

struct AppCommandDescriptor: Identifiable, Hashable {
    let id: ShortcutActionID
    let title: String
    let detail: String
    let surfaces: Set<AppCommandSurface>
    let shortcutID: ShortcutActionID?
}

struct AppCommandRegistry {
    static let shared = AppCommandRegistry()

    private(set) var descriptors: [AppCommandDescriptor]
    private let descriptorByID: [ShortcutActionID: AppCommandDescriptor]

    init(shortcutRegistry: ShortcutRegistry = .shared) {
        self.descriptors = shortcutRegistry.descriptors.map { shortcut in
            AppCommandDescriptor(
                id: shortcut.id,
                title: shortcut.title,
                detail: shortcut.detail,
                surfaces: [.shortcut, .menu, .palette],
                shortcutID: shortcut.id
            )
        }
        self.descriptorByID = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.id, $0) })
    }

    func descriptor(for id: ShortcutActionID) -> AppCommandDescriptor? {
        descriptorByID[id]
    }

    var shortcutCommandIDs: Set<ShortcutActionID> {
        Set(descriptors.filter { $0.surfaces.contains(.shortcut) }.map(\.id))
    }

    var menuCommandIDs: Set<ShortcutActionID> {
        Set(descriptors.filter { $0.surfaces.contains(.menu) }.map(\.id))
    }

    var paletteCommandIDs: Set<ShortcutActionID> {
        Set(descriptors.filter { $0.surfaces.contains(.palette) }.map(\.id))
    }
}
