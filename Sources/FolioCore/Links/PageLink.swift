import Foundation

/// Системная ссылка `folio://open?space=<id>&path=<путь>`: открывает страницу в приложении.
public enum PageLink {
    public static let scheme = "folio"
    public static let openHost = "open"

    public static func url(for ref: PageRef) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = openHost
        components.queryItems = [
            URLQueryItem(name: "space", value: ref.spaceID.uuidString),
            URLQueryItem(name: "path", value: ref.path),
        ]
        return components.url
    }

    public static func ref(from url: URL) -> PageRef? {
        guard url.scheme == scheme, url.host() == openHost,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let spaceID = items.first(where: { $0.name == "space" })?.value.flatMap(UUID.init(uuidString:)) else {
            return nil
        }
        return PageRef(spaceID: spaceID, path: items.first { $0.name == "path" }?.value ?? "")
    }
}
