import Foundation
import Testing
@testable import FolioCore

@Suite("Шапка страницы")
struct FrontmatterTests {
    @Test("Читает известные поля")
    func parsesKnownFields() {
        let document = PageDocument.parse("""
            ---
            id: abc123
            title: Протокол встречи
            status: На согласовании
            labels: [встреча, crm, CRM]
            order: 5
            created: 2026-09-15
            ---

            Текст страницы
            """)
        #expect(document.frontmatter.id == "abc123")
        #expect(document.frontmatter.title == "Протокол встречи")
        #expect(document.frontmatter.status == PageStatus(label: "На согласовании", color: .yellow))
        #expect(document.frontmatter.labels == ["встреча", "crm"])
        #expect(document.frontmatter.order == 5)
        #expect(document.frontmatter.created == "2026-09-15")
        #expect(document.body == "Текст страницы")
    }

    @Test("Явный цвет статуса важнее названия")
    func explicitStatusColor() {
        let document = PageDocument.parse("---\nstatus: В работе\nstatus_color: red\n---\n")
        #expect(document.frontmatter.status == PageStatus(label: "В работе", color: .red))
    }

    @Test("Метки можно перечислить через запятую")
    func labelsFromString() {
        #expect(PageDocument.parse("---\nlabels: встреча, crm\n---\n").frontmatter.labels == ["встреча", "crm"])
    }

    @Test("Понимает переводы строк Windows")
    func windowsLineEndings() {
        let document = PageDocument.parse("---\r\ntitle: Страница\r\n---\r\n\r\nТекст\r\n")
        #expect(document.frontmatter.title == "Страница")
        #expect(document.body == "Текст\n")
    }

    @Test("Сломанная шапка не теряет текст")
    func invalidYaml() {
        let document = PageDocument.parse("---\ntitle: [незакрыто\n---\nТекст")
        #expect(document.frontmatterError != nil)
        #expect(document.body == "Текст")
    }

    @Test("Без шапки весь файл — тело страницы")
    func noFrontmatter() {
        let document = PageDocument.parse("# Заголовок\n\nТекст")
        #expect(document.rawFrontmatter == nil)
        #expect(document.body == "# Заголовок\n\nТекст")
    }

    @Test("Незакрытая шапка считается текстом")
    func unclosedFrontmatter() {
        #expect(PageDocument.parse("---\ntitle: Страница\nТекст").rawFrontmatter == nil)
    }

    @Test("Кавычки ставятся только там, где без них YAML прочитает иначе", arguments: [
        ("Протокол встречи", "Протокол встречи"),
        ("Встреча: заказчик", "\"Встреча: заказчик\""),
        ("2026", "\"2026\""),
        ("2026-09-15 созвон", "\"2026-09-15 созвон\""),
        ("yes", "\"yes\""),
        ("Цитата \"клиента\"", "Цитата \"клиента\""),
        ("#тег", "\"#тег\""),
    ])
    func scalarQuoting(value: String, expected: String) {
        #expect(FrontmatterWriter.scalar(value) == expected)
        #expect(PageDocument.parse("---\ntitle: \(expected)\n---\n").frontmatter.title == value)
    }

    @Test("Замена поля не трогает остальные строки")
    func replacingField() {
        let multiline = "id: abc\ntitle: >\n  Длинный\n  заголовок\nlabels: [a]"
        #expect(FrontmatterWriter.replacingField("title", with: "Новый", in: multiline) == ["id: abc", "title: Новый", "labels: [a]"])
        #expect(FrontmatterWriter.replacingField("title", with: "Новый", in: "id: abc\nlabels: [a]") == ["id: abc", "title: Новый", "labels: [a]"])
    }

    @Test("Отбрасывает указанные поля вместе с продолжением")
    func excludingKeys() {
        let yaml = "id: abc\ntitle: Шаблон\nlabels:\n  - встреча\nstatus: Черновик"
        #expect(FrontmatterWriter.lines(of: yaml, excluding: ["id", "title"]) == ["labels:", "  - встреча", "status: Черновик"])
    }
}
