import Foundation
import Yams

public enum StatusColor: String, Sendable, Codable, CaseIterable {
    case grey, blue, green, yellow, red, purple
}

public struct PageStatus: Sendable, Hashable, Codable {
    public let label: String
    public let color: StatusColor

    public init(label: String, color: StatusColor? = nil) {
        self.label = label
        self.color = color ?? Self.defaultColor(for: label)
    }

    static func defaultColor(for label: String) -> StatusColor {
        switch TitleKey.make(label) {
        case "в работе", "в процессе": .blue
        case "на согласовании", "на ревью", "на проверке", "ожидает": .yellow
        case "утверждено", "согласовано", "готово", "сделано": .green
        case "отклонено", "заблокировано", "отменено": .red
        case "архив", "устарело": .purple
        default: .grey
        }
    }
}

public struct PageFrontmatter: Sendable, Hashable {
    public var id: String?
    public var title: String?
    public var status: PageStatus?
    public var labels: [String]
    public var order: Double?
    public var created: String?

    public init(
        id: String? = nil,
        title: String? = nil,
        status: PageStatus? = nil,
        labels: [String] = [],
        order: Double? = nil,
        created: String? = nil
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.labels = labels
        self.order = order
        self.created = created
    }
}

/// Файл страницы: YAML-шапка между строками `---` и Markdown-тело.
public struct PageDocument: Sendable, Hashable {
    public let frontmatter: PageFrontmatter
    /// Текст шапки без разделителей; `nil`, если шапки нет.
    public let rawFrontmatter: String?
    public let body: String
    public let frontmatterError: String?

    public static func parse(_ text: String) -> PageDocument {
        let unified = text.replacingOccurrences(of: "\r\n", with: "\n")
        let source = unified.hasPrefix("\u{FEFF}") ? String(unified.dropFirst()) : unified
        guard let parts = splitFrontmatter(source) else {
            return PageDocument(frontmatter: PageFrontmatter(), rawFrontmatter: nil, body: source, frontmatterError: nil)
        }
        do {
            return PageDocument(
                frontmatter: try decodeFields(parts.yaml),
                rawFrontmatter: parts.yaml,
                body: parts.body,
                frontmatterError: nil
            )
        } catch {
            return PageDocument(
                frontmatter: PageFrontmatter(),
                rawFrontmatter: parts.yaml,
                body: parts.body,
                frontmatterError: String(describing: error)
            )
        }
    }

    static func splitFrontmatter(_ source: String) -> (yaml: String, body: String)? {
        guard source.hasPrefix("---\n") else { return nil }
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        let closing = lines.indices.dropFirst().first { index in
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            return line == "---" || line == "..."
        }
        guard let closing else { return nil }
        let yaml = lines[1..<closing].joined(separator: "\n")
        let body = lines[(closing + 1)...]
            .drop { $0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: "\n")
        return (yaml, body)
    }

    private static func decodeFields(_ yaml: String) throws -> PageFrontmatter {
        guard !yaml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return PageFrontmatter() }
        guard let fields = try Yams.load(yaml: yaml) as? [String: Any] else {
            throw FrontmatterFormatError()
        }
        let statusColor = scalarString(fields["status_color"]).flatMap(StatusColor.init(rawValue:))
        return PageFrontmatter(
            id: scalarString(fields["id"]),
            title: scalarString(fields["title"]).map(collapseWhitespace),
            status: scalarString(fields["status"]).map { PageStatus(label: $0, color: statusColor) },
            labels: stringList(fields["labels"]),
            order: number(fields["order"]),
            created: scalarString(fields["created"])
        )
    }

    private static func scalarString(_ value: Any?) -> String? {
        switch value {
        case let text as String: text.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        case let date as Date: date.formatted(.iso8601.year().month().day())
        case let flag as Bool: String(flag)
        case let integer as Int: String(integer)
        case let double as Double: String(double)
        default: nil
        }
    }

    private static func stringList(_ value: Any?) -> [String] {
        let items: [String] = switch value {
        case let list as [Any]: list.compactMap(scalarString)
        case let text as String: text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        default: []
        }
        var seen = Set<String>()
        return items.filter { !$0.isEmpty && seen.insert(TitleKey.make($0)).inserted }
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let integer as Int: Double(integer)
        case let double as Double: double
        case let text as String: Double(text)
        default: nil
        }
    }
}

struct FrontmatterFormatError: Error, CustomStringConvertible {
    var description: String { "шапка должна быть набором полей «ключ: значение»" }
}

public enum FrontmatterWriter {
    public static func document(frontmatterLines: [String], body: String) -> String {
        let header = "---\n" + frontmatterLines.joined(separator: "\n") + "\n---\n"
        let content = body.trimmingCharacters(in: .newlines)
        return content.isEmpty ? header : "\(header)\n\(content)\n"
    }

    /// Строка YAML-скаляра: в кавычках только когда без них значение прочитается иначе.
    public static func scalar(_ value: String) -> String {
        let reservedWords: Set<String> = ["true", "false", "yes", "no", "on", "off", "null", "~"]
        let needsQuotes = value.isEmpty
            || value.first.map { "-?:,[]{}#&*!|>'\"%@`".contains($0) } == true
            || value.contains(": ") || value.contains(" #") || value.hasSuffix(":")
            || value != value.trimmingCharacters(in: .whitespaces)
            || reservedWords.contains(value.lowercased())
            || Double(value) != nil
            || value.wholeMatch(of: /\d{4}-\d{2}-\d{2}.*/) != nil
        guard needsQuotes else { return value }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    /// Строки шапки верхнего уровня, кроме перечисленных ключей (вместе с их продолжением на следующих строках).
    public static func lines(of yaml: String, excluding keys: Set<String>) -> [String] {
        var result: [String] = []
        var isSkipping = false
        for line in yaml.components(separatedBy: "\n") {
            let isContinuation = line.first.map { $0 == " " || $0 == "\t" || $0 == "-" } ?? true
            if !isContinuation {
                let key = line.split(separator: ":", maxSplits: 1).first.map(String.init) ?? ""
                isSkipping = keys.contains(key)
            }
            if !isSkipping && !(line.isEmpty && result.isEmpty) {
                result.append(line)
            }
        }
        while result.last?.isEmpty == true { result.removeLast() }
        return result
    }

    /// Заменяет поле верхнего уровня; если поля нет — добавляет его после `id`.
    public static func replacingField(_ key: String, with value: String, in yaml: String) -> [String] {
        let newLine = "\(key): \(value)"
        let original = yaml.isEmpty ? [] : yaml.components(separatedBy: "\n")
        guard let index = original.firstIndex(where: { $0.hasPrefix("\(key):") }) else {
            let insertAt = original.firstIndex { $0.hasPrefix("id:") }.map { $0 + 1 } ?? 0
            return Array(original[..<insertAt]) + [newLine] + Array(original[insertAt...])
        }
        let continuationEnd = original[(index + 1)...].firstIndex { line in
            !(line.first == " " || line.first == "\t")
        } ?? original.endIndex
        return Array(original[..<index]) + [newLine] + Array(original[continuationEnd...])
    }
}
