import AppKit
import FolioCore
import SwiftUI

struct InspectorView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(NavigationModel.self) private var navigation

    var body: some View {
        if let ref = navigation.selection, let snapshot = library.snapshot(for: ref.spaceID), snapshot.page(at: ref.path) != nil {
            PageInspector(ref: ref, snapshot: snapshot)
        } else {
            ContentUnavailableView("Страница не выбрана", systemImage: "sidebar.trailing")
        }
    }
}

private struct RevisionKey: Hashable {
    let ref: PageRef
    let revision: Int
}

private struct PageFacts: Sendable {
    let attachments: [URL]
    let revisions: [GitRevision]
    let hasUncommittedChanges: Bool
}

private struct PageInspector: View {
    let ref: PageRef
    let snapshot: SpaceSnapshot

    @Environment(LibraryModel.self) private var library
    @Environment(NavigationModel.self) private var navigation
    @State private var backlinks: [SearchHit] = []
    @State private var facts = PageFacts(attachments: [], revisions: [], hasUncommittedChanges: false)
    @SceneStorage("inspector.outline") private var isOutlineExpanded = true
    @SceneStorage("inspector.backlinks") private var isBacklinksExpanded = true
    @SceneStorage("inspector.attachments") private var isAttachmentsExpanded = true
    @SceneStorage("inspector.history") private var isHistoryExpanded = true

    var body: some View {
        List {
            if let node = snapshot.page(at: ref.path) {
                PagePropertiesSection(ref: ref, node: node)
            }

            Section("Содержание", isExpanded: $isOutlineExpanded) {
                if navigation.outline.isEmpty {
                    placeholder("Заголовков нет")
                }
                ForEach(navigation.outline) { item in
                    Button {
                        navigation.requestHeading(item.index)
                    } label: {
                        Text(item.text)
                            .lineLimit(2)
                            .padding(.leading, CGFloat(item.level - 1) * 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Ссылаются сюда", isExpanded: $isBacklinksExpanded) {
                if backlinks.isEmpty {
                    placeholder("Ссылок нет")
                }
                ForEach(backlinks) { hit in
                    Button {
                        navigation.open(hit.ref)
                    } label: {
                        Label(hit.title, systemImage: "arrow.turn.up.left")
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Вложения", isExpanded: $isAttachmentsExpanded) {
                if facts.attachments.isEmpty {
                    placeholder("Файлов рядом со страницей нет")
                }
                ForEach(facts.attachments, id: \.self) { url in
                    AttachmentRow(url: url)
                }
            }

            Section("История", isExpanded: $isHistoryExpanded) {
                if facts.hasUncommittedChanges {
                    Button("Сохранить снимок", systemImage: "clock.badge.checkmark") {
                        Task { await library.commitChanges(in: ref.spaceID) }
                    }
                    .help("В пространстве есть изменения, которых нет в истории")
                }
                RevisionRow(title: "Текущая версия", subtitle: nil, isSelected: navigation.version == nil) {
                    navigation.version = nil
                }
                ForEach(facts.revisions) { revision in
                    RevisionRow(
                        title: revision.message,
                        subtitle: revision.date.formatted(date: .abbreviated, time: .shortened),
                        isSelected: navigation.version?.hash == revision.hash
                    ) {
                        navigation.version = HistoryVersion(hash: revision.hash, path: revision.path, date: revision.date, message: revision.message)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .task(id: RevisionKey(ref: ref, revision: library.indexRevision)) {
            backlinks = await library.backlinks(for: ref)
        }
        .task(id: RevisionKey(ref: ref, revision: library.contentRevision)) {
            facts = await loadFacts()
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.tertiary)
    }

    private func loadFacts() async -> PageFacts {
        let folder = snapshot.folderURL(for: ref.path)
        let root = snapshot.space.root
        let relativeFile = ref.path.isEmpty ? SpaceScanner.pageFileName : "\(ref.path)/\(SpaceScanner.pageFileName)"
        return await Task.detached(priority: .utility) {
            let repository = GitRepository(root: root)
            return PageFacts(
                attachments: Self.attachments(in: folder),
                revisions: (try? repository.history(of: relativeFile)) ?? [],
                hasUncommittedChanges: (try? repository.hasChanges()) ?? false
            )
        }.value
    }

    private nonisolated static func attachments(in folder: URL) -> [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let hiddenNames: Set<String> = [SpaceScanner.pageFileName, "CLAUDE.md"]
        return entries
            .filter { url in
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                return !isDirectory && !hiddenNames.contains(url.lastPathComponent)
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}

private struct AttachmentRow: View {
    let url: URL

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            Label {
                Text(url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false)))
                    .resizable()
                    .frame(width: 16, height: 16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Открыть")
        .contextMenu {
            Button("Открыть") { NSWorkspace.shared.open(url) }
            Button("Показать в Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
    }
}

private struct RevisionRow: View {
    let title: String
    let subtitle: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .imageScale(.small)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .lineLimit(2)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
