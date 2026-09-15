import ArgumentParser
import FolioCore
import Foundation

@main
struct FolioCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "folio",
        abstract: "Вики Folio из терминала: страницы, поиск, проверка и история.",
        subcommands: [
            SpacesCommand.self,
            InitCommand.self,
            AddCommand.self,
            TreeCommand.self,
            PathCommand.self,
            OpenCommand.self,
            NewCommand.self,
            RenameCommand.self,
            MoveCommand.self,
            DeleteCommand.self,
            SearchCommand.self,
            BacklinksCommand.self,
            HistoryCommand.self,
            CheckCommand.self,
            CommitCommand.self,
            ReindexCommand.self,
        ]
    )
}

struct SpaceOptions: ParsableArguments {
    @Option(name: [.short, .long], help: "Имя пространства. Внутри папки пространства можно не указывать.")
    var space: String?
}

extension SpaceKind: ExpressibleByArgument {}

/// Подключённые пространства, отсканированные на момент запуска команды.
struct Workspace {
    let library: LibrarySnapshot

    static func load() -> Workspace {
        let spaces = SpaceRegistry().load().spaces
        return Workspace(library: LibrarySnapshot(spaces: spaces.map(SpaceScanner.scan)))
    }

    func space(_ name: String?) throws -> SpaceSnapshot {
        if let name {
            guard let snapshot = library.snapshot(named: name) else { throw FolioError.spaceNotFound(name) }
            return snapshot
        }
        let currentPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).standardizedFileURL.path(percentEncoded: false)
        let normalizedPath = currentPath.count > 1 && currentPath.hasSuffix("/") ? String(currentPath.dropLast()) : currentPath
        if let match = library.spaces.first(where: { $0.space.contains(path: normalizedPath) }) {
            return match
        }
        if library.spaces.count == 1, let only = library.spaces.first {
            return only
        }
        guard !library.spaces.isEmpty else {
            throw ValidationError("Пространств нет. Создай его: folio init <папка> --name <имя>")
        }
        let names = library.spaces.map(\.space.name).joined(separator: ", ")
        throw ValidationError("Укажи пространство через --space: \(names)")
    }

    /// Страница по заголовку, а если заголовок не нашёлся — по пути папки.
    func page(_ reference: String, in snapshot: SpaceSnapshot) throws -> PageNode {
        if let page = try? snapshot.uniquePage(titled: reference) {
            return page
        }
        let path = reference.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !path.isEmpty, let page = snapshot.page(at: path) {
            return page
        }
        return try snapshot.uniquePage(titled: reference)
    }

    func syncedIndex() async throws -> SearchIndex {
        let index = try SearchIndex(url: FolioPaths.indexURL)
        for snapshot in library.spaces {
            try await index.sync(snapshot)
        }
        return index
    }

    func describe(_ ref: PageRef) -> String {
        guard let snapshot = library.snapshot(for: ref.spaceID) else { return ref.path }
        return ref.path.isEmpty ? snapshot.space.name : "\(snapshot.space.name) / \(ref.path)"
    }
}

func filePath(_ url: URL) -> String {
    url.path(percentEncoded: false)
}

func relativePageFile(_ path: String) -> String {
    path.isEmpty ? SpaceScanner.pageFileName : "\(path)/\(SpaceScanner.pageFileName)"
}

// MARK: - Пространства

struct SpacesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "spaces", abstract: "Подключённые пространства.")

    func run() async throws {
        let result = SpaceRegistry().load()
        if result.spaces.isEmpty && result.missingPaths.isEmpty {
            print("Пространств нет. Создай его: folio init <папка> --name <имя>")
            return
        }
        for space in result.spaces {
            print("\(space.name)\t\(SpaceScanner.scan(space).pages.count) стр.\t\(space.rootPath)")
        }
        for path in result.missingPaths {
            print("папка пропала\t\(path)")
        }
    }
}

struct InitCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "init", abstract: "Создать пространство в пустой папке и подключить его.")

    @Argument(help: "Папка пространства.")
    var folder: String

    @Option(help: "Имя пространства.")
    var name: String

    @Option(help: "Тип: work, personal или blank.")
    var kind: SpaceKind = .blank

    @Option(help: "Значок из SF Symbols.")
    var icon: String?

    func run() async throws {
        let registry = SpaceRegistry()
        let nameKey = TitleKey.make(name)
        if let clash = registry.load().spaces.first(where: { TitleKey.make($0.name) == nameKey }) {
            throw FolioError.spaceAlreadyRegistered(clash.name)
        }
        let url = URL(fileURLWithPath: NSString(string: folder).expandingTildeInPath, isDirectory: true)
        let space = try SpaceBootstrap.create(at: url, name: name, icon: icon, kind: kind)
        try registry.register(space)
        print("Создано пространство «\(space.name)»: \(space.rootPath)")
    }
}

struct AddCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "add", abstract: "Подключить существующее пространство.")

    @Argument(help: "Папка пространства.")
    var folder: String

    func run() async throws {
        let url = URL(fileURLWithPath: NSString(string: folder).expandingTildeInPath, isDirectory: true)
        let space = try Space.open(at: url)
        try SpaceRegistry().register(space)
        print("Подключено пространство «\(space.name)»")
    }
}

