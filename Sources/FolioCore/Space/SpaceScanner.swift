import Foundation

/// Снимок дерева страниц одного пространства на момент сканирования.
public struct SpaceSnapshot: Sendable {
    public let space: Space
    public let home: PageNode
    public let pages: [String: PageNode]
    private let titleIndex: [String: [String]]

    init(space: Space, home: PageNode, pages: [String: PageNode]) {
        self.space = space
        self.home = home
        self.pages = pages
        self.titleIndex = Dictionary(grouping: pages.values) { TitleKey.make($0.title) }
            .mapValues { $0.map(\.path).sorted() }
    }

    public func page(at path: String) -> PageNode? {
        pages[path]
    }

    public func pages(titled title: String) -> [PageNode] {
        (titleIndex[TitleKey.make(title)] ?? []).compactMap { pages[$0] }
    }

    public func uniquePage(titled title: String) throws -> PageNode {
        let matches = pages(titled: title)
        guard let first = matches.first else { throw FolioError.pageNotFound(title) }
        guard matches.count == 1 else { throw FolioError.ambiguousTitle(title, paths: matches.map(\.path)) }
        return first
    }

    /// Заголовки, которые носят несколько страниц, с путями этих страниц.
    public var duplicateTitles: [(title: String, paths: [String])] {
        titleIndex.values
            .filter { $0.count > 1 }
            .compactMap { paths in pages[paths[0]].map { (title: $0.title, paths: paths) } }
            .sorted { $0.title < $1.title }
    }

    /// Цепочка от главной страницы до родителя, без самой страницы.
    public func ancestors(of path: String) -> [PageNode] {
        guard !path.isEmpty else { return [] }
        let components = path.split(separator: "/").map(String.init)
        let prefixes = components.indices.dropLast().map { components[...$0].joined(separator: "/") }
        return ([""] + prefixes).compactMap { pages[$0] }
    }

    public func folderURL(for path: String) -> URL {
        path.isEmpty ? space.root : space.root.appending(path: path, directoryHint: .isDirectory)
    }

    public func fileURL(for path: String) -> URL {
        folderURL(for: path).appending(path: SpaceScanner.pageFileName)
    }
}

public enum SpaceScanner {
    public static let pageFileName = "index.md"
    static let headerByteLimit = 16_384

    public static func scan(_ space: Space) -> SpaceSnapshot {
        var pages: [String: PageNode] = [:]
        let home = scanPage(folder: space.root, path: "", space: space, pages: &pages)
        return SpaceSnapshot(space: space, home: home, pages: pages)
    }

    /// Папка — страница, если в ней лежит `index.md`. Папки на `_` и `.` служебные.
    public static func isPageFolder(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        guard !name.hasPrefix("_"), !name.hasPrefix(".") else { return false }
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return false }
        return FileManager.default.fileExists(atPath: String.filePath(url.appending(path: pageFileName)))
    }

    private static func scanPage(folder: URL, path: String, space: Space, pages: inout [String: PageNode]) -> PageNode {
        let frontmatter = readFrontmatter(at: folder.appending(path: pageFileName))
        let childFolders = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var children: [PageNode] = []
        for child in childFolders where isPageFolder(child) {
            let childPath = PagePath.join(path, child.lastPathComponent)
            children.append(scanPage(folder: child, path: childPath, space: space, pages: &pages))
        }

        let fallbackTitle = path.isEmpty ? space.name : folder.lastPathComponent
        let node = PageNode(
            spaceID: space.id,
            path: path,
            title: frontmatter.title ?? fallbackTitle,
            pageID: frontmatter.id,
            status: frontmatter.status,
            labels: frontmatter.labels,
            order: frontmatter.order,
            children: children.sorted(by: PageNode.displayOrder)
        )
        pages[path] = node
        return node
    }

    /// Читает только начало файла: расшифровки бывают большими, а для дерева нужна одна шапка.
    static func readFrontmatter(at url: URL) -> PageFrontmatter {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return PageFrontmatter() }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: headerByteLimit)) ?? Data()
        let document = PageDocument.parse(String(decoding: head, as: UTF8.self))
        let isTruncatedHeader = document.rawFrontmatter == nil && head.count == headerByteLimit && head.starts(with: Data("---".utf8))
        guard isTruncatedHeader else { return document.frontmatter }
        let rest = (try? handle.readToEnd()) ?? Data()
        return PageDocument.parse(String(decoding: head + rest, as: UTF8.self)).frontmatter
    }
}

/// Все подключённые пространства сразу — нужно для ссылок между пространствами.
public struct LibrarySnapshot: Sendable {
    public let spaces: [SpaceSnapshot]

    public init(spaces: [SpaceSnapshot]) {
        self.spaces = spaces
    }

    public func snapshot(for id: UUID) -> SpaceSnapshot? {
        spaces.first { $0.space.id == id }
    }

    public func snapshot(named name: String) -> SpaceSnapshot? {
        let key = TitleKey.make(name)
        return spaces.first { TitleKey.make($0.space.name) == key }
    }

    public func node(for ref: PageRef) -> PageNode? {
        snapshot(for: ref.spaceID)?.page(at: ref.path)
    }

    public func resolve(_ link: WikiLink, from spaceID: UUID) -> PageRef? {
        let target: SpaceSnapshot? = if let spaceName = link.space {
            snapshot(named: spaceName)
        } else {
            snapshot(for: spaceID)
        }
        return target?.pages(titled: link.title).first?.id
    }
}
