import AppKit
import FolioCore
import SwiftUI

private struct LoadKey: Hashable {
    let ref: PageRef
    let contentRevision: Int
    let reloadToken: Int
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
    @Environment(EditorModel.self) private var editor
    @State private var bridge = PageBridge()
    @State private var renderedKey: RenderedKey?

    var body: some View {
        PageWebView(bridge: bridge)
            .safeAreaInset(edge: .top, spacing: 0) {
                if editor.conflictRef == ref {
                    ConflictBanner()
                }
            }
            .onAppear(perform: connectBridge)
            .task(id: LoadKey(ref: ref, contentRevision: library.contentRevision, reloadToken: editor.reloadToken, version: navigation.version)) {
                await load()
            }
            .onChange(of: navigation.headingRequest) { _, request in
                if let request { bridge.scrollToHeading(request.index) }
            }
            .onChange(of: editor.isEditing) { _, isEditing in
                bridge.setEditable(isEditing && editor.editingRef == ref)
            }
            .onChange(of: editor.command) { _, command in
                guard let command, editor.editingRef == ref else { return }
                bridge.run(command.name, arguments: command.arguments)
            }
            .onChange(of: editor.flushRequest) { _, request in
                guard let request else { return }
                Task { await flush(request) }
            }
            .onChange(of: navigation.version) { _, version in
                if version != nil { editor.requestFinish() }
            }
            .navigationTitle(node.title)
            .navigationSubtitle(subtitle)
    }

    private var subtitle: String {
        let path = library.snapshot(for: ref.spaceID)?.ancestors(of: ref.path).map(\.title).joined(separator: " › ") ?? ""
        let state: String? = if editor.isEditing, editor.editingRef == ref {
            switch editor.saveState {
            case .idle: "правка"
            case .saved: "правка · сохранено"
            case .failed(let message): "не сохранено: \(message)"
            }
        } else {
            navigation.version.map { "версия от \($0.date.formatted(date: .abbreviated, time: .shortened))" }
        }
        return [path, state ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func connectBridge() {
        bridge.spaceRoot = { [library] id in library.snapshot(for: id)?.space.root }
        bridge.onMessage = { [library, navigation, editor, weak bridge] message in
            PageMessageRouter.handle(message, library: library, navigation: navigation, editor: editor, bridge: bridge)
        }
    }

    private func flush(_ request: FlushRequest) async {
        if let pending = await bridge.takeMarkdown(force: request.reason == .overwrite) {
            editor.applyChange(markdown: pending.markdown, pageKey: pending.pageKey, library: library)
        }
        if request.reason == .finish {
            editor.completeFinish(library: library)
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
                resetScroll: renderedKey != key,
                editable: version == nil && editor.isEditing && editor.editingRef == ref
            )
            if version == nil, !editor.shouldRender(loaded.text, for: ref) {
                bridge.updateHeader(payload)
                return
            }
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

private struct ConflictBanner: View {
    @Environment(EditorModel.self) private var editor

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Страницу изменили снаружи, пока вы её правили.")
                .font(.callout)
            Spacer()
            Button("Взять версию с диска") { editor.takeDiskVersion() }
            Button("Оставить мою") { editor.keepMyVersion() }
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

@MainActor
enum PageMessageRouter {
    static func handle(
        _ message: BridgeMessage,
        library: LibraryModel,
        navigation: NavigationModel,
        editor: EditorModel,
        bridge: PageBridge?
    ) {
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
        case .change(let key, let markdown):
            editor.applyChange(markdown: markdown, pageKey: key, library: library)
        case .state(let state):
            editor.formatting = state
        case .renameTitle(let key, let title):
            Task { await renameTitle(key: key, title: title, library: library, navigation: navigation, editor: editor, bridge: bridge) }
        case .saveAttachment(let id, let name, let data):
            saveAttachment(id: id, name: name, base64: data, library: library, editor: editor, bridge: bridge)
        case .pickAttachment:
            pickAttachments(library: library, editor: editor, bridge: bridge)
        case .notice(let text):
            library.errorMessage = text
        case .ready, .renderError:
            break
        }
    }

    private static func renameTitle(
        key: String,
        title: String,
        library: LibraryModel,
        navigation: NavigationModel,
        editor: EditorModel,
        bridge: PageBridge?
    ) async {
        guard let ref = PageKey.ref(from: key) else { return }
        // Сначала дописываем текст, пока путь страницы ещё прежний.
        if let pending = await bridge?.takeMarkdown(force: false) {
            editor.applyChange(markdown: pending.markdown, pageKey: pending.pageKey, library: library)
        }
        do {
            let renamed = try editor.rename(ref, to: title, library: library)
            if navigation.selection == ref {
                navigation.relocate(to: renamed)
            }
            bridge?.setPageKey(PageKey.make(renamed))
        } catch {
            library.report(error)
            bridge?.restoreHeader()
        }
    }

    private static func saveAttachment(
        id: String,
        name: String,
        base64: String,
        library: LibraryModel,
        editor: EditorModel,
        bridge: PageBridge?
    ) {
        guard let ref = editor.editingRef, let data = Data(base64Encoded: base64) else {
            bridge?.attachmentSaved(id: id, item: nil)
            return
        }
        do {
            bridge?.attachmentSaved(id: id, item: try library.saveAttachment(data, named: name, for: ref))
        } catch {
            library.report(error)
            bridge?.attachmentSaved(id: id, item: nil)
        }
    }

    private static func pickAttachments(library: LibraryModel, editor: EditorModel, bridge: PageBridge?) {
        guard let ref = editor.editingRef else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Вставить"
        panel.message = "Файлы скопируются в папку страницы"
        guard panel.runModal() == .OK else { return }
        do {
            let items = try panel.urls.map { try library.copyAttachment(from: $0, for: ref) }
            let json = String(decoding: try JSONEncoder().encode(items), as: UTF8.self)
            bridge?.run("insertAttachments", arguments: ["items": json])
        } catch {
            library.report(error)
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
        resetScroll: Bool,
        editable: Bool
    ) -> PagePayload {
        let links = WikiLinkParser.links(in: document.body).reduce(into: [String: Bool]()) { result, link in
            result[link.key] = library.resolve(link, from: ref.spaceID) != nil
        }
        let status = version == nil ? node.status : document.frontmatter.status
        let labels = version == nil ? node.labels : document.frontmatter.labels
        let dateStyle = Date.FormatStyle(date: .long, time: .shortened, locale: russian)
        let pages = library.spaces.flatMap { snapshot in
            snapshot.pages.values.map { PagePayload.PageEntry(space: snapshot.space.name, title: $0.title) }
        }

        return PagePayload(
            pageKey: PageKey.make(ref),
            markdown: document.body,
            title: version == nil ? node.title : (document.frontmatter.title ?? node.title),
            status: status.map { PagePayload.Status(label: $0.label, color: $0.color.rawValue) },
            labels: labels,
            meta: modified.map { "Изменено \($0.formatted(dateStyle))" } ?? "",
            assetBase: AppScheme.assetBase(spaceID: ref.spaceID, pagePath: ref.path),
            links: links,
            children: node.children.map { PagePayload.Child(title: $0.title) },
            pages: pages,
            spaceName: library.snapshot(for: ref.spaceID)?.space.name ?? "",
            banner: version.map { "Старая версия от \($0.date.formatted(dateStyle)) — «\($0.message)». Только для просмотра." },
            resetScroll: resetScroll,
            editable: editable
        )
    }
}
