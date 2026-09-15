import AppKit
import FolioCore
import Observation
import os

/// Все подключённые пространства: дерево страниц, наблюдение за файлами, индекс поиска и операции.
@MainActor
@Observable
final class LibraryModel {
    private(set) var snapshots: [SpaceSnapshot] = []
    private(set) var missingPaths: [String] = []
    private(set) var isLoaded = false
    /// Растёт при изменении файлов: открытые страницы перечитываются.
    private(set) var contentRevision = 0
    /// Растёт после обновления индекса: пересчитываются поиск и обратные ссылки.
    private(set) var indexRevision = 0
    var errorMessage: String?

    @ObservationIgnored private let registry = SpaceRegistry()
    @ObservationIgnored private var index: SearchIndex?
    @ObservationIgnored private var watchers: [UUID: FileWatcher] = [:]
    @ObservationIgnored private var rescanTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private let logger = Logger(subsystem: "org.sleepycoffee.folio", category: "library")

    private static let rescanDelay: Duration = .milliseconds(200)
    private static let searchLimit = 60

    init() {
        do {
            index = try SearchIndex(url: FolioPaths.indexURL)
        } catch {
            logger.error("Индекс не открылся: \(error.localizedDescription, privacy: .public)")
        }
        Task { await reload() }
    }

    var librarySnapshot: LibrarySnapshot {
        LibrarySnapshot(spaces: snapshots)
    }

    func snapshot(for id: UUID) -> SpaceSnapshot? {
        snapshots.first { $0.space.id == id }
    }

    func node(for ref: PageRef) -> PageNode? {
        snapshot(for: ref.spaceID)?.page(at: ref.path)
    }

    /// Страницу переименовали или перенесли снаружи: находим её по id из шапки.
    func relocate(pageID: String, in spaceID: UUID) -> PageRef? {
        snapshot(for: spaceID)?.pages.values.first { $0.pageID == pageID }?.id
    }

    func report(_ error: any Error) {
        errorMessage = error.localizedDescription
    }

    // MARK: - Загрузка и наблюдение

    func reload() async {
        let registry = registry
        let loaded = await Task.detached(priority: .userInitiated) {
            let result = registry.load()
            return (spaces: result.spaces.map(SpaceScanner.scan), missing: result.missingPaths)
        }.value
        snapshots = loaded.spaces
        missingPaths = loaded.missing
        isLoaded = true
        contentRevision += 1
        restartWatchers()
        await syncIndex(snapshots)
    }

    private func restartWatchers() {
        let ids = Set(snapshots.map(\.space.id))
        watchers = watchers.filter { ids.contains($0.key) }
        for snapshot in snapshots where watchers[snapshot.space.id] == nil {
            let id = snapshot.space.id
            watchers[id] = FileWatcher(path: snapshot.space.rootPath) { [weak self] paths in
                guard paths.contains(where: FileWatcher.isRelevant) else { return }
                Task { @MainActor in self?.scheduleRescan(of: id) }
            }
        }
    }

