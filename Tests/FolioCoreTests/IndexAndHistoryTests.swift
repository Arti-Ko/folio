import Foundation
import Testing
@testable import FolioCore

@Suite("Поиск и обратные ссылки")
struct SearchIndexTests {
    @Test("Находит кириллицу по части слова без учёта регистра")
    func findsCyrillic() async throws {
        let folder = try TemporaryFolder()
        let space = try Fixture.space(named: "Работа", in: folder)
        try Fixture.writePage(in: space, path: "Интеграция", title: "Интеграция с CRM", body: "Требования к ВЫГРУЗКЕ заказов в хранилище")
        let index = try SearchIndex(url: folder.url.appending(path: "index.sqlite"))
        try await index.sync(SpaceScanner.scan(space))

        let hits = try await index.search("выгрузк")

        #expect(hits.map(\.title) == ["Интеграция с CRM"])
        #expect(hits.first?.snippet.contains(SearchIndex.highlightStart) == true)
        #expect(try await index.search("ин").isEmpty)
    }

    @Test("Переиндексирует только изменённое и убирает удалённое")
    func incrementalSync() async throws {
        let folder = try TemporaryFolder()
        let space = try Fixture.space(named: "Работа", in: folder)
        try Fixture.writePage(in: space, path: "A", title: "A", body: "Первый текст")
        try Fixture.writePage(in: space, path: "B", title: "B", body: "Бета текст")
        let index = try SearchIndex(url: folder.url.appending(path: "index.sqlite"))

        #expect(try await index.sync(SpaceScanner.scan(space)) == 3)
        #expect(try await index.sync(SpaceScanner.scan(space)) == 0)

        try Fixture.writePage(in: space, path: "A", title: "A", body: "Новый текст про бюджет")
        #expect(try await index.sync(SpaceScanner.scan(space)) == 1)
        #expect(try await index.search("бюджет").count == 1)

        try FileManager.default.removeItem(at: space.root.appending(path: "B"))
        #expect(try await index.sync(SpaceScanner.scan(space)) == 1)
        #expect(try await index.search("Бета").isEmpty)
    }

    @Test("Обратные ссылки внутри пространства и из другого")
    func backlinks() async throws {
        let folder = try TemporaryFolder()
        let work = try Fixture.space(named: "Работа", in: folder)
        let personal = try Fixture.space(named: "Личное", in: folder)
        try Fixture.writePage(in: work, path: "Требования", title: "Требования", body: "")
        try Fixture.writePage(in: work, path: "Встреча", title: "Встреча", body: "[[Требования]]")
        try Fixture.writePage(in: personal, path: "Заметка", title: "Заметка", body: "[[Работа::требования]]")
        try Fixture.writePage(in: personal, path: "Другая", title: "Другая", body: "[[Требования]]")
        let index = try SearchIndex(url: folder.url.appending(path: "index.sqlite"))
        try await index.sync(SpaceScanner.scan(work))
        try await index.sync(SpaceScanner.scan(personal))

        let hits = try await index.backlinks(to: "Требования", in: work)

        #expect(Set(hits.map(\.title)) == ["Встреча", "Заметка"])
    }

    @Test("Короткий запрос ищет по заголовкам")
    func shortQueryUsesTitles() throws {
        let folder = try TemporaryFolder()
        let space = try Fixture.space(named: "Работа", in: folder)
        try Fixture.writePage(in: space, path: "ТЗ", title: "ТЗ на CRM", body: "")
        try Fixture.writePage(in: space, path: "Другое", title: "Другое", body: "")

        let hits = TitleSearch.hits("тз", in: [SpaceScanner.scan(space)], limit: 10)

        #expect(hits.map(\.title) == ["ТЗ на CRM"])
    }
}

@Suite("Пространство и история в git")
struct GitHistoryTests {
    @Test("Новое рабочее пространство создаётся с историей, шаблонами и справкой")
    func bootstrapCreatesRepository() throws {
        let folder = try TemporaryFolder()
        let space = try SpaceBootstrap.create(at: folder.url.appending(path: "Работа", directoryHint: .isDirectory), name: "Работа", kind: .work)
        let snapshot = SpaceScanner.scan(space)
        let repository = GitRepository(root: space.root)

        #expect(snapshot.home.title == "Работа")
        #expect(snapshot.page(at: "Справка по разметке") != nil)
        #expect(PageOperations(snapshot: snapshot).templateNames() == ["Протокол встречи", "Страница", "Техническое задание", "Требования"])
        #expect(FileManager.default.fileExists(atPath: space.root.appending(path: "CLAUDE.md").path(percentEncoded: false)))
        #expect(try repository.history(of: "index.md").count == 1)
        #expect(try repository.hasChanges() == false)
        #expect(SpaceChecker.check(snapshot, library: LibrarySnapshot(spaces: [snapshot])).isEmpty)
    }

    @Test("История страницы переживает переименование")
    func historyFollowsRename() throws {
        let folder = try TemporaryFolder()
        let space = try SpaceBootstrap.create(at: folder.url.appending(path: "Личное", directoryHint: .isDirectory), name: "Личное", kind: .blank)
        let repository = GitRepository(root: space.root)
        let path = try PageOperations(snapshot: SpaceScanner.scan(space)).createPage(title: "Идеи", parentPath: "")
        let file = space.root.appending(path: path).appending(path: SpaceScanner.pageFileName)
        let body = "\nСписок идей на осень: поехать в горы, дочитать книги, разобраться с оконными функциями в SQL.\n"
        try Data((try String(contentsOf: file, encoding: .utf8) + body).utf8).write(to: file)
        try repository.commitAll(message: "Идеи")

        let library = LibrarySnapshot(spaces: [SpaceScanner.scan(space)])
        let renamed = try PageOperations(snapshot: library.spaces[0]).renamePage(at: path, to: "Идеи на осень", library: library)
        try repository.commitAll(message: "Переименование")

        let history = try repository.history(of: "\(renamed.newPath)/index.md")
        #expect(history.map(\.message) == ["Переименование", "Идеи"])
        #expect(history.last?.path == "Идеи/index.md")
        let original = try repository.contents(of: history[1].path, at: history[1].hash)
        #expect(PageDocument.parse(original).frontmatter.title == "Идеи")
    }
}
