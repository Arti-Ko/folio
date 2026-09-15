import FolioCore
import SwiftUI

extension ContentView {
    /// Открывает страницу из `folio://open`, как только она появилась в дереве.
    func openPendingPage() {
        guard library.isLoaded, let ref = navigation.pendingOpen, library.node(for: ref) != nil else { return }
        navigation.pendingOpen = nil
        navigation.open(ref)
    }
}
