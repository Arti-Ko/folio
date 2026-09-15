import FolioCore
import SwiftUI

struct PageSheetView: View {
    let sheet: PageSheet

    var body: some View {
        switch sheet {
        case .newPage(let parent):
            NewPageForm(parent: parent)
        case .rename(let ref):
            RenamePageForm(ref: ref)
        }
    }
}

private struct NewPageForm: View {
    let parent: PageRef

    @Environment(LibraryModel.self) private var library
    @Environment(NavigationModel.self) private var navigation
    @Environment(EditorModel.self) private var editor
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var template: String?
    @State private var errorText: String?
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        Form {
            Section {
                TextField("Заголовок", text: $title)
                    .focused($isTitleFocused)
                    .onSubmit(create)
                Picker("Шаблон", selection: $template) {
                    Text("Без шаблона").tag(String?.none)
                    ForEach(library.templates(for: parent.spaceID), id: \.self) { name in
                        Text(name).tag(Optional(name))
                    }
                }
                LabeledContent("Внутри", value: library.node(for: parent)?.title ?? "")
            } footer: {
                if let errorText {
                    Text(errorText)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Новая страница")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Создать", action: create)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .frame(width: 460)
        .onAppear { isTitleFocused = true }
    }

    private func create() {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        do {
            let ref = try library.createPage(title: title, under: parent, template: template)
            navigation.open(ref)
            // Новую страницу сразу открываем на правку, как в Confluence.
            editor.begin(ref, library: library)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

private struct RenamePageForm: View {
    let ref: PageRef

    @Environment(LibraryModel.self) private var library
    @Environment(NavigationModel.self) private var navigation
    @Environment(EditorModel.self) private var editor
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var errorText: String?
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        Form {
            Section {
                TextField("Заголовок", text: $title)
                    .focused($isTitleFocused)
                    .onSubmit(rename)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ссылки на страницу обновятся во всех пространствах.")
                        .foregroundStyle(.secondary)
                    if let errorText {
                        Text(errorText)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Переименовать страницу")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Переименовать", action: rename)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .frame(width: 460)
        .onAppear {
            title = library.node(for: ref)?.title ?? ""
            isTitleFocused = true
        }
    }

    private func rename() {
        do {
            let renamed = try editor.rename(ref, to: title, library: library)
            if navigation.selection == ref {
                navigation.relocate(to: renamed)
            }
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