// MARK: - Страницы

struct TreeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "tree", abstract: "Дерево страниц.")

    @OptionGroup var options: SpaceOptions

    @Option(help: "Показать только ветку этой страницы.")
    var under: String?

    @Option(help: "Сколько уровней показать.")
    var depth: Int?

    @Flag(help: "Показывать пути папок.")
    var paths = false

    func run() async throws {
        let workspace = Workspace.load()
        let snapshot = try workspace.space(options.space)
        let root = try under.map { try workspace.page($0, in: snapshot) } ?? snapshot.home
        print(TreePrinter(showsPaths: paths, maximumDepth: depth).render(root))
    }
}

struct TreePrinter {
    let showsPaths: Bool
    let maximumDepth: Int?

    func render(_ root: PageNode) -> String {
        ([label(for: root, hidesChildren: false)] + lines(for: root.children, prefix: "", depth: 1)).joined(separator: "\n")
    }

    private func lines(for nodes: [PageNode], prefix: String, depth: Int) -> [String] {
        nodes.enumerated().flatMap { index, node -> [String] in
            let isLast = index == nodes.count - 1
            let hidesChildren = maximumDepth.map { depth >= $0 } ?? false
            let line = prefix + (isLast ? "└─ " : "├─ ") + label(for: node, hidesChildren: hidesChildren)
            guard !hidesChildren else { return [line] }
            return [line] + lines(for: node.children, prefix: prefix + (isLast ? "   " : "│  "), depth: depth + 1)
        }
    }

    private func label(for node: PageNode, hidesChildren: Bool) -> String {
        let status = node.status.map { "  [\($0.label)]" } ?? ""
        let hidden = hidesChildren && !node.children.isEmpty ? "  (+\(node.children.count))" : ""
        let path = showsPaths ? "  — \(node.path.isEmpty ? "/" : node.path)" : ""
        return node.title + status + hidden + path
    }
}

struct PathCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "path", abstract: "Путь к файлу страницы.")

    @OptionGroup var options: SpaceOptions

    @Argument(help: "Заголовок страницы.")
    var title: String

    @Flag(help: "Путь папки страницы вместо index.md.")
    var folder = false

    func run() async throws {
        let workspace = Workspace.load()
        let snapshot = try workspace.space(options.space)
        let page = try workspace.page(title, in: snapshot)
        print(filePath(folder ? snapshot.folderURL(for: page.path) : snapshot.fileURL(for: page.path)))
    }
}

struct NewCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "new", abstract: "Создать страницу; печатает путь к index.md.")

    @OptionGroup var options: SpaceOptions

    @Argument(help: "Заголовок новой страницы.")
    var title: String

    @Option(help: "Заголовок родительской страницы; по умолчанию — главная.")
    var parent: String?

    @Option(help: "Шаблон из папки _Шаблоны.")
    var template: String?

    func run() async throws {
        let workspace = Workspace.load()
        let snapshot = try workspace.space(options.space)
        let parentPage = try parent.map { try workspace.page($0, in: snapshot) } ?? snapshot.home
        let path = try PageOperations(snapshot: snapshot).createPage(title: title, parentPath: parentPage.path, template: template)
        print(filePath(snapshot.fileURL(for: path)))
    }
}

struct RenameCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "rename", abstract: "Переименовать страницу и починить ссылки на неё.")

    @OptionGroup var options: SpaceOptions

    @Argument(help: "Текущий заголовок.")
    var title: String

    @Argument(help: "Новый заголовок.")
    var newTitle: String

    func run() async throws {
        let workspace = Workspace.load()
        let snapshot = try workspace.space(options.space)
        let page = try workspace.page(title, in: snapshot)
        let result = try PageOperations(snapshot: snapshot).renamePage(at: page.path, to: newTitle, library: workspace.library)
        print("«\(page.title)» → «\(newTitle)», файлов обновлено: \(result.updatedFiles)")
        print(filePath(snapshot.fileURL(for: result.newPath)))
    }
}

struct MoveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "move", abstract: "Перенести страницу к другому родителю.")

    @OptionGroup var options: SpaceOptions

    @Argument(help: "Заголовок страницы.")
    var title: String

    @Option(help: "Заголовок нового родителя; для верхнего уровня — имя пространства.")
    var parent: String

    func run() async throws {
        let workspace = Workspace.load()
        let snapshot = try workspace.space(options.space)
        let page = try workspace.page(title, in: snapshot)
        let parentPage = try workspace.page(parent, in: snapshot)
        let newPath = try PageOperations(snapshot: snapshot).movePage(at: page.path, toParent: parentPage.path)
        print(filePath(snapshot.fileURL(for: newPath)))
    }
}

struct DeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete", abstract: "Переместить страницу с подстраницами в Корзину.")

    @OptionGroup var options: SpaceOptions

    @Argument(help: "Заголовок страницы.")
    var title: String

    func run() async throws {
        let workspace = Workspace.load()
        let snapshot = try workspace.space(options.space)
        let page = try workspace.page(title, in: snapshot)
        try PageOperations(snapshot: snapshot).trashPage(at: page.path)
        print("«\(page.title)» и её подстраницы (\(page.children.count)) перемещены в Корзину")
    }
}

