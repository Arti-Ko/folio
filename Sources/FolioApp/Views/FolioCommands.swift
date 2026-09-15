import FolioCore
import SwiftUI

struct FolioCommands: Commands {
    let library: LibraryModel
    let updater: Updater
    @FocusedValue(\.navigation) private var navigation
    @FocusedValue(\.editor) private var editor

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            CheckForUpdatesButton(updater: updater)
        }

        CommandGroup(replacing: .newItem) {
            Button("Новая страница…") {
                if let navigation, let parent = navigation.selection {
                    navigation.sheet = .newPage(parent: parent)
                }
            }
            .keyboardShortcut("n")
            .disabled(navigation?.selection == nil)

            NewWindowButton()
        }

        CommandGroup(after: .sidebar) {
            Button("Назад") { navigation?.goBack() }
                .keyboardShortcut("[")
                .disabled(!(navigation?.canGoBack ?? false))
            Button("Вперёд") { navigation?.goForward() }
                .keyboardShortcut("]")
                .disabled(!(navigation?.canGoForward ?? false))
            Divider()
        }

        InspectorCommands()

        CommandMenu("Страница") {
            Button(editor?.isEditing == true ? "Завершить правку" : "Редактировать") {
                guard let editor, let navigation, let ref = navigation.selection else { return }
                if editor.isEditing {
                    editor.requestFinish()
                } else if navigation.version == nil {
                    editor.begin(ref, library: library)
                }
            }
            .keyboardShortcut("e")
            .disabled(navigation?.selection == nil || navigation?.version != nil)

            Divider()

            Button("Переименовать…") {
                if let navigation, let ref = navigation.selection { navigation.sheet = .rename(ref) }
            }
            .disabled(navigation?.selection?.isHome ?? true)

            Button("Показать в Finder") {
                if let ref = navigation?.selection { library.revealInFinder(ref) }
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
            .disabled(navigation?.selection == nil)

            Button("Скопировать путь к файлу") {
                if let ref = navigation?.selection { library.copyPath(ref) }
            }
            .keyboardShortcut("c", modifiers: [.command, .option, .shift])
            .disabled(navigation?.selection == nil)

            Divider()

            Button("Сохранить снимок в истории") {
                if let ref = navigation?.selection {
                    Task { await library.commitChanges(in: ref.spaceID) }
                }
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
            .disabled(navigation?.selection == nil)

            Divider()

            Button("Переместить в Корзину…") {
                if let navigation, let ref = navigation.selection { navigation.pendingTrash = ref }
            }
            .disabled(navigation?.selection?.isHome ?? true)
        }
    }
}

private struct NewWindowButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Новое окно") { openWindow(id: WindowID.library) }
            .keyboardShortcut("n", modifiers: [.command, .shift])
    }
}
