import FolioCore
import SwiftUI

private struct LoadKey: Hashable {
    let ref: PageRef
    let contentRevision: Int
    let version: HistoryVersion?
}

private struct RenderedKey: Equatable {
    let ref: PageRef
    let version: HistoryVersion?
}

private struct LoadedText: Sendable {
    let text: String
    let modified: Date?
}

struct PageView: View {
    let ref: PageRef
    let node: PageNode

    @Environment(LibraryModel.self) private var library
    @Environment(NavigationModel.self) private var navigation
    @State private var bridge = PageBridge()
    @State private var renderedKey: RenderedKey?

    var body: some View {
        PageWebView(bridge: bridge)
            .onAppear(perform: connectBridge)
            .task(id: LoadKey(ref: ref, contentRevision: library.contentRevision, version: navigation.version)) {
                await load()
            }
            .onChange(of: navigation.headingRequest) { _, request in
                if let request { bridge.scrollToHeading(request.index) }
            }
            .navigationTitle(node.title)
            .navigationSubtitle(subtitle)
    }

    private var subtitle: String {
        let path = library.snapshot(for: ref.spaceID)?.ancestors(of: ref.path).map(\.title).joined(separator: " › ") ?? ""
        guard let version = navigation.version else { return path }
        let date = version.date.formatted(date: .abbreviated, time: .shortened)
        return path.isEmpty ? "версия от \(date)" : "\(path) · версия от \(date)"
    }

    private func connectBridge() {
        bridge.spaceRoot = { [library] id in library.snapshot(for: id)?.space.root }
        bridge.onMessage = { [library, navigation] message in
            PageMessageRouter.handle(message, library: library, navigation: navigation)
        }
    }

    private func load() async {
        guard let snapshot = library.snapshot(for: ref.spaceID) else { return }
        let fileURL = snapshot.fileURL(for: ref.path)
        let root = snapshot.space.root
        let version = navigation.version

        let result = await Task.detached(priority: .userInitiated) {
            Result { try Self.read(fileURL: fileURL, root: root, version: version) }
        }.value
        guard !Task.isCancelled else { return }

        switch result {
        case .success(let loaded):
            let key = RenderedKey(ref: ref, version: version)
            let payload = PagePayloadBuilder.make(
                ref: ref,
                node: node,
                document: PageDocument.parse(loaded.text),
                library: library.librarySnapshot,
                modified: loaded.modified,
                version: version,
                resetScroll: renderedKey != key
            )
            renderedKey = key
            bridge.render(payload)
        case .failure(let error):
            library.errorMessage = "Страница «\(node.title)» не открылась: \(error.localizedDescription)"
        }
    }

    private nonisolated static func read(fileURL: URL, root: URL, version: HistoryVersion?) throws -> LoadedText {
        if let version {
            let text = try GitRepository(root: root).contents(of: version.path, at: version.hash)
            return LoadedText(text: text, modified: version.date)
        }
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        let modified = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        return LoadedText(text: text, modified: modified)
    }
}

@MainActor
enum PageMessageRouter {
    static func handle(_ message: BridgeMessage, library: LibraryModel, navigation: NavigationModel) {
        switch message {
        case .outline(let items):
            navigation.outline = items
        case .openPage(let spaceName, let title):
            guard let current = navigation.selection else { return }
            let link = WikiLink(space: spaceName, title: title, label: nil)
            if let target = library.librarySnapshot.resolve(link, from: current.spaceID) {
                navigation.open(target)
            } else {
                library.errorMessage = "Страницы «\(title)» пока нет"
            }
        case .openURL(let href):
            guard let current = navigation.selection else { return }
            library.openLink(href, from: current)
        case .ready, .renderError:
            break
        }
    }
}

enum PagePayloadBuilder {
    private static let russian = Locale(identifier: "ru_RU")

    static func make(
        ref: PageRef,
        node: PageNode,
        document: PageDocument,
        library: LibrarySnapshot,
        modified: Date?,
        version: HistoryVersion?,
        resetScroll: Bool
    ) -> PagePayload {
        let links = WikiLinkParser.links(in: document.body).reduce(into: [String: Bool]()) { result, link in
            result[link.key] = library.resolve(link, from: ref.spaceID) != nil
        }
        let status = version == nil ? node.status : document.frontmatter.status
        let labels = version == nil ? node.labels : document.frontmatter.labels
        let dateStyle = Date.FormatStyle(date: .long, time: .shortened, locale: russian)

        return PagePayload(
            markdown: document.body,
            title: version == nil ? node.title : (document.frontmatter.title ?? node.title),
            status: status.map { PagePayload.Status(label: $0.label, color: $0.color.rawValue) },
            labels: labels,
            meta: modified.map { "Изменено \($0.formatted(dateStyle))" } ?? "",
            assetBase: AppScheme.assetBase(spaceID: ref.spaceID, pagePath: ref.path),
            links: links,
            children: node.children.map { PagePayload.Child(title: $0.title) },
            banner: version.map { "Старая версия от \($0.date.formatted(dateStyle)) — «\($0.message)». Только для просмотра." },
            resetScroll: resetScroll
        )
    }
}
