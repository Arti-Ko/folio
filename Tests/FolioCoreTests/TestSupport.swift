import Foundation
@testable import FolioCore

final class TemporaryFolder {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "folio-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

extension URL {
    /// Путь без процентного кодирования и завершающего слеша — как его передаёт приложение.
    var plainPath: String { String.filePath(self) }
}

enum Fixture {
    /// Пространство без git: манифест и главная страница.
    static func space(named name: String, in folder: TemporaryFolder) throws -> Space {
        let space = Space(
            manifest: SpaceManifest(name: name, icon: "folder"),
            root: folder.url.appending(path: name, directoryHint: .isDirectory)
        )
        try space.writeManifest()
        try writePage(in: space, path: "", title: name, body: "")
        return space
    }

    static func writePage(in space: Space, path: String, title: String?, extra: [String] = [], body: String) throws {
        let folder = folderURL(space, path)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let titleLines = title.map { ["title: \(FrontmatterWriter.scalar($0))"] } ?? []
        let lines = ["id: \(PageID.make())"] + titleLines + extra
        let text = FrontmatterWriter.document(frontmatterLines: lines, body: body)
        try Data(text.utf8).write(to: folder.appending(path: SpaceScanner.pageFileName))
    }

    static func read(_ space: Space, _ path: String) throws -> String {
        try String(contentsOf: folderURL(space, path).appending(path: SpaceScanner.pageFileName), encoding: .utf8)
    }

    private static func folderURL(_ space: Space, _ path: String) -> URL {
        path.isEmpty ? space.root : space.root.appending(path: path, directoryHint: .isDirectory)
    }
}
