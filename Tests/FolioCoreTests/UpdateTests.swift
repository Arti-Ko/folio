import Foundation
import Testing
@testable import FolioCore

@Suite("Версии и выпуски")
struct UpdateTests {
    @Test("Разбор номера версии", arguments: [
        ("1.2.3", [1, 2, 3]),
        ("v2.0", [2, 0]),
        ("1.4.0-beta.1", [1, 4, 0]),
        (" 3 ", [3]),
    ])
    func parsesVersion(input: String, expected: [Int]) {
        #expect(AppVersion(input)?.components == expected)
    }

    @Test("Мусор не считается версией", arguments: ["", "v", "1..2", "latest", "1.x"])
    func rejectsGarbage(input: String) {
        #expect(AppVersion(input) == nil)
    }

    @Test("Версии сравниваются по числам, а не по строкам")
    func comparesNumerically() throws {
        #expect(try #require(AppVersion("1.10.0")) > #require(AppVersion("1.9.9")))
        #expect(try #require(AppVersion("1.2")) == #require(AppVersion("1.2.0")))
        #expect(try #require(AppVersion("2.0.0")) > #require(AppVersion("1.99")))
        #expect(Set([AppVersion("1.2"), AppVersion("1.2.0")]).count == 1)
    }

    @Test("Выпуск с архивом разбирается")
    func parsesRelease() throws {
        let release = try #require(try ReleaseFeed.parse(releaseJSON()))
        #expect(release.version == AppVersion("1.2.0"))
        #expect(release.archiveURL.lastPathComponent == "Folio.zip")
        #expect(release.archiveSize == 1234)
        #expect(release.notes == "Что нового")
    }

    @Test("Пререлиз не предлагается к установке")
    func ignoresPrerelease() throws {
        #expect(try ReleaseFeed.parse(releaseJSON(prerelease: true)) == nil)
    }

    @Test("Выпуск без архива приложения — ошибка")
    func missingArchiveThrows() {
        #expect(throws: UpdateError.missingArchive) {
            try ReleaseFeed.parse(releaseJSON(assets: "[]"))
        }
    }

    @Test("В окне обновления нет инструкции по установке, заголовки жирные")
    func cleansNotesForUpdateWindow() {
        let notes = "## Что нового\n\n- Поиск быстрее\n\n## Установка\n\n1. Скачайте DMG\n"
        #expect(ReleaseFeed.displayNotes(notes) == "**Что нового**\n\n- Поиск быстрее")
    }

    private func releaseJSON(tag: String = "v1.2.0", prerelease: Bool = false, assets: String? = nil) -> Data {
        let defaultAssets = #"""
        [{"name":"Folio.dmg","browser_download_url":"https://github.com/Arti-Ko/folio/releases/download/v1.2.0/Folio.dmg","size":2000},
         {"name":"Folio.zip","browser_download_url":"https://github.com/Arti-Ko/folio/releases/download/v1.2.0/Folio.zip","size":1234}]
        """#
        let json = #"""
        {"tag_name":"\#(tag)","body":"Что нового","html_url":"https://github.com/Arti-Ko/folio/releases/tag/\#(tag)",
         "draft":false,"prerelease":\#(prerelease),"assets":\#(assets ?? defaultAssets)}
        """#
        return Data(json.utf8)
    }
}

@Suite("Подмена приложения при обновлении")
struct UpdateInstallerTests {
    private let root = FileManager.default.temporaryDirectory
        .appending(path: "folio-swap-\(UUID().uuidString)", directoryHint: .isDirectory)

    @Test("Новая версия заменяет старую, временные файлы убираются")
    func replacesBundle() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appending(path: "Applications/Folio.app", directoryHint: .isDirectory)
        let staging = root.appending(path: "staging", directoryHint: .isDirectory)
        let staged = staging.appending(path: "Folio.app", directoryHint: .isDirectory)
        try makeBundle(at: target, marker: "old")
        try makeBundle(at: staged, marker: "new")

        #expect(try runSwap(target: target, staged: staged, staging: staging) == 0)

        #expect(try marker(in: target) == "new")
        #expect(!FileManager.default.fileExists(atPath: target.plainPath + ".previous"))
        #expect(!FileManager.default.fileExists(atPath: staging.plainPath))
    }

    @Test("Если копирование не удалось, старая версия возвращается на место")
    func restoresOldBundleOnFailure() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appending(path: "Applications/Folio.app", directoryHint: .isDirectory)
        let staging = root.appending(path: "staging", directoryHint: .isDirectory)
        let missing = staging.appending(path: "Folio.app", directoryHint: .isDirectory)
        try makeBundle(at: target, marker: "old")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        _ = try runSwap(target: target, staged: missing, staging: staging)

        #expect(try marker(in: target) == "old")
        #expect(!FileManager.default.fileExists(atPath: target.plainPath + ".previous"))
    }

    /// Сеть и опубликованный выпуск: FOLIO_UPDATE_E2E=1 swift test --filter UpdateInstallerTests
    @Test("Опубликованный выпуск скачивается и проходит проверку",
          .enabled(if: ProcessInfo.processInfo.environment["FOLIO_UPDATE_E2E"] != nil))
    func downloadsPublishedRelease() async throws {
        let release = try #require(try await ReleaseFeed.latest())
        let app = try await UpdateInstaller.download(release, expectedBundleID: "org.sleepycoffee.folio") { _ in }
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }

        #expect(FileManager.default.isExecutableFile(atPath: app.appending(path: "Contents/MacOS/FolioApp").plainPath))
        #expect(FileManager.default.isExecutableFile(atPath: app.appending(path: "Contents/MacOS/folio").plainPath))
    }

    private func makeBundle(at url: URL, marker: String) throws {
        let contents = url.appending(path: "Contents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try Data(marker.utf8).write(to: contents.appending(path: "marker"))
    }

    private func marker(in bundle: URL) throws -> String {
        try String(contentsOf: bundle.appending(path: "Contents/marker"), encoding: .utf8)
    }

    private func runSwap(target: URL, staged: URL, staging: URL) throws -> Int32 {
        let script = root.appending(path: "install.sh")
        try UpdateInstaller.swapScript.write(to: script, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // PID вне допустимого диапазона macOS: скрипту не нужно ждать выхода приложения.
        process.arguments = [
            script.plainPath, "999999",
            target.plainPath, staged.plainPath, staging.plainPath,
            "--no-launch",
        ]
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
