import FolioCore
import SwiftUI

/// Кнопки отмены и повтора правки.
struct EditorHistoryButtons: View {
    @Environment(EditorModel.self) private var editor

    var body: some View {
        ControlGroup {
            Button("Отменить", systemImage: "arrow.uturn.backward") { editor.send("undo") }
                .disabled(!editor.formatting.canUndo)
            Button("Повторить", systemImage: "arrow.uturn.forward") { editor.send("redo") }
                .disabled(!editor.formatting.canRedo)
        }
    }
}

struct EditorTextMenu: View {
    @Environment(EditorModel.self) private var editor

    var body: some View {
        Menu {
            blockToggle("Обычный текст", command: "paragraph")
            blockToggle("Заголовок 1", command: "heading1")
            blockToggle("Заголовок 2", command: "heading2")
            blockToggle("Заголовок 3", command: "heading3")
            blockToggle("Цитата", command: "blockquote")
            blockToggle("Блок кода", command: "codeBlock")
            Divider()
            markToggle("Жирный", isOn: editor.formatting.bold, command: "bold")
            markToggle("Курсив", isOn: editor.formatting.italic, command: "italic")
            markToggle("Зачёркнутый", isOn: editor.formatting.strike, command: "strike")
            markToggle("Код", isOn: editor.formatting.code, command: "code")
            Button(editor.formatting.link ? "Изменить ссылку…" : "Ссылка…") { editor.send("link") }
            Divider()
            Button("Очистить форматирование") { editor.send("clearFormatting") }
        } label: {
            Label("Текст", systemImage: "textformat")
        }
        .help("Стиль и оформление текста")
    }

    private func blockToggle(_ title: String, command: String) -> some View {
        Toggle(title, isOn: Binding(get: { editor.formatting.block == command }, set: { _ in editor.send(command) }))
    }

    private func markToggle(_ title: String, isOn: Bool, command: String) -> some View {
        Toggle(title, isOn: Binding(get: { isOn }, set: { _ in editor.send(command) }))
    }
}

struct EditorListMenu: View {
    @Environment(EditorModel.self) private var editor

    var body: some View {
        Menu {
            listToggle("Маркированный список", command: "bulletList")
            listToggle("Нумерованный список", command: "orderedList")
            listToggle("Задачи", command: "taskList")
            Divider()
            Button("Переместить блок выше") { editor.send("moveBlockUp") }
            Button("Переместить блок ниже") { editor.send("moveBlockDown") }
        } label: {
            Label("Списки", systemImage: "list.bullet")
        }
        .help("Списки и порядок блоков (⌥⇧↑, ⌥⇧↓)")
    }

    private func listToggle(_ title: String, command: String) -> some View {
        Toggle(title, isOn: Binding(get: { editor.formatting.block == command }, set: { _ in editor.send(command) }))
    }
}

struct EditorInsertMenu: View {
    @Environment(EditorModel.self) private var editor

    private static let panels: [(type: String, title: String)] = [
        ("info", "Информация"),
        ("note", "Заметка"),
        ("success", "Успех"),
        ("warning", "Предупреждение"),
        ("error", "Ошибка"),
    ]

    var body: some View {
        Menu {
            Button("Таблица", systemImage: "tablecells") { editor.send("insertTable") }
            Menu("Панель") {
                ForEach(Self.panels, id: \.type) { panel in
                    Button(panel.title) { editor.send("insertPanel", ["type": panel.type]) }
                }
            }
            Button("Раскрывающийся блок", systemImage: "chevron.right.square") { editor.send("insertExpand") }
            Button("Статус", systemImage: "capsule") { editor.send("insertStatus") }
            Divider()
            Button("Ссылка на страницу…", systemImage: "link") { editor.send("insertPageLink") }
            Button("Картинка или файл…", systemImage: "photo") { editor.send("requestAttachment") }
            Divider()
            Button("Оглавление", systemImage: "list.bullet.indent") { editor.send("insertToc") }
            Button("Дочерние страницы", systemImage: "rectangle.stack") { editor.send("insertChildren") }
            Button("Разделитель", systemImage: "minus") { editor.send("horizontalRule") }
        } label: {
            Label("Вставить", systemImage: "plus")
        }
        .help("Вставить элемент — или введите «/» в тексте")
    }
}

struct EditorTableMenu: View {
    @Environment(EditorModel.self) private var editor

    var body: some View {
        Menu {
            Button("Строка выше") { editor.send("addRowBefore") }
            Button("Строка ниже") { editor.send("addRowAfter") }
            Button("Столбец слева") { editor.send("addColumnBefore") }
            Button("Столбец справа") { editor.send("addColumnAfter") }
            Divider()
            Button("Строка заголовков") { editor.send("toggleHeaderRow") }
            Divider()
            Button("Удалить строку") { editor.send("deleteRow") }
            Button("Удалить столбец") { editor.send("deleteColumn") }
            Button("Удалить таблицу", role: .destructive) { editor.send("deleteTable") }
        } label: {
            Label("Таблица", systemImage: "tablecells.badge.ellipsis")
        }
        .disabled(!editor.formatting.inTable)
        .help("Строки и столбцы таблицы под курсором")
    }
}

/// Статус и метки страницы в инспекторе.
struct PagePropertiesSection: View {
    let ref: PageRef
    let node: PageNode

    @Environment(LibraryModel.self) private var library
    @Environment(EditorModel.self) private var editor
    @State private var labelsText = ""
    @FocusState private var isLabelsFocused: Bool
    @SceneStorage("inspector.properties") private var isExpanded = true

    private static let presetStatuses = ["Черновик", "В работе", "На согласовании", "Утверждено", "Отклонено", "Архив"]

    var body: some View {
        Section("Свойства", isExpanded: $isExpanded) {
            Picker("Статус", selection: statusBinding) {
                Text("Без статуса").tag(String?.none)
                ForEach(statusOptions, id: \.self) { status in
                    Text(status).tag(Optional(status))
                }
            }
            LabeledContent("Метки") {
                TextField("Метки", text: $labelsText, prompt: Text("через запятую"))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .focused($isLabelsFocused)
                    .onSubmit(saveLabels)
            }
        }
        .onChange(of: node.labels, initial: true) { _, labels in
            if !isLabelsFocused { labelsText = labels.joined(separator: ", ") }
        }
        .onChange(of: isLabelsFocused) { _, isFocused in
            if !isFocused { saveLabels() }
        }
    }

    private var statusOptions: [String] {
        guard let current = node.status?.label, !Self.presetStatuses.contains(current) else { return Self.presetStatuses }
        return Self.presetStatuses + [current]
    }

    private var statusBinding: Binding<String?> {
        Binding(
            get: { node.status?.label },
            set: { status in editor.setProperties(for: ref, status: status, labels: node.labels, library: library) }
        )
    }

    private func saveLabels() {
        let labels = labelsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard labels != node.labels else { return }
        editor.setProperties(for: ref, status: node.status?.label, labels: labels, library: library)
    }
}
