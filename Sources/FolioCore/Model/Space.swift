import Foundation

public struct SpaceManifest: Codable, Sendable, Hashable {
    public var id: UUID
    public var name: String
    public var icon: String
    public var created: Date

    public init(id: UUID = UUID(), name: String, icon: String, created: Date = .now) {
        self.id = id
        self.name = name
        self.icon = icon
        self.created = created
    }
}

/// Пространство — папка со страницами, своей историей git и манифестом `.folio/space.json`.
public struct Space: Sendable, Hashable, Identifiable {
    public static let manifestPath = ".folio/space.json"

    public let manifest: SpaceManifest
    public let root: URL

    public var id: UUID { manifest.id }
    public var name: String { manifest.name }
    public var icon: String { manifest.icon }

    public init(manifest: SpaceManifest, root: URL) {
        self.manifest = manifest
        self.root = root.standardizedFileURL
    }

    public static func open(at root: URL) throws -> Space {
        let url = root.appending(path: manifestPath)
        guard let data = try? Data(contentsOf: url) else {
            throw FolioError.notASpace(String.filePath(root))
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return Space(manifest: try decoder.decode(SpaceManifest.self, from: data), root: root)
    }

    func writeManifest() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let url = root.appending(path: Self.manifestPath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(manifest).write(to: url, options: .atomic)
    }
}
