import Foundation
import Testing
@testable import FolioCore

@Suite("Ссылки на страницы")
struct WikiLinkTests {
    @Test("Разбирает все формы записи")
    func parsesForms() {
        let links = WikiLinkParser.links(in: "[[Протокол]] и [[Личное::Идеи|мои идеи]], [[Встреча: заказчик]]")
        #expect(links == [
            WikiLink(space: nil, title: "Протокол", label: nil),
            WikiLink(space: "Личное", title: "Идеи", label: "мои идеи"),
            WikiLink(space: nil, title: "Встреча: заказчик", label: nil),
        ])
    }

    @Test("Пропускает ссылки внутри кода")
    func skipsCode() {
        let markdown = "Текст [[Живая]]\n\n```\n[[В блоке кода]]\n```\n\nИ `[[в строке кода]]`"
        #expect(WikiLinkParser.links(in: markdown).map(\.title) == ["Живая"])
    }

    @Test("Незакрытый блок кода тянется до конца файла")
    func unclosedFence() {
        #expect(WikiLinkParser.links(in: "[[До]]\n~~~\n[[После]]").map(\.title) == ["До"])
    }

    @Test("Переименование сохраняет текст ссылки и пространство")
    func rewritePreservesLabel() {
        let markdown = "[[Старое]], [[старое|текст]], [[Личное::Старое]], [[Другое]]"
        let result = WikiLinkParser.rewrite(markdown, newTitle: "Новое") { link in
            TitleKey.make(link.title) == "старое" && link.space == nil
        }
        #expect(result == "[[Новое]], [[Новое|текст]], [[Личное::Старое]], [[Другое]]")
        #expect(WikiLinkParser.rewrite(markdown, newTitle: "Новое") { _ in false } == nil)
    }

    @Test("Ключ ссылки строится так же, как в веб-части")
    func keyMatchesWeb() {
        #expect(WikiLink.key(space: nil, title: "  Протокол   Встречи ") == "::протокол встречи")
        #expect(WikiLink.key(space: "Личное", title: "Идеи") == "личное::идеи")
    }

    @Test("Системная ссылка на страницу переживает кириллицу и пробелы")
    func pageLinkRoundTrip() throws {
        let ref = PageRef(spaceID: UUID(), path: "Проекты/Встреча с заказчиком 15.09")
        let url = try #require(PageLink.url(for: ref))
        #expect(PageLink.ref(from: url) == ref)
        #expect(PageLink.ref(from: URL(string: "folio://app/index.html")!) == nil)
    }

    @Test("Находит относительные вложения и пропускает внешние адреса")
    func attachments() {
        let markdown = "![Схема](схема%201.png) [ТЗ](<ТЗ финал.pdf>) ![](https://example.com/a.png) [[Страница]] [якорь](#раздел)"
        #expect(AttachmentReferences.relativePaths(in: markdown) == ["схема 1.png", "ТЗ финал.pdf"])
    }
}
