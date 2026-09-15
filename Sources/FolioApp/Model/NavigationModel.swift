import FolioCore
import Observation
import SwiftUI

struct HistoryVersion: Hashable, Sendable {
    let hash: String
    let path: String
    let date: Date
    let message: String
}

struct OutlineItem: Hashable, Identifiable, Sendable {
    let level: Int
    let text: String
    let index: Int

    var id: Int { index }
}

enum PageSheet: Identifiable, Hashable {
    case newPage(parent: PageRef)
    case rename(PageRef)

    var id: Self { self }
}

struct HeadingRequest: Equatable {
    let index: Int
    let token = UUID()
}

/// Состояние одного окна: открытая страница, история переходов, раскрытые ветки, инспектор.
@MainActor
@Observable
final class NavigationModel {
    private(set) var selection: PageRef?
    private(set) var selectedPageID: String?
    private(set) var backStack: [PageRef] = []
    private(set) var forwardStack: [PageRef] = []
    private(set) var headingRequest: HeadingRequest?

    var expandedPages: Set<PageRef> = []
    var collapsedSpaces: Set<UUID> = []
    var searchText = ""
    var isInspectorPresented = true
    var version: HistoryVersion?
    var outline: [OutlineItem] = []
    var sheet: PageSheet?
    var pendingTrash: PageRef?
    /// Страница из ссылки `folio://open`, которая пришла раньше, чем её увидело дерево.
    var pendingOpen: PageRef?
    var pendingOpenEditing = false

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    func open(_ ref: PageRef?) {
        guard let ref, ref != selection else { return }
        if let selection { backStack.append(selection) }
        forwardStack.removeAll()
        show(ref)
    }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        if let selection { forwardStack.append(selection) }
        show(previous)
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        if let selection { backStack.append(selection) }
        show(next)
    }

    /// Адрес страницы поменялся снаружи: подменяем его без записи в историю переходов.
    func relocate(to ref: PageRef) {
        selection = ref
        expandAncestors(of: ref)
    }

    func remember(pageID: String?) {
        selectedPageID = pageID
    }

    func requestHeading(_ index: Int) {
        headingRequest = HeadingRequest(index: index)
    }

    func isExpanded(_ ref: PageRef) -> Binding<Bool> {
        Binding(
            get: { self.expandedPages.contains(ref) },
            set: { isOpen in
                if isOpen { self.expandedPages.insert(ref) } else { self.expandedPages.remove(ref) }
            }
        )
    }

    func isSpaceExpanded(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { !self.collapsedSpaces.contains(id) },
            set: { isOpen in
                if isOpen { self.collapsedSpaces.remove(id) } else { self.collapsedSpaces.insert(id) }
            }
        )
    }

    private func show(_ ref: PageRef) {
        selection = ref
        selectedPageID = nil
        version = nil
        outline = []
        expandAncestors(of: ref)
    }

    private func expandAncestors(of ref: PageRef) {
        let components = ref.path.split(separator: "/").map(String.init)
        let ancestors = components.indices.dropLast().map { index in
            PageRef(spaceID: ref.spaceID, path: components[...index].joined(separator: "/"))
        }
        expandedPages.formUnion(ancestors)
        collapsedSpaces.remove(ref.spaceID)
    }
}

extension FocusedValues {
    @Entry var navigation: NavigationModel?
}

extension StatusColor {
    var tint: Color {
        switch self {
        case .grey: .gray
        case .blue: .blue
        case .green: .green
        case .yellow: .yellow
        case .red: .red
        case .purple: .purple
        }
    }
}
