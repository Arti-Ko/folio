import Foundation

/// Имена вложений, которые не ломают Markdown-ссылки и не затирают соседние файлы.
public enum AttachmentNaming {
    static let maximumStemLength = 80
    private static let unsafeScalars = CharacterSet(charactersIn: " ()[]{}<>#%?*:|\"'\\/")
        .union(.whitespacesAndNewlines)
        .union(.controlCharacters)
    /// Такие имена даёт буфер обмена при вставке снимка экрана.
    private static let genericStems: Set<String> = ["image", "Image", "изображение", "Вставка", "Снимок"]

    public static func availableName(for preferred: String, in folder: URL, now: Date = .now) -> String {
        let preferredURL = URL(fileURLWithPath: preferred)
        let fileExtension = preferredURL.pathExtension.lowercased()
        let originalStem = preferredURL.deletingPathExtension().lastPathComponent
        let stem = cleanStem(genericStems.contains(originalStem) ? "" : originalStem, fallback: pastedStem(now))
        let suffix = fileExtension.isEmpty ? "" : ".\(fileExtension)"

        var candidate = stem + suffix
        var counter = 2
        while FileManager.default.fileExists(atPath: String.filePath(folder.appending(path: candidate))) {
            candidate = "\(stem)-\(counter)\(suffix)"
            counter += 1
        }
        return candidate
    }

    static func cleanStem(_ stem: String, fallback: String) -> String {
        let replaced = String(String.UnicodeScalarView(stem.unicodeScalars.map { unsafeScalars.contains($0) ? "-" : $0 }))
        let collapsed = replaced
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: ".-_"))
        let limited = String(collapsed.prefix(maximumStemLength))
        return limited.isEmpty ? fallback : limited
    }

    private static func pastedStem(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "Вставка-\(formatter.string(from: date))"
    }
}
