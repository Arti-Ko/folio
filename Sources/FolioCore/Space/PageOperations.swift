import Foundation

public struct RenameResult: Sendable, Equatable {
    public let newPath: String
    /// Сколько файлов переписано: сама страница и страницы со ссылками на неё.
    public let updatedFiles: Int
}

/// Создание, перенос, переименование и удаление страниц одного пространства.
public struct PageOperations: Sendable {
    public static let templatesFolder = "_Шаблоны"
    static let maximumFolderNameLength = 120

    public let snapshot: SpaceSnapshot

    public init(snapshot: SpaceSnapshot) {
        self.snapshot = snapshot
    }

    public func templateNames() -> [String] {
        let folder = snapshot.space.root.appending(path: Self.templatesFolder)
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "md" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    @discardableResult
    public func createPage(title rawTitle: String, parentPath: String, template: String? = nil, now: Date = .now) throws -> String {
        let title = try TitleRules.validate(rawTitle)
        try ensureTitleIsFree(title, exceptPath: nil)
        guard snapshot.page(at: parentPath) != nil else {
            throw FolioError.pageNotFound(parentPath.isEmpty ? snapshot.space.name : parentPath)
        }
        let content = try pageContent(title: title, template: template, now: now)
        let parentFolder = snapshot.folderURL(for: parentPath)
        let folderName = uniqueFolderName(base: Self.folderName(for: title), in: parentFolder, current: nil)
        let folder = parentFolder.appending(path: folderName, directoryHint: .isDirectory)

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try Data(content.utf8).write(to: folder.appending(path: SpaceScanner.pageFileName), options: .atomic)
        return PagePath.join(parentPath, folderName)
    }

    @discardableResult
    public func movePage(at path: String, toParent parentPath: String) throws -> String {
        guard !path.isEmpty else { throw FolioError.homePageIsFixed }
        guard let page = snapshot.page(at: path) else { throw FolioError.pageNotFound(path) }
        guard snapshot.page(at: parentPath) != nil else { throw FolioError.pageNotFound(parentPath) }
        guard parentPath != path, !parentPath.hasPrefix(path + "/") else { throw FolioError.moveIntoItself }
        guard page.parentPath != parentPath else { return path }

        let destinationParent = snapshot.folderURL(for: parentPath)
        let name = uniqueFolderName(base: page.folderName, in: destinationParent, current: nil)
        try FileManager.default.moveItem(
            at: snapshot.folderURL(for: path),
            to: destinationParent.appending(path: name, directoryHint: .isDirectory)
        )
        return PagePath.join(parentPath, name)
    }

    /// Меняет заголовок, папку и все ссылки на страницу во всех пространствах библиотеки.
    public func renamePage(at path: String, to rawTitle: String, library: LibrarySnapshot) throws -> RenameResult {
        guard let page = snapshot.page(at: path) else { throw FolioError.pageNotFound(path) }
        let title = try TitleRules.validate(rawTitle)
        try ensureTitleIsFree(title, exceptPath: path)
        guard title != page.title else { return RenameResult(newPath: path, updatedFiles: 0) }

        // Ссылки переписываем до переноса папки, пока пути в снимке ещё верные.
        let linkFiles = try rewriteLinks(from: page.title, to: title, library: library)
        try rewriteTitle(of: path, to: title)
        let updatedFiles = linkFiles.union(["\(snapshot.space.id)/\(path)"]).count

        guard !path.isEmpty else {
            return RenameResult(newPath: path, updatedFiles: updatedFiles)
        }
        let desiredName = Self.folderName(for: title)
        var newPath = path
        if desiredName != page.folderName {
            let parentPath = page.parentPath ?? ""
            let parentFolder = snapshot.folderURL(for: parentPath)
            let name = uniqueFolderName(base: desiredName, in: parentFolder, current: page.folderName)
            try renameFolder(snapshot.folderURL(for: path), to: parentFolder.appending(path: name, directoryHint: .isDirectory))
            newPath = PagePath.join(parentPath, name)
        }
        return RenameResult(newPath: newPath, updatedFiles: updatedFiles)
    }

    public func trashPage(at path: String) throws {
        guard !path.isEmpty else { throw FolioError.homePageIsFixed }
        guard snapshot.page(at: path) != nil else { throw FolioError.pageNotFound(path) }
        try FileManager.default.trashItem(at: snapshot.folderURL(for: path), resultingItemURL: nil)
    }

    /// Имя папки из заголовка: без символов, запрещённых в путях, и без служебных префиксов.
    public static func folderName(for title: String) -> String {
        let replaced = String(title.map { "/:\\".contains($0) ? "-" : $0 })
        let trimmed = replaced.trimmingCharacters(in: .whitespaces).drop { $0 == "." || $0 == "_" }
        let limited = String(trimmed.prefix(maximumFolderNameLength)).trimmingCharacters(in: .whitespaces)
        return limited.isEmpty ? "Без названия" : limited
    }

    // MARK: - Детали

    private func ensureTitleIsFree(_ title: String, exceptPath: String?) throws {
        let clashes = snapshot.pages(titled: title).filter { $0.path != exceptPath }
        if !clashes.isEmpty { throw FolioError.duplicateTitle(title) }
    }

    private func pageContent(title: String, template: String?, now: Date) throws -> String {
        var extraLines: [String] = []
        var body = ""
        if let template {
            let url = snapshot.space.root.appending(path: Self.templatesFolder).appending(path: "\(template).md")
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                throw FolioError.templateNotFound(template)
            }
            let rendered = text
                .replacingOccurrences(of: "{{title}}", with: title)
                .replacingOccurrences(of: "{{date}}", with: DateText.russian(now))
                .replacingOccurrences(of: "{{iso_date}}", with: DateText.iso(now))
            let document = PageDocument.parse(rendered)
            extraLines = FrontmatterWriter.lines(of: document.rawFrontmatter ?? "", excluding: ["id", "title", "created"])
            body = document.body
        }
        let lines = [
            "id: \(PageID.make())",
            "title: \(FrontmatterWriter.scalar(title))",
            "created: \(DateText.iso(now))",
        ] + extraLines
        return FrontmatterWriter.document(frontmatterLines: lines, body: body)
    }

