import Foundation

struct SettingsStore {
    private let url: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        self.decoder = JSONDecoder()
    }

    var storageURL: URL {
        url
    }

    func load() -> AppSettings {
        guard fileManager.fileExists(atPath: url.path) else {
            return AppSettings()
        }

        do {
            let data = try Data(contentsOf: url)
            let decoded = try decoder.decode(AppSettings.self, from: data)
            return decoded
        } catch {
            Logger.error("Failed loading settings file: \(error.localizedDescription)")
            return AppSettings()
        }
    }

    func save(_ settings: AppSettings) throws {
        let data = try encoder.encode(settings)
        try atomicWrite(data: data, to: url)
    }

    private func atomicWrite(data: Data, to destination: URL) throws {
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destination, options: .atomic)
    }
}
