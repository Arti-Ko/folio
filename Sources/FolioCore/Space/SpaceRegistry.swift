import Foundation

public enum FolioPaths {
    /// Переменная окружения `FOLIO_SUPPORT_DIR` подменяет служебную папку — для проверок без реальных данных.
    public static var supportFolder: URL {
        if let override = ProcessInfo.processInfo.environment["FOLIO_SUPPORT_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return URL.applicationSupportDirectory.appending(path: "Folio", directoryHint: .isDirectory)
    }

    public static var defaultSpacesFolder: URL {
        URL.documentsDirectory.appending(path: "Folio", directoryHint: .isDirectory)
    }

    public static var registryURL: URL { supportFolder.appending(path: "spaces.json") }
    public static var indexURL: URL { supportFolder.appending(path: "index.sqlite") }
}

/// Список подключённых пространств, общий для приложения и утилиты `folio`.
public struct SpaceRegistry: Sendable {
    private struct StoredList: Codable {
        var spaces: [String]
    }

    public struct LoadResult: Sendable {
        public let spaces: [Space]
        public let missingPaths: [String]
    }

    public let fileURL: URL

    public init(fileURL: URL = FolioPaths.registryURL) {
        self.fileURL = fileURL
    }

    public func load() -> LoadResult {
        var spaces: [Space] = []
        var missing: [String] = []
        for path in storedPaths() {
            if let space = try? Space.open(at: URL(fileURLWithPath: path, isDirectory: true)) {
                spaces.append(space)
            } else {
                missing.append(path)
            }
        }
        return LoadResult(spaces: spaces, missingPaths: missing)
    }

    public func register(_ space: Space) throws {
        let nameKey = TitleKey.make(space.name)
        if let clash = load().spaces.first(where: { $0.id == space.id || TitleKey.make($0.name) == nameKey }) {
            throw FolioError.spaceAlreadyRegistered(clash.name)
        }
        try save(storedPaths() + [space.rootPath])
    }

    public func unregister(id: UUID) throws {
        try save(storedPaths().filter { path in
            (try? Space.open(at: URL(fileURLWithPath: path, isDirectory: true)))?.id != id
        })
    }

    public func unregister(path: String) throws {
        try save(storedPaths().filter { $0 != path })
    }

    private func storedPaths() -> [String] {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode(StoredList.self, from: data) else { return [] }
        return list.spaces
    }

    private func save(_ paths: [String]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        try encoder.encode(StoredList(spaces: paths)).write(to: fileURL, options: .atomic)
    }
}

extension Space {
    public var rootPath: String { String.filePath(root) }

    /// Лежит ли путь внутри пространства.
    public func contains(path: String) -> Bool {
        path == rootPath || path.hasPrefix(rootPath + "/")
    }
}