    private func rewriteTitle(of path: String, to title: String) throws {
        let url = snapshot.fileURL(for: path)
        let document = PageDocument.parse(try String(contentsOf: url, encoding: .utf8))
        let lines = FrontmatterWriter.replacingField(
            "title",
            with: FrontmatterWriter.scalar(title),
            in: document.rawFrontmatter ?? "id: \(PageID.make())"
        )
        let content = FrontmatterWriter.document(frontmatterLines: lines, body: document.body)
        try Data(content.utf8).write(to: url, options: .atomic)
    }

    /// Возвращает ключи переписанных файлов вида `<id пространства>/<путь>`.
    private func rewriteLinks(from oldTitle: String, to newTitle: String, library: LibrarySnapshot) throws -> Set<String> {
        let oldKey = TitleKey.make(oldTitle)
        let spaceKey = TitleKey.make(snapshot.space.name)
        let spaces = library.snapshot(for: snapshot.space.id) == nil ? library.spaces + [snapshot] : library.spaces
        var updated = Set<String>()

        for other in spaces {
            let isSameSpace = other.space.id == snapshot.space.id
            for otherPath in other.pages.keys {
                let url = other.fileURL(for: otherPath)
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                let rewritten = WikiLinkParser.rewrite(text, newTitle: newTitle) { link in
                    guard TitleKey.make(link.title) == oldKey else { return false }
                    if let linkSpace = link.space { return TitleKey.make(linkSpace) == spaceKey }
                    return isSameSpace
                }
                guard let rewritten else { continue }
                try Data(rewritten.utf8).write(to: url, options: .atomic)
                updated.insert("\(other.space.id)/\(otherPath)")
            }
        }
        return updated
    }

    private func uniqueFolderName(base: String, in parent: URL, current: String?) -> String {
        var candidate = base
        var counter = 2
        while candidate.lowercased() != current?.lowercased(),
              FileManager.default.fileExists(atPath: String.filePath(parent.appending(path: candidate))) {
            candidate = "\(base) \(counter)"
            counter += 1
        }
        return candidate
    }

    /// На нечувствительном к регистру диске смена одного регистра идёт через временное имя.
    private func renameFolder(_ source: URL, to destination: URL) throws {
        guard source.lastPathComponent.lowercased() == destination.lastPathComponent.lowercased() else {
            try FileManager.default.moveItem(at: source, to: destination)
            return
        }
        let temporary = source.deletingLastPathComponent().appending(path: ".folio-rename-\(UUID().uuidString)")
        try FileManager.default.moveItem(at: source, to: temporary)
        try FileManager.default.moveItem(at: temporary, to: destination)
    }
}
