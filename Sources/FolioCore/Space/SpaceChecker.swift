import Foundation

public struct CheckIssue: Sendable, Hashable {
    public enum Kind: String, Sendable, CaseIterable {
        case duplicateTitle
        case brokenLink
        case missingAttachment
        case invalidFrontmatter
        case missingFrontmatter
        case strayFile
    }

    public let kind: Kind
    /// Путь страницы; у главной — «(главная)».
    public let path: String
    public let message: String
}

/// Проверка пространства на то, что ломает вики: дубли, битые ссылки, потерянные вложения.
public enum SpaceChecker {
    static let homeLabel = "(главная)"
    static let ignoredMarkdownFiles: Set<String> = [SpaceScanner.pageFileName, "CLAUDE.md"]

    public static func check(_ snapshot: SpaceSnapshot, library: LibrarySnapshot) -> [CheckIssue] {
        let duplicates = snapshot.duplicateTitles.map { duplicate in
            CheckIssue(
                kind: .duplicateTitle,
                path: duplicate.paths.map(displayPath).joined(separator: ", "),
                message: "заголовок «\(duplicate.title)» носят несколько страниц"
            )
        }
        let pageIssues = snapshot.pages.keys.sorted().flatMap { path in
            issues(forPage: path, snapshot: snapshot, library: library)
        }
        return duplicates + pageIssues
    }

    private static func displayPath(_ path: String) -> String {
        path.isEmpty ? homeLabel : path
    }

    private static func issues(forPage path: String, snapshot: SpaceSnapshot, library: LibrarySnapshot) -> [CheckIssue] {
        let shownPath = displayPath(path)
        guard let text = try? String(contentsOf: snapshot.fileURL(for: path), encoding: .utf8) else {
            return [CheckIssue(kind: .invalidFrontmatter, path: shownPath, message: "файл не читается как UTF-8")]
        }
        let document = PageDocument.parse(text)
        var issues: [CheckIssue] = []

        if let error = document.frontmatterError {
            issues.append(CheckIssue(kind: .invalidFrontmatter, path: shownPath, message: "шапка не разбирается: \(error)"))
        } else if document.frontmatter.id == nil || document.frontmatter.title == nil {
            issues.append(CheckIssue(kind: .missingFrontmatter, path: shownPath, message: "в шапке нет id или title"))
        }

        let brokenLinks = Set(WikiLinkParser.links(in: document.body))
            .filter { library.resolve($0, from: snapshot.space.id) == nil }
            .map(\.markdown)
            .sorted()
        issues += brokenLinks.map { CheckIssue(kind: .brokenLink, path: shownPath, message: "битая ссылка \($0)") }

        let folder = snapshot.folderURL(for: path)
        let missingFiles = Set(AttachmentReferences.relativePaths(in: document.body))
            .filter { !FileManager.default.fileExists(atPath: String.filePath(folder.appending(path: $0))) }
            .sorted()
        issues += missingFiles.map { CheckIssue(kind: .missingAttachment, path: shownPath, message: "нет файла вложения \($0)") }

        return issues + strayFiles(in: folder, shownPath: shownPath)
    }

    private static func strayFiles(in folder: URL, shownPath: String) -> [CheckIssue] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return entries.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { entry in
            let name = entry.lastPathComponent
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if !isDirectory, entry.pathExtension == "md", !ignoredMarkdownFiles.contains(name) {
                return CheckIssue(kind: .strayFile, path: shownPath, message: "файл \(name) не страница: страница — папка с index.md")
            }
            guard isDirectory, !name.hasPrefix("_"), !SpaceScanner.isPageFolder(entry) else { return nil }
            let hasMarkdown = ((try? FileManager.default.contentsOfDirectory(atPath: String.filePath(entry))) ?? [])
                .contains { $0.hasSuffix(".md") }
            return hasMarkdown
                ? CheckIssue(kind: .strayFile, path: shownPath, message: "в папке \(name) есть Markdown, но нет index.md — в дереве её не видно")
                : nil
        }
    }
}
