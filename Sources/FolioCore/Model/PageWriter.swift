import Foundation

/// Запись правок из приложения: тело и свойства страницы меняются, остальная шапка остаётся как была.
public enum PageWriter {
    /// Текст файла с прежней шапкой и новым телом.
    public static func replacingBody(in text: String, with body: String) -> String {
        let document = PageDocument.parse(text)
        let content = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw = document.rawFrontmatter else {
            return content.isEmpty ? "" : content + "\n"
        }
        return FrontmatterWriter.document(frontmatterLines: lines(of: raw), body: content)
    }

    /// Меняет статус и метки; пустой статус и пустой список меток убирают поля из шапки.
    /// Свой цвет статуса сбрасывается, только если сменился сам статус.
    public static func settingProperties(in text: String, status: String?, labels: [String]) -> String {
        let document = PageDocument.parse(text)
        let cleanStatus = status.map(collapseWhitespace)?.nilIfEmpty
        let cleanLabels = labels.map(collapseWhitespace).filter { !$0.isEmpty }

        var fields = document.rawFrontmatter.map(lines(of:)) ?? ["id: \(PageID.make())"]
        fields = setting("status", to: cleanStatus.map(FrontmatterWriter.scalar), in: fields)
        if cleanStatus != document.frontmatter.status?.label {
            fields = setting("status_color", to: nil, in: fields)
        }
        let labelsValue = cleanLabels.isEmpty
            ? nil
            : "[" + cleanLabels.map(FrontmatterWriter.flowScalar).joined(separator: ", ") + "]"
        fields = setting("labels", to: labelsValue, in: fields)
        return FrontmatterWriter.document(frontmatterLines: fields, body: document.body)
    }

    private static func lines(of raw: String) -> [String] {
        raw.isEmpty ? [] : raw.components(separatedBy: "\n")
    }

    private static func setting(_ key: String, to value: String?, in fields: [String]) -> [String] {
        let yaml = fields.joined(separator: "\n")
        guard let value else {
            return FrontmatterWriter.lines(of: yaml, excluding: [key])
        }
        return FrontmatterWriter.replacingField(key, with: value, in: yaml)
    }
}

extension FrontmatterWriter {
    /// Элемент списка `[a, b]`: кроме обычных случаев, кавычки нужны для запятых и скобок.
    public static func flowScalar(_ value: String) -> String {
        let plain = scalar(value)
        guard plain == value, value.contains(where: { ",[]{}".contains($0) }) else { return plain }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