    private func scheduleRescan(of id: UUID) {
        rescanTasks[id]?.cancel()
        rescanTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: Self.rescanDelay)
            guard !Task.isCancelled else { return }
            await self?.rescan(id)
        }
    }

    private func rescan(_ id: UUID) async {
        guard let space = snapshot(for: id)?.space else { return }
        let fresh = await Task.detached(priority: .utility) { SpaceScanner.scan(space) }.value
        replace(fresh)
        await syncIndex([fresh])
    }

    func rescanNow(_ id: UUID) {
        guard let space = snapshot(for: id)?.space else { return }
        let fresh = SpaceScanner.scan(space)
        replace(fresh)
        Task { await syncIndex([fresh]) }
    }

    private func replace(_ fresh: SpaceSnapshot) {
        snapshots = snapshots.map { $0.space.id == fresh.space.id ? fresh : $0 }
        contentRevision += 1
    }

    private func syncIndex(_ targets: [SpaceSnapshot]) async {
        guard let index else { return }
        do {
            for snapshot in targets {
                try await index.sync(snapshot)
            }
            indexRevision += 1
        } catch {
            logger.error("Индекс не обновился: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Поиск

    func search(_ query: String) async -> [SearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let hasIndexableTerm = trimmed.split(whereSeparator: \.isWhitespace).contains { $0.count >= SearchIndex.minimumTermLength }
        guard hasIndexableTerm, let index else {
            return TitleSearch.hits(trimmed, in: snapshots, limit: Self.searchLimit)
        }
        do {
            return try await index.search(trimmed, limit: Self.searchLimit)
        } catch {
            logger.error("Поиск не удался: \(error.localizedDescription, privacy: .public)")
            return TitleSearch.hits(trimmed, in: snapshots, limit: Self.searchLimit)
        }
    }

    func backlinks(for ref: PageRef) async -> [SearchHit] {
        guard let index, let snapshot = snapshot(for: ref.spaceID), let node = snapshot.page(at: ref.path) else { return [] }
        let hits = (try? await index.backlinks(to: node.title, in: snapshot.space)) ?? []
        return hits.filter { $0.ref != ref }
    }

    // MARK: - Страницы

    func templates(for spaceID: UUID) -> [String] {
        snapshot(for: spaceID).map { PageOperations(snapshot: $0).templateNames() } ?? []
    }

    func createPage(title: String, under parent: PageRef, template: String?) throws -> PageRef {
        let snapshot = try requireSnapshot(parent.spaceID)
        let path = try PageOperations(snapshot: snapshot).createPage(title: title, parentPath: parent.path, template: template)
        rescanNow(parent.spaceID)
        return PageRef(spaceID: parent.spaceID, path: path)
    }

    func renamePage(_ ref: PageRef, to title: String) throws -> PageRef {
        let snapshot = try requireSnapshot(ref.spaceID)
        let result = try PageOperations(snapshot: snapshot).renamePage(at: ref.path, to: title, library: librarySnapshot)
        // Ссылки могли поменяться в любом пространстве.
        snapshots.map(\.space.id).forEach(rescanNow)
        return PageRef(spaceID: ref.spaceID, path: result.newPath)
    }

    func trashPage(_ ref: PageRef) throws {
        let snapshot = try requireSnapshot(ref.spaceID)
        try PageOperations(snapshot: snapshot).trashPage(at: ref.path)
        rescanNow(ref.spaceID)
    }

    /// Сохраняет снимок всех изменений пространства; `false`, если сохранять нечего.
    @discardableResult
    func commitChanges(in spaceID: UUID) async -> Bool {
        guard let root = snapshot(for: spaceID)?.space.root else { return false }
        let message = "Снимок от \(Date.now.formatted(date: .numeric, time: .shortened))"
        let result = await Task.detached(priority: .userInitiated) {
            Result { try GitRepository(root: root).commitAll(message: message) }
        }.value
        switch result {
        case .success(let didCommit):
            contentRevision += 1
            return didCommit
        case .failure(let error):
            report(error)
            return false
        }
    }

    func fileURL(for ref: PageRef) -> URL? {
        snapshot(for: ref.spaceID)?.fileURL(for: ref.path)
    }

    func revealInFinder(_ ref: PageRef) {
        guard let url = fileURL(for: ref) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copyPath(_ ref: PageRef) {
        guard let url = fileURL(for: ref) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path(percentEncoded: false), forType: .string)
    }

    /// Ссылка из текста страницы: внешний адрес открывается в браузере, относительный путь — файлом рядом со страницей.
    func openLink(_ href: String, from ref: PageRef) {
        if let url = URL(string: href), let scheme = url.scheme?.lowercased() {
            guard ["http", "https", "mailto"].contains(scheme) else { return }
            NSWorkspace.shared.open(url)
            return
        }
        guard let snapshot = snapshot(for: ref.spaceID) else { return }
        let relative = href.split(separator: "#", maxSplits: 1).first.map(String.init) ?? href
        let target = snapshot.folderURL(for: ref.path)
            .appending(path: relative.removingPercentEncoding ?? relative)
            .standardizedFileURL
        let targetPath = target.path(percentEncoded: false)
        var isDirectory: ObjCBool = false
        guard snapshot.space.contains(path: targetPath), FileManager.default.fileExists(atPath: targetPath, isDirectory: &isDirectory) else {
            errorMessage = "Файл «\(relative)» не найден рядом со страницей"
            return
        }
        // Программы и скрипты из текста страницы не запускаем — только показываем в Finder.
        let isRunnable = Self.runnableExtensions.contains(target.pathExtension.lowercased())
            || (!isDirectory.boolValue && FileManager.default.isExecutableFile(atPath: targetPath))
        if isRunnable || isDirectory.boolValue {
            NSWorkspace.shared.activateFileViewerSelecting([target])
        } else {
            NSWorkspace.shared.open(target)
        }
    }

    private static let runnableExtensions: Set<String> = [
        "app", "command", "sh", "zsh", "bash", "tool", "terminal", "workflow", "action",
        "scpt", "scptd", "applescript", "pkg", "mpkg", "dmg", "jar", "py", "rb", "pl",
        "prefpane", "osax", "webloc", "inetloc", "fileloc", "shortcut",
    ]

    // MARK: - Пространства

    func createDefaultSpaces() async {
        let existingNames = Set(snapshots.map { TitleKey.make($0.space.name) })
        let defaults: [(name: String, kind: SpaceKind)] = [("Работа", .work), ("Личное", .personal)]
        for item in defaults where !existingNames.contains(TitleKey.make(item.name)) {
            let folder = FolioPaths.defaultSpacesFolder.appending(path: item.name, directoryHint: .isDirectory)
            do {
                let space = try (try? Space.open(at: folder)) ?? SpaceBootstrap.create(at: folder, name: item.name, kind: item.kind)
                try registry.register(space)
            } catch {
                report(error)
            }
        }
        await reload()
    }

    func createSpace(name: String, kind: SpaceKind, in parentFolder: URL) async throws {
        let space = try SpaceBootstrap.create(
            at: parentFolder.appending(path: PageOperations.folderName(for: name), directoryHint: .isDirectory),
            name: name,
            kind: kind
        )
        try registry.register(space)
        await reload()
    }

    func chooseAndAddSpace() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Подключить"
        panel.message = "Выберите папку пространства Folio"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try registry.register(try Space.open(at: url))
            Task { await reload() }
        } catch {
            report(error)
        }
    }

    func removeSpace(_ id: UUID) async {
        do {
            try registry.unregister(id: id)
            try await index?.removeSpace(id)
        } catch {
            report(error)
        }
        await reload()
    }

    func forgetMissing(_ path: String) async {
        do {
            try registry.unregister(path: path)
        } catch {
            report(error)
        }
        await reload()
    }

    private func requireSnapshot(_ id: UUID) throws -> SpaceSnapshot {
        guard let snapshot = snapshot(for: id) else { throw FolioError.spaceNotFound(id.uuidString) }
        return snapshot
    }
}
