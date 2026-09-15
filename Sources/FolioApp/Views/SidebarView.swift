import FolioCore
import SwiftUI

struct SidebarView: View {
    @Environment(NavigationModel.self) private var navigation

    var body: some View {
        Group {
            if navigation.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                PageTreeList()
            } else {
                SearchResultsList(query: navigation.searchText)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            UpdateBanner()
        }
    }
}

private struct PageTreeList: View {
    @Environment(LibraryModel.self) private var library
    @Environment(NavigationModel.self) private var navigation

    var body: some View {
        List(selection: selection) {
            ForEach(library.snapshots, id: \.space.id) { snapshot in
                Section(isExpanded: navigation.isSpaceExpanded(snapshot.space.id)) {
                    PageRowLabel(title: homeTitle(snapshot), systemImage: "house", status: nil)
                        .tag(snapshot.home.id)
                        .contextMenu { PageMenuItems(ref: snapshot.home.id) }
                    ForEach(snapshot.home.children) { node in
                        PageTreeNode(node: node)
                    }
                } header: {
                    Text(snapshot.space.name)
                        .contextMenu { SpaceMenuItems(snapshot: snapshot) }
                }
            }

            if !library.missingPaths.isEmpty {
                Section("Недоступные папки") {
                    ForEach(library.missingPaths, id: \.self) { path in
                        Label(path, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                            .contextMenu {
                                Button("Убрать из списка") {
                                    Task { await library.forgetMissing(path) }
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var selection: Binding<PageRef?> {
        Binding(get: { navigation.selection }, set: { navigation.open($0) })
    }

    private func homeTitle(_ snapshot: SpaceSnapshot) -> String {
        snapshot.home.title == snapshot.space.name ? "Главная" : snapshot.home.title
    }
}

private struct PageTreeNode: View {
    let node: PageNode
    @Environment(NavigationModel.self) private var navigation

    var body: some View {
        if node.children.isEmpty {
            label
                .tag(node.id)
                .contextMenu { PageMenuItems(ref: node.id) }
        } else {
            DisclosureGroup(isExpanded: navigation.isExpanded(node.id)) {
                ForEach(node.children) { child in
                    PageTreeNode(node: child)
                }
            } label: {
                label
            }
            .tag(node.id)
            .contextMenu { PageMenuItems(ref: node.id) }
        }
    }

    private var label: some View {
        PageRowLabel(title: node.title, systemImage: "doc.text", status: node.status)
    }
}

private struct PageRowLabel: View {
    let title: String
    let systemImage: String
    let status: PageStatus?

    var body: some View {
        Label {
            HStack(spacing: 6) {
                Text(title)
                    .lineLimit(1)
                if let status, status.color != .grey {
                    Circle()
                        .fill(status.color.tint)
                        .frame(width: 6, height: 6)
                        .help(status.label)
                        .accessibilityLabel(status.label)
                }
            }
        } icon: {
            Image(systemName: systemImage)
        }
    }
}

struct PageMenuItems: View {
    let ref: PageRef
    @Environment(LibraryModel.self) private var library
    @Environment(NavigationModel.self) private var navigation

    var body: some View {
        Button("Новая подстраница…", systemImage: "doc.badge.plus") {
            navigation.sheet = .newPage(parent: ref)
        }
        if !ref.isHome {
            Button("Переименовать…", systemImage: "pencil") {
                navigation.sheet = .rename(ref)
            }
        }
        Divider()
        Button("Показать в Finder", systemImage: "folder") {
            library.revealInFinder(ref)
        }
        Button("Скопировать путь к файлу", systemImage: "doc.on.doc") {
            library.copyPath(ref)
        }
        if !ref.isHome {
            Divider()
            Button("Переместить в Корзину…", systemImage: "trash", role: .destructive) {
                navigation.pendingTrash = ref
            }
        }
    }
}

private struct SpaceMenuItems: View {
    let snapshot: SpaceSnapshot
    @Environment(LibraryModel.self) private var library
    @Environment(NavigationModel.self) private var navigation

    var body: some View {
        Button("Новая страница…", systemImage: "doc.badge.plus") {
            navigation.sheet = .newPage(parent: snapshot.home.id)
        }
        Button("Сохранить снимок в истории", systemImage: "clock.arrow.circlepath") {
            Task { await library.commitChanges(in: snapshot.space.id) }
        }
        Button("Показать в Finder", systemImage: "folder") {
            NSWorkspace.shared.activateFileViewerSelecting([snapshot.space.root])
        }
    }
}

private struct SearchKey: Hashable {
    let query: String
    let revision: Int
}

private struct SearchResultsList: View {
    let query: String
    @Environment(LibraryModel.self) private var library
    @Environment(NavigationModel.self) private var navigation
    @State private var hits: [SearchHit] = []
    @State private var hasSearched = false

    private static let debounce: Duration = .milliseconds(120)

    var body: some View {
        List(selection: selection) {
            ForEach(hits) { hit in
                SearchHitRow(hit: hit, location: location(of: hit.ref))
                    .tag(hit.ref)
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if hasSearched && hits.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .task(id: SearchKey(query: query, revision: library.indexRevision)) {
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            let found = await library.search(query)
            guard !Task.isCancelled else { return }
            hits = found
            hasSearched = true
        }
    }

    private var selection: Binding<PageRef?> {
        Binding(get: { navigation.selection }, set: { navigation.open($0) })
    }

    private func location(of ref: PageRef) -> String {
        guard let snapshot = library.snapshot(for: ref.spaceID) else { return "" }
        let ancestors = snapshot.ancestors(of: ref.path).map(\.title)
        return ancestors.isEmpty ? snapshot.space.name : ancestors.joined(separator: " › ")
    }
}

private struct SearchHitRow: View {
    let hit: SearchHit
    let location: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(hit.title)
                .lineLimit(1)
            Text(location)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if !hit.snippet.isEmpty {
                Text(SnippetFormatter.attributed(hit.snippet))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

enum SnippetFormatter {
    /// Превращает маркеры совпадений из индекса в выделение жирным.
    static func attributed(_ snippet: String) -> AttributedString {
        let flattened = snippet.replacingOccurrences(of: "\n", with: " ")
        var result = AttributedString()
        var isMatch = false
        var fragment = ""

        func flush() {
            guard !fragment.isEmpty else { return }
            var part = AttributedString(fragment)
            if isMatch {
                part.font = .caption.weight(.semibold)
                part.foregroundColor = .primary
            }
            result += part
            fragment = ""
        }

        for character in flattened {
            switch character {
            case SearchIndex.highlightStart:
                flush()
                isMatch = true
            case SearchIndex.highlightEnd:
                flush()
                isMatch = false
            default:
                fragment.append(character)
            }
        }
        flush()
        return result
    }
}
