import Foundation

public struct PageRef: Hashable, Sendable, Codable {
    public let spaceID: UUID
    /// Путь папки страницы относительно корня пространства; пустая строка — главная.
    public let path: String

    public init(spaceID: UUID, path: String) {
        self.spaceID = spaceID
        self.path = path
    }

    public var isHome: Bool { path.isEmpty }
}

public struct PageNode: Sendable, Hashable, Identifiable {
    public let spaceID: UUID
    public let path: String
    public let title: String
    public let pageID: String?
    public let status: PageStatus?
    public let labels: [String]
    public let order: Double?
    public let children: [PageNode]

    public var id: PageRef { PageRef(spaceID: spaceID, path: path) }
    /// Для `OutlineGroup`: у листьев нет стрелки раскрытия.
    public var outlineChildren: [PageNode]? { children.isEmpty ? nil : children }
    public var folderName: String { PagePath.name(of: path) }
    public var parentPath: String? { PagePath.parent(of: path) }

    static func displayOrder(_ lhs: PageNode, _ rhs: PageNode) -> Bool {
        switch (lhs.order, rhs.order) {
        case let (left?, right?) where left != right:
            left < right
        case (.some, nil):
            true
        case (nil, .some):
            false
        default:
            lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }
}
