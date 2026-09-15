import Foundation
import Testing
@testable import FolioCore

@Suite("Запись правок")
struct PageWriterTests {
    private let page = """
        ---
        id: abc123
        title: Протокол
        # комментарий остаётся
        custom: значение
        status: В работе
        status_color: red
        ---

        Старый текст
        """

    @Test("Новое тело не трогает шапку")
    func replacesBodyKeepingFrontmatter() {
        let result = PageWriter.replacingBody(in: page, with: "\n# Новый текст\n\n- пункт\n\n")
        #expect(result == """
            ---
            id: abc123
            title: Протокол
            # комментарий остаётся
            custom: значение
            status: В работе
            status_color: red
            ---

            # Новый текст

            - пункт

            """)
    }

    @Test("Файл без шапки остаётся без шапки")
    func bodyWithoutFrontmatter() {
        #expect(PageWriter.replacingBody(in: "старое", with: "новое") == "новое\n")
        #expect(PageWriter.replacingBody(in: "старое", with: "  ") == "")
    }

    @Test("Смена статуса сбрасывает свой цвет, метки с запятой берутся в кавычки")
    func setsProperties() {
        let result = PageWriter.settingProperties(in: page, status: "На согласовании", labels: ["встреча", "a, b"])
        let document = PageDocument.parse(result)
        #expect(document.frontmatter.status == PageStatus(label: "На согласовании"))
        #expect(document.frontmatter.status?.color == .yellow)
        #expect(document.frontmatter.labels == ["встреча", "a, b"])
        #expect(document.rawFrontmatter?.contains("custom: значение") == true)
        #expect(document.rawFrontmatter?.contains("status_color") == false)
        #expect(document.body == "Старый текст\n")
    }

    @Test("Тот же статус сохраняет свой цвет, пустые значения убирают поля")
    func keepsColorAndRemovesEmpty() {
        let sameStatus = PageDocument.parse(PageWriter.settingProperties(in: page, status: "В работе", labels: []))
        #expect(sameStatus.frontmatter.status == PageStatus(label: "В работе", color: .red))

        let cleared = PageDocument.parse(PageWriter.settingProperties(in: page, status: nil, labels: []))
        #expect(cleared.frontmatter.status == nil)
        #expect(cleared.rawFrontmatter?.contains("status") == false)
        #expect(cleared.frontmatter.title == "Протокол")
    }
}
