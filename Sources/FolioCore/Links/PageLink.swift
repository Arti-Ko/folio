import Foundation

/// Системная ссылка `folio://open?space=<id>&path=<путь>[&edit=1]`: открывает страницу в приложении.
public enum PageLink {
    public static let scheme = "folio"
    public static let openHost = "open"
    private static let editValue = "1"

    public static func url(for ref: PageRef, editing: Bool = false) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = openHost
        components.queryItems = [
            URLQueryItem(name: "space", value: ref.spaceID.uuidString),
            URLQueryItem(name: "path", value: ref.path),
        ] + (editing ? [URLQueryItem(name: "edit", value: editValue)] : [])
        return components.url
    }

    public static func ref(from url: URL) -> PageRef? {
        guard let items = queryItems(of: url),
              let spaceID = items.first(where: { $0.name == "space" })?.value.flatMap(UUID.init(uuidString:)) else {
            return nil
        }
        return PageRef(spaceID: spaceID, path: items.first { $0.name == "path" }?.value ?? "")
    }

    /// Просит ли ссылка открыть страницу сразу на правку.
    public static func wantsEditing(_ url: URL) -> Bool {
        queryItems(of: url)?.contains { $0.name == "edit" && $0.value == editValue } ?? false
    }

    private static func queryItems(of url: URL) -> [URLQueryItem]? {
        guard url.scheme == scheme, url.host() == openHost else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
    }
}
