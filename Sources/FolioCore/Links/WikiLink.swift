import Foundation

/// Ссылка `[[Пространство::Заголовок|текст]]`.
public struct WikiLink: Sendable, Hashable {
    public let space: String?
    public let title: String
    public let label: String?

    public init(space: String?, title: String, label: String?) {
        self.space = space
        self.title = title
        self.label = label
    }

    public var key: String { Self.key(space: space, title: title) }

    public var markdown: String {
        let prefix = space.map { "\($0)::" } ?? ""
        let suffix = label.map { "|\($0)" } ?? ""
        return "[[\(prefix)\(title)\(suffix)]]"
    }

    /// Совпадает с `wikiLinkKey` в веб-части.
    public static func key(space: String?, title: String) -> String {
        "\(TitleKey.make(space ?? ""))::\(TitleKey.make(title))"
    }
}

public struct WikiLinkOccurrence: Sendable {
    public let link: WikiLink
    public let range: Range<String.Index>
}

public enum WikiLinkParser {
    public static func links(in markdown: String) -> [WikiLink] {
        occurrences(in: markdown).map(\.link)
    }

    public static func occurrences(in markdown: String) -> [WikiLinkOccurrence] {
        let code = MarkdownCode.ranges(in: markdown)
        let pattern = /\[\[([^\[\]|\n]+?)(?:\|([^\[\]\n]+?))?\]\]/
        return markdown.matches(of: pattern).compactMap { match in
            guard !code.contains(where: { $0.overlaps(match.range) }) else { return nil }
            let label = match.output.2.map { $0.trimmingCharacters(in: .whitespaces) }?.nilIfEmpty
            guard let link = parseTarget(String(match.output.1), label: label) else { return nil }
            return WikiLinkOccurrence(link: link, range: match.range)
        }
    }

    /// Переписывает заголовок в подходящих ссылках; `nil`, если менять нечего.
    public static func rewrite(
        _ markdown: String,
        newTitle: String,
        where shouldRename: (WikiLink) -> Bool
    ) -> String? {
        let targets = occurrences(in: markdown).filter { shouldRename($0.link) }
        guard !targets.isEmpty else { return nil }
        var result = ""
        var cursor = markdown.startIndex
        for occurrence in targets {
            result += markdown[cursor..<occurrence.range.lowerBound]
            result += WikiLink(space: occurrence.link.space, title: newTitle, label: occurrence.link.label).markdown
            cursor = occurrence.range.upperBound
        }
        result += markdown[cursor...]
        return result
    }

    static func parseTarget(_ inner: String, label: String?) -> WikiLink? {
        let space: String?
        let title: String
        if let separator = inner.range(of: "::") {
            space = inner[..<separator.lowerBound].trimmingCharacters(in: .whitespaces).nilIfEmpty
            title = inner[separator.upperBound...].trimmingCharacters(in: .whitespaces)
        } else {
            space = nil
            title = inner.trimmingCharacters(in: .whitespaces)
        }
        return title.isEmpty ? nil : WikiLink(space: space, title: title, label: label)
    }
}

/// Участки кода, внутри которых разметку ссылок не трогаем.
enum MarkdownCode {
    static func ranges(in markdown: String) -> [Range<String.Index>] {
        let fenced = fencedRanges(in: markdown)
        let inline = markdown.matches(of: /(`+)[^`\n]+?\1/)
            .map(\.range)
            .filter { range in !fenced.contains { $0.overlaps(range) } }
        return fenced + inline
    }

    private static func fencedRanges(in markdown: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var openFence: (marker: Character, length: Int, start: String.Index)?
        var lineStart = markdown.startIndex

        while lineStart < markdown.endIndex {
            let lineEnd = markdown[lineStart...].firstIndex { $0 == "\n" || $0 == "\r\n" } ?? markdown.endIndex
            let line = markdown[lineStart..<lineEnd].drop { $0 == " " }
            if let marker = line.first, marker == "`" || marker == "~" {
                let length = line.prefix { $0 == marker }.count
                if length >= 3 {
                    if let open = openFence {
                        let isClosing = marker == open.marker && length >= open.length
                            && line.dropFirst(length).allSatisfy(\.isWhitespace)
                        if isClosing {
                            ranges.append(open.start..<lineEnd)
                            openFence = nil
                        }
                    } else {
                        openFence = (marker, length, lineStart)
                    }
                }
            }
            lineStart = lineEnd < markdown.endIndex ? markdown.index(after: lineEnd) : markdown.endIndex
        }
        if let open = openFence {
            ranges.append(open.start..<markdown.endIndex)
        }
        return ranges
    }
}

/// Относительные ссылки на файлы рядом со страницей: картинки и вложения.
public enum AttachmentReferences {
    public static func relativePaths(in markdown: String) -> [String] {
        let code = MarkdownCode.ranges(in: markdown)
        let pattern = /!?\[[^\]\n]*\]\((<[^>\n]+>|[^)\s]+)(?:\s+"[^"\n]*")?\)/
        return markdown.matches(of: pattern).compactMap { match in
            guard !code.contains(where: { $0.overlaps(match.range) }) else { return nil }
            var target = String(match.output.1)
            if target.hasPrefix("<") { target = String(target.dropFirst().dropLast()) }
            let isExternal = target.contains(":") || target.hasPrefix("#") || target.hasPrefix("/")
            guard !isExternal else { return nil }
            let withoutFragment = target.split(separator: "#", maxSplits: 1).first.map(String.init) ?? target
            return withoutFragment.removingPercentEncoding ?? withoutFragment
        }
    }
}
