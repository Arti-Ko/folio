import ArgumentParser
import FolioCore
import Foundation

struct OpenCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "open", abstract: "Открыть страницу в приложении Folio.")

    @OptionGroup var options: SpaceOptions

    @Argument(help: "Заголовок страницы; без него откроется главная пространства.")
    var title: String?

    @Flag(help: "Сразу открыть страницу на правку.")
    var edit = false

    func run() async throws {
        let workspace = Workspace.load()
        let snapshot = try workspace.space(options.space)
        let page = try title.map { try workspace.page($0, in: snapshot) } ?? snapshot.home
        guard let url = PageLink.url(for: page.id, editing: edit) else {
            throw ValidationError("Не удалось построить ссылку на «\(page.title)»")
        }
        let result = try ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/open"), arguments: [url.absoluteString])
        guard result.status == 0 else {
            throw FolioError.commandFailed(command: "open", message: result.error.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
