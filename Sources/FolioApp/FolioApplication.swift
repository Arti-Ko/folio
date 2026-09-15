import AppKit
import FolioCore
import SwiftUI

@main
struct FolioApplication: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var library = LibraryModel()
    @State private var updater = Updater()

    var body: some Scene {
        WindowGroup("Folio", id: WindowID.library) {
            ContentView()
                .environment(library)
                .environment(updater)
                .modifier(UpdatePresenter())
                .onAppear {
                    appDelegate.terminationHandler = { [updater] in
                        updater.installPendingUpdateOnQuit()
                    }
                }
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            FolioCommands(library: library, updater: updater)
        }

        Window("Обновление Folio", id: WindowID.update) {
            UpdateWindowView()
                .environment(updater)
        }
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView()
                .environment(library)
                .environment(updater)
        }
    }
}

enum WindowID {
    static let library = "library"
    static let update = "update"
}

/// При выходе ставит заранее скачанное обновление.
/// applicationDidFinishLaunching и открытие ссылок здесь не реализуем:
/// первое мешает окнам SwiftUI, второе перехватило бы `folio://open` у `onOpenURL`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var terminationHandler: (@MainActor () -> Void)?

    func applicationWillTerminate(_ notification: Notification) {
        terminationHandler?()
    }
}
