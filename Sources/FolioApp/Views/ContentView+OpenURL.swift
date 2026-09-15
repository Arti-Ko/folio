import FolioCore
import SwiftUI

extension ContentView {
    func handleOpenURL(_ url: URL) {
        guard let ref = PageLink.ref(from: url) else { return }
        navigation.searchText = ""
        navigation.pendingOpen = ref
        navigation.pendingOpenEditing = PageLink.wantsEditing(url)
        openPendingPage()
    }

    /// Открывает страницу из `folio://open`, как только она появилась в дереве.
    func openPendingPage() {
        guard library.isLoaded, let ref = navigation.pendingOpen, library.node(for: ref) != nil else { return }
        let shouldEdit = navigation.pendingOpenEditing
        navigation.pendingOpen = nil
        navigation.pendingOpenEditing = false
        navigation.open(ref)
        if shouldEdit, !editor.isEditing {
            editor.begin(ref, library: library)
        }
    }
}
