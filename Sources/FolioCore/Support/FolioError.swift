import Foundation

public enum FolioError: LocalizedError, Equatable, Sendable {
    case spaceNotFound(String)
    case notASpace(String)
    case spaceAlreadyRegistered(String)
    case folderNotEmpty(String)
    case pageNotFound(String)
    case ambiguousTitle(String, paths: [String])
    case duplicateTitle(String)
    case invalidTitle(String, reason: String)
    case homePageIsFixed
    case moveIntoItself
    case templateNotFound(String)
    case commandFailed(command: String, message: String)
    case database(String)

    public var errorDescription: String? {
        switch self {
        case .spaceNotFound(let name):
            "Пространство «\(name)» не найдено"
        case .notASpace(let path):
            "Папка \(path) не пространство Folio: в ней нет .folio/space.json"
        case .spaceAlreadyRegistered(let name):
            "Пространство «\(name)» уже подключено"
        case .folderNotEmpty(let path):
            "Папка \(path) не пустая: новое пространство создаётся только в пустой папке"
        case .pageNotFound(let title):
            "Страница «\(title)» не найдена"
        case .ambiguousTitle(let title, let paths):
            "Заголовок «\(title)» встречается несколько раз: \(paths.joined(separator: ", "))"
        case .duplicateTitle(let title):
            "Страница «\(title)» уже есть в этом пространстве, а заголовки должны быть уникальными"
        case .invalidTitle(let title, let reason):
            "Недопустимый заголовок «\(title)»: \(reason)"
        case .homePageIsFixed:
            "Главную страницу пространства нельзя переносить, переименовывать папкой или удалять"
        case .moveIntoItself:
            "Нельзя перенести страницу внутрь неё самой"
        case .templateNotFound(let name):
            "Шаблон «\(name)» не найден в папке _Шаблоны"
        case .commandFailed(let command, let message):
            "\(command): \(message)"
        case .database(let message):
            "Индекс поиска: \(message)"
        }
    }
}
