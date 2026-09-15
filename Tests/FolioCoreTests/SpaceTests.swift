import Foundation
import Testing
@testable import FolioCore

@Suite("Дерево пространства")
struct ScannerTests {
    @Test("Строит дерево с порядком, запасными заголовками и без служебных папок")
    func buildsTree() throws {
        let folder = try TemporaryFolder()
        let space = try Fixture.space(named: "Работа", in: folder)
        try Fixture.writePage(in: space, path: "Бета", title: "Бета", body: "")
        try Fixture.writePage(in: space, path: "Альфа", title: "Альфа", body: "")
        try Fixture.writePage(in: space, path: "Первая", title: "Закреплённая", extra: ["order: 1"], body: "")
        try Fixture.writePage(in: space, path: "Альфа/Без шапки", title: nil, body: "")
        try Fixture.writePage(in: space, path: "_Шаблоны/Скрытая", title: "Скрытая", body: "")
        try FileManager.default.createDirectory(at: space.root.appending(path: "Просто папка"), withIntermediateDirectories: true)

        let snapshot = SpaceScanner.scan(space)

        #expect(snapshot.home.title == "Работа")
        #expect(snapshot.home.children.map(\.title) == ["Закреплённая", "Альфа", "Бета"])
        #expect(snapshot.page(at: "Альфа/Без шапки")?.title == "Без шапки")
        #expect(snapshot.pages.count == 5)
        #expect(snapshot.ancestors(of: "Альфа/Без шапки").map(\.title) == ["Работа", "Альфа"])
    }

    @Test("Находит дубли заголовков без учёта регистра")
    func duplicates() throws {
        let folder = try TemporaryFolder()
        let space = try Fixture.space(named: "Работа", in: folder)
        try Fixture.writePage(in: space, path: "A", title: "Встреча", body: "")
        try Fixture.writePage(in: space, path: "B", title: "встреча", body: "")

        let snapshot = SpaceScanner.scan(space)

        #expect(snapshot.duplicateTitles.count == 1)
        #expect(throws: FolioError.ambiguousTitle("Встреча", paths: ["A", "B"])) {
            try snapshot.uniquePage(titled: "Встреча")
        }
    }
}

@Suite("Операции со страницами")
struct PageOperationsTests {
    @Test("Создаёт страницу по шаблону")
    func createsFromTemplate() throws {
        let folder = try TemporaryFolder()
        let space = try Fixture.space(named: "Работа", in: folder)
        let templates = space.root.appending(path: PageOperations.templatesFolder)
        try FileManager.default.createDirectory(at: templates, withIntermediateDirectories: true)
        let template = "---\ntitle: Шаблон\nstatus: Черновик\nlabels: [встреча]\n---\n\n# {{title}}\n\nДата: {{date}}\n"
        try Data(template.utf8).write(to: templates.appending(path: "Встреча.md"))

        let operations = PageOperations(snapshot: SpaceScanner.scan(space))
        #expect(operations.templateNames() == ["Встреча"])
        let path = try operations.createPage(title: "Встреча: заказчик", parentPath: "", template: "Встреча")

        #expect(path == "Встреча- заказчик")
        let document = PageDocument.parse(try Fixture.read(space, path))
        #expect(document.frontmatter.title == "Встреча: заказчик")
        #expect(document.frontmatter.status?.label == "Черновик")
        #expect(document.frontmatter.labels == ["встреча"])
        #expect(document.frontmatter.id?.count == 12)
        #expect(document.body.hasPrefix("# Встреча: заказчик\n\nДата: "))
        #expect(!document.body.contains("{{"))
    }