// MARK: - Поиск и связи

struct SearchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "search", abstract: "Полнотекстовый поиск по всем пространствам.")

    @Option(name: [.short, .long], help: "Искать только в этом пространстве.")
    var space: String?

    @Argument(help: "Что искать.")
    var query: String

    @Option(help: "Сколько результатов показать.")
    var limit = 20

    func run() async throws {
        let workspace = Workspace.load()
        let spaces = try space.map { [try workspace.space($0)] } ?? workspace.library.spaces
        let hasIndexableTerm = query.split(whereSeparator: \.isWhitespace).contains { $0.count >= SearchIndex.minimumTermLength }
        let hits = hasIndexableTerm
            ? try await workspace.syncedIndex().search(query, in: spaces.map(\.space.id), limit: limit)
            : TitleSearch.hits(query, in: spaces, limit: limit)

        guard !hits.isEmpty else {
            print("Ничего не найдено")
            return
        }
        for hit in hits {
            print("\(hit.title) — \(workspace.describe(hit.ref))")
            let snippet = hit.snippet
                .replacingOccurrences(of: String(SearchIndex.highlightStart), with: "**")
                .replacingOccurrences(of: String(SearchIndex.highlightEnd), with: "**")
                .split(whereSeparator: \.isNewline)
                .joined(separator: " ")
            if !snippet.isEmpty { print("    \(snippet)") }
        }
    }
}

struct BacklinksCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "backlinks", abstract: "Страницы, которые ссылаются на эту.")

    @OptionGroup var options: SpaceOptions

    @Argument(help: "Заголовок страницы.")
    var title: String

    func run() async throws {
        let workspace = Workspace.load()
        let snapshot = try workspace.space(options.space)
        let page = try workspace.page(title, in: snapshot)
        let hits = try await workspace.syncedIndex().backlinks(to: page.title, in: snapshot.space)
        guard !hits.isEmpty else {
            print("На «\(page.title)» никто не ссылается")
            return
        }
        hits.forEach { print("\($0.title) — \(workspace.describe($0.ref))") }
    }
}

struct HistoryCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "history", abstract: "История правок страницы.")

    @OptionGroup var options: SpaceOptions

    @Argument(help: "Заголовок страницы.")
    var title: String

    @Option(help: "Сколько версий показать.")
    var limit = 30

    func run() async throws {
        let workspace = Workspace.load()
        let snapshot = try workspace.space(options.space)
        let page = try workspace.page(title, in: snapshot)
        let revisions = try GitRepository(root: snapshot.space.root).history(of: relativePageFile(page.path), limit: limit)
        guard !revisions.isEmpty else {
            print("У «\(page.title)» пока нет сохранённых версий — сделай folio commit")
            return
        }
        let style = Date.FormatStyle(date: .numeric, time: .shortened, locale: Locale(identifier: "ru_RU"))
        revisions.forEach { print("\($0.shortHash)  \($0.date.formatted(style))  \($0.message)") }
    }
}

struct CheckCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "check", abstract: "Найти дубли заголовков, битые ссылки и потерянные вложения.")

    @OptionGroup var options: SpaceOptions

    @Flag(help: "Проверить все пространства.")
    var all = false

    func run() async throws {
        let workspace = Workspace.load()
        let targets = all ? workspace.library.spaces : [try workspace.space(options.space)]
        let reports = targets.map { ($0.space.name, SpaceChecker.check($0, library: workspace.library)) }
        for (name, issues) in reports {
            print("«\(name)»: \(issues.isEmpty ? "проблем нет" : "проблем — \(issues.count)")")
            issues.forEach { print("  \($0.path): \($0.message)") }
        }
        if reports.contains(where: { !$0.1.isEmpty }) {
            throw ExitCode(1)
        }
    }
}

struct CommitCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "commit", abstract: "Сохранить изменения пространства снимком в истории.")

    @OptionGroup var options: SpaceOptions

    @Option(name: [.short, .long], help: "Описание снимка.")
    var message: String?

    func run() async throws {
        let snapshot = try Workspace.load().space(options.space)
        let repository = GitRepository(root: snapshot.space.root)
        try repository.initialize()
        let style = Date.FormatStyle(date: .numeric, time: .shortened, locale: Locale(identifier: "ru_RU"))
        let text = message ?? "Правки от \(Date.now.formatted(style))"
        print(try repository.commitAll(message: text) ? "Снимок сохранён: \(text)" : "Изменений нет")
    }
}

struct ReindexCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "reindex", abstract: "Пересобрать индекс поиска с нуля.")

    func run() async throws {
        let base = FolioPaths.indexURL
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: filePath(base) + suffix))
        }
        let workspace = Workspace.load()
        let index = try SearchIndex(url: base)
        for snapshot in workspace.library.spaces {
            let count = try await index.sync(snapshot)
            print("«\(snapshot.space.name)»: проиндексировано страниц — \(count)")
        }
    }
}
