import FolioCore
import SwiftUI

struct ContentView: View {
    @Environment(LibraryModel.self) var library
    @State var navigation = NavigationModel()
    @SceneStorage("selectedPage") private var storedSelection = ""

    var body: some View {
        @Bindable var navigation = navigation
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 270, max: 420)
        } detail: {
            DetailView()
        }
        .searchable(text: $navigation.searchText, placement: .sidebar, prompt: "Поиск по страницам")
        .inspector(isPresented: $navigation.isInspectorPresented) {
            InspectorView()
                .inspectorColumnWidth(min: 220, ideal: 270, max: 380)
        }
        .toolbar { toolbarContent }
        .environment(navigation)
        .focusedSceneValue(\.navigation, navigation)
        .sheet(item: $navigation.sheet) { sheet in
            PageSheetView(sheet: sheet)
                .environment(library)
                .environment(navigation)
        }
        .confirmationDialog(trashTitle, isPresented: isTrashConfirmationPresented, titleVisibility: .visible) {
            Button("Переместить в Корзину", role: .destructive, action: trashPendingPage)
        } message: {
            Text("Вместе с подстраницами. Вернуть можно из Корзины или из истории пространства.")
        }
        .alert("Не получилось", isPresented: isErrorPresented) {
            Button("OK") {}
        } message: {
            Text(library.errorMessage ?? "")
        }
        .onChange(of: library.isLoaded, initial: true) {
            restoreSelection()
            openPendingPage()
        }
        .onChange(of: library.contentRevision) { openPendingPage() }
        .onOpenURL { url in
            guard let ref = PageLink.ref(from: url) else { return }
            navigation.searchText = ""
            navigation.pendingOpen = ref
            openPendingPage()
        }
        .handlesExternalEvents(preferring: [PageLink.openHost], allowing: ["*"])
        .onChange(of: navigation.selection) { _, selection in
            storedSelection = selection.map { "\($0.spaceID.uuidString)\n\($0.path)" } ?? ""
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button("Назад", systemImage: "chevron.backward", action: navigation.goBack)
                .disabled(!navigation.canGoBack)
            Button("Вперёд", systemImage: "chevron.forward", action: navigation.goForward)
                .disabled(!navigation.canGoForward)
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Новая страница", systemImage: "square.and.pencil") {
                if let parent = navigation.selection { navigation.sheet = .newPage(parent: parent) }
            }
            .help("Новая подстраница открытой страницы")
            .disabled(navigation.selection == nil)
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Инспектор", systemImage: "sidebar.trailing") {
                navigation.isInspectorPresented.toggle()
            }
            .help("Показать или скрыть инспектор")
        }
    }

    private var trashTitle: String {
        guard let ref = navigation.pendingTrash, let node = library.node(for: ref) else { return "" }
        return "Переместить «\(node.title)» в Корзину?"
    }

    private var isTrashConfirmationPresented: Binding<Bool> {
        Binding(get: { navigation.pendingTrash != nil }, set: { if !$0 { navigation.pendingTrash = nil } })
    }

    private var isErrorPresented: Binding<Bool> {
        Binding(get: { library.errorMessage != nil }, set: { if !$0 { library.errorMessage = nil } })
    }

    private func trashPendingPage() {
        guard let ref = navigation.pendingTrash else { return }
        navigation.pendingTrash = nil
        let parentPath = ref.path.split(separator: "/").dropLast().joined(separator: "/")
        do {
            try library.trashPage(ref)
            if navigation.selection == ref {
                navigation.open(PageRef(spaceID: ref.spaceID, path: parentPath))
            }
        } catch {
            library.report(error)
        }
    }

    private func restoreSelection() {
        guard library.isLoaded, navigation.selection == nil else { return }
        let parts = storedSelection.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        if parts.count == 2, let id = UUID(uuidString: parts[0]) {
            let ref = PageRef(spaceID: id, path: parts[1])
            if library.node(for: ref) != nil {
                navigation.open(ref)
                return
            }
        }
        navigation.open(library.snapshots.first?.home.id)
    }
}

struct DetailView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(NavigationModel.self) private var navigation

    var body: some View {
        content
            .onChange(of: library.contentRevision) { relocateIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        if library.isLoaded && library.snapshots.isEmpty {
            WelcomeView()
        } else if let ref = navigation.selection, let node = library.node(for: ref) {
            PageView(ref: ref, node: node)
                .onChange(of: node.pageID, initial: true) { _, pageID in navigation.remember(pageID: pageID) }
        } else if navigation.selection != nil {
            ContentUnavailableView(
                "Страница не найдена",
                systemImage: "doc.questionmark",
                description: Text("Её перенесли или удалили.")
            )
        } else {
            ContentUnavailableView("Выберите страницу", systemImage: "doc.text")
        }
    }

    private func relocateIfNeeded() {
        guard let ref = navigation.selection,
              library.node(for: ref) == nil,
              let pageID = navigation.selectedPageID,
              let moved = library.relocate(pageID: pageID, in: ref.spaceID) else { return }
        navigation.relocate(to: moved)
    }
}

struct WelcomeView: View {
    @Environment(LibraryModel.self) private var library

    var body: some View {
        ContentUnavailableView {
            Label("Пространств пока нет", systemImage: "books.vertical")
        } description: {
            Text("Создайте «Работу» и «Личное» в папке Документы › Folio или подключите готовую папку пространства.")
        } actions: {
            Button("Создать «Работу» и «Личное»") {
                Task { await library.createDefaultSpaces() }
            }
            .buttonStyle(.borderedProminent)
            Button("Подключить папку…", action: library.chooseAndAddSpace)
        }
    }
}
