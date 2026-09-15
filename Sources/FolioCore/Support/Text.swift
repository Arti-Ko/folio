import Foundation

/// Ключ для сравнения заголовков: без учёта регистра и лишних пробелов.
/// Веб-часть строит ключ ссылки по тому же правилу (`wikiLinkKey`).
public enum TitleKey {
    public static func make(_ text: String) -> String {
        collapseWhitespace(text).lowercased()
    }
}

public enum TitleRules {
    static let maximumLength = 200

    /// Возвращает заголовок без лишних пробелов или объясняет, почему он не подходит.
    public static func validate(_ title: String) throws -> String {
        let cleaned = collapseWhitespace(title)
        guard !cleaned.isEmpty else {
            throw FolioError.invalidTitle(title, reason: "заголовок пустой")
        }
        guard !cleaned.contains(where: { "[]|".contains($0) }) else {
            throw FolioError.invalidTitle(title, reason: "символы [ ] | ломают ссылки на страницу")
        }
        guard !cleaned.contains("::") else {
            throw FolioError.invalidTitle(title, reason: "«::» в ссылках отделяет пространство от страницы")
        }
        guard cleaned.count <= maximumLength else {
            throw FolioError.invalidTitle(title, reason: "длиннее \(maximumLength) символов")
        }
        return cleaned
    }
}

enum PagePath {
    static func join(_ parent: String, _ name: String) -> String {
        parent.isEmpty ? name : "\(parent)/\(name)"
    }

    static func parent(of path: String) -> String? {
        guard !path.isEmpty else { return nil }
        guard let slash = path.lastIndex(of: "/") else { return "" }
        return String(path[..<slash])
    }

    static func name(of path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? ""
    }
}

enum PageID {
    static func make() -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(12))
    }
}

enum DateText {
    static func iso(_ date: Date) -> String {
        format(date, pattern: "yyyy-MM-dd")
    }

    static func russian(_ date: Date) -> String {
        format(date, pattern: "dd.MM.yyyy")
    }

    private static func format(_ date: Date, pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}

func collapseWhitespace(_ text: String) -> String {
    text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }

    /// Путь файла без процентного кодирования и без завершающего слеша.
    static func filePath(_ url: URL) -> String {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
