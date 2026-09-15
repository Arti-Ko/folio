import Foundation
import Testing
@testable import FolioCore

@Suite("Имена вложений")
struct AttachmentNamingTests {
    @Test("Пробелы и скобки заменяются, расширение остаётся в нижнем регистре")
    func cleansName() throws {
        let folder = try TemporaryFolder()
        #expect(AttachmentNaming.availableName(for: "Схема процесса (финал).PNG", in: folder.url) == "Схема-процесса-финал.png")
    }

    @Test("Занятое имя получает номер")
    func avoidsCollisions() throws {
        let folder = try TemporaryFolder()
        try Data().write(to: folder.url.appending(path: "ТЗ.pdf"))
        try Data().write(to: folder.url.appending(path: "ТЗ-2.pdf"))
        #expect(AttachmentNaming.availableName(for: "ТЗ.pdf", in: folder.url) == "ТЗ-3.pdf")
    }

    @Test("Снимок из буфера получает имя с датой")
    func namesPastedImages() throws {
        let folder = try TemporaryFolder()
        let date = try #require(ISO8601DateFormatter().date(from: "2026-09-15T20:41:03+05:00"))
        let name = AttachmentNaming.availableName(for: "image.png", in: folder.url, now: date)
        #expect(name.hasPrefix("Вставка-2026-09-15-"))
        #expect(name.hasSuffix(".png"))
        #expect(!name.contains(" "))
    }
}
