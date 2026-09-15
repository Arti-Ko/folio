import Foundation

/// Поиск по заголовкам в памяти — для запросов короче трёх букв, которые не умеет полнотекстовый индекс.
public enum TitleSearch {
    public static func hits(_ query: String, in spaces: [SpaceSnapshot], limit: Int) -> [SearchHit] {
        let needle = TitleKey.make(query)
        guard !needle.isEmpty else { return [] }
        let pages: [PageNode] = spaces.flatMap { Array($0.pages.values) }
        let matches: [PageNode] = pages
            .filter { TitleKey.make($0.title).contains(needle) }
            .sorted(by: shorterTitleFirst)
        return matches.prefix(limit).map { SearchHit(ref: $0.id, title: $0.title, snippet: "") }
    }

    private static func shorterTitleFirst(_ lhs: PageNode, _ rhs: PageNode) -> Bool {
        guard lhs.title.count != rhs.title.count else {
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        return lhs.title.count < rhs.title.count
    }
}
