import Foundation

public enum SpaceKind: String, Sendable, CaseIterable {
    case work
    case personal
    case blank

    public var defaultIcon: String {
        switch self {
        case .work: "briefcase"
        case .personal: "person"
        case .blank: "folder"
        }
    }
}

public enum SpaceBootstrap {
    /// Создаёт пространство в пустой папке: манифест, главную, шаблоны, инструкцию и первый снимок в git.
    @discardableResult
    public static func create(at root: URL, name rawName: String, icon: String? = nil, kind: SpaceKind, now: Date = .now) throws -> Space {
        let name = try TitleRules.validate(rawName)
        let path = String.filePath(root)
        if FileManager.default.fileExists(atPath: path) {
            let contents = try FileManager.default.contentsOfDirectory(atPath: path).filter { $0 != ".DS_Store" }
            guard contents.isEmpty else { throw FolioError.folderNotEmpty(path) }
        }

        let space = Space(manifest: SpaceManifest(name: name, icon: icon ?? kind.defaultIcon, created: now), root: root)
        try space.writeManifest()
        for file in SpaceContent.files(kind: kind, spaceName: name, now: now) {
            let url = root.appending(path: file.path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(file.contents.utf8).write(to: url, options: .atomic)
        }

        let repository = GitRepository(root: space.root)
        try repository.initialize()
        try repository.commitAll(message: "Создано пространство «\(name)»")
        return space
    }
}