    @Test("Не создаёт дубль и страницу с запрещёнными символами")
    func rejectsInvalidTitles() throws {
        let folder = try TemporaryFolder()
        let space = try Fixture.space(named: "Работа", in: folder)
        try Fixture.writePage(in: space, path: "Требования", title: "Требования", body: "")
        let operations = PageOperations(snapshot: SpaceScanner.scan(space))

        #expect(throws: FolioError.duplicateTitle("требования")) {
            try operations.createPage(title: "требования", parentPath: "")
        }
        #expect(throws: FolioError.duplicateTitle("Работа")) {
            try operations.createPage(title: "Работа", parentPath: "")
        }
        #expect(throws: FolioError.self) {
            try operations.createPage(title: "Плохой [заголовок]", parentPath: "")
        }
    }

    @Test("Переносит страницу и не даёт перенести внутрь себя")
    func movesPages() throws {
        let folder = try TemporaryFolder()
        let space = try Fixture.space(named: "Работа", in: folder)
        try Fixture.writePage(in: space, path: "Проекты", title: "Проекты", body: "")
        try Fixture.writePage(in: space, path: "Проекты/CRM", title: "CRM", body: "")
        try Fixture.writePage(in: space, path: "Архив", title: "Архив", body: "")
        let operations = PageOperations(snapshot: SpaceScanner.scan(space))

        #expect(throws: FolioError.moveIntoItself) {
            try operations.movePage(at: "Проекты", toParent: "Проекты/CRM")
        }
        #expect(throws: FolioError.homePageIsFixed) {
            try operations.movePage(at: "", toParent: "Архив")
        }
        #expect(try operations.movePage(at: "Проекты/CRM", toParent: "Архив") == "Архив/CRM")
        #expect(SpaceScanner.scan(space).page(at: "Архив/CRM")?.title == "CRM")
    }

    @Test("Переименование чинит ссылки во всех пространствах")
    func renameRewritesLinks() throws {
        let folder = try TemporaryFolder()
        let work = try Fixture.space(named: "Работа", in: folder)
        let personal = try Fixture.space(named: "Личное", in: folder)
        try Fixture.writePage(in: work, path: "Требования", title: "Требования", body: "Черновик")
        try Fixture.writePage(in: work, path: "Встреча", title: "Встреча", body: "См. [[требования|список]] и [[Работа::Требования]]")
        try Fixture.writePage(in: personal, path: "Заметка", title: "Заметка", body: "[[Работа::Требования]] и [[Требования]]")
        let library = LibrarySnapshot(spaces: [SpaceScanner.scan(work), SpaceScanner.scan(personal)])

        let result = try PageOperations(snapshot: library.spaces[0])
            .renamePage(at: "Требования", to: "Требования к CRM", library: library)

        #expect(result == RenameResult(newPath: "Требования к CRM", updatedFiles: 3))
        #expect(try Fixture.read(work, "Встреча").contains("См. [[Требования к CRM|список]] и [[Работа::Требования к CRM]]"))
        // Ссылка без пространства внутри «Личного» ведёт в «Личное», её не трогаем.
        #expect(try Fixture.read(personal, "Заметка").contains("[[Работа::Требования к CRM]] и [[Требования]]"))
        #expect(PageDocument.parse(try Fixture.read(work, "Требования к CRM")).frontmatter.title == "Требования к CRM")
    }

    @Test("Смена регистра переименовывает и папку")
    func caseOnlyRename() throws {
        let folder = try TemporaryFolder()
        let space = try Fixture.space(named: "Работа", in: folder)
        try Fixture.writePage(in: space, path: "встреча", title: "встреча", body: "")
        let library = LibrarySnapshot(spaces: [SpaceScanner.scan(space)])

        let result = try PageOperations(snapshot: library.spaces[0]).renamePage(at: "встреча", to: "Встреча", library: library)

        #expect(result.newPath == "Встреча")
        let names = try FileManager.default.contentsOfDirectory(atPath: space.rootPath)
        #expect(names.contains("Встреча"))
        #expect(!names.contains("встреча"))
    }
}

@Suite("Проверка и реестр")
struct CheckAndRegistryTests {
    @Test("Находит битые ссылки, потерянные вложения и лишние файлы")
    func findsProblems() throws {
        let folder = try TemporaryFolder()
        let space = try Fixture.space(named: "Работа", in: folder)
        try Fixture.writePage(in: space, path: "Страница", title: "Страница", body: "[[Нет такой]] ![](схема.png) [[Работа]]")
        try Data("черновик".utf8).write(to: space.root.appending(path: "Страница/заметки.md"))
        let snapshot = SpaceScanner.scan(space)

        let issues = SpaceChecker.check(snapshot, library: LibrarySnapshot(spaces: [snapshot]))

        #expect(issues.map(\.kind) == [.brokenLink, .missingAttachment, .strayFile])
        #expect(issues.allSatisfy { $0.path == "Страница" })
    }

    @Test("Запоминает пространства, не пускает дубли имён и видит пропавшие папки")
    func registersSpaces() throws {
        let folder = try TemporaryFolder()
        let registry = SpaceRegistry(fileURL: folder.url.appending(path: "spaces.json"))
        let work = try Fixture.space(named: "Работа", in: folder)
        try registry.register(work)
        #expect(registry.load().spaces.map(\.name) == ["Работа"])

        let clone = Space(manifest: SpaceManifest(name: "работа", icon: "folder"), root: folder.url.appending(path: "Копия"))
        #expect(throws: FolioError.spaceAlreadyRegistered("Работа")) {
            try registry.register(clone)
        }

        try FileManager.default.removeItem(at: work.root)
        #expect(registry.load().missingPaths == [work.rootPath])
        try registry.unregister(path: work.rootPath)
        #expect(registry.load().missingPaths.isEmpty)
    }
}
