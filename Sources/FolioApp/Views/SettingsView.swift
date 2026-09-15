import AppKit
import FolioCore
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("Пространства", systemImage: "books.vertical") {
                SpacesSettings()
            }
            Tab("Командная строка", systemImage: "terminal") {
                CommandLineSettings()
            }
            Tab("Обновления", systemImage: "arrow.down.circle") {
                UpdateSettings()
            }
        }
        .frame(width: 580, height: 420)
    }
}

private struct SpacesSettings: View {
    @Environment(LibraryModel.self) private var library
    @State private var isCreating = false

    var body: some View {
        Form {
            Section {
                ForEach(library.snapshots, id: \.space.id) { snapshot in
                    LabeledContent {
                        HStack {
                            Button("Показать") {
                                NSWorkspace.shared.activateFileViewerSelecting([snapshot.space.root])
                            }
                            Button("Отключить") {
                                Task { await library.removeSpace(snapshot.space.id) }
                            }
                        }
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(snapshot.space.name)
                                Text(snapshot.space.rootPath)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        } icon: {
                            Image(systemName: snapshot.space.icon)
                        }
                    }
                }
            } header: {
                Text("Подключённые пространства")
            } footer: {
                Text("«Отключить» убирает пространство из Folio, файлы остаются на месте.")
            }

            Section {
                Button("Создать пространство…") { isCreating = true }
                Button("Подключить готовую папку…", action: library.chooseAndAddSpace)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $isCreating) {
            CreateSpaceForm()
                .environment(library)
        }
    }
}

private struct CreateSpaceForm: View {
    @Environment(LibraryModel.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind = SpaceKind.blank
    @State private var parentFolder = FolioPaths.defaultSpacesFolder
    @State private var errorText: String?

    var body: some View {
        Form {
            Section {
                TextField("Название", text: $name)
                Picker("Тип", selection: $kind) {
                    Text("Рабочее — шаблоны протокола, требований и ТЗ").tag(SpaceKind.work)
                    Text("Личное — шаблон заметки").tag(SpaceKind.personal)
                    Text("Пустое").tag(SpaceKind.blank)
                }
                LabeledContent("Папка") {
                    HStack {
                        Text(parentFolder.appending(path: PageOperations.folderName(for: name.isEmpty ? "…" : name)).path(percentEncoded: false))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Выбрать…", action: chooseFolder)
                    }
                }
            } footer: {
                if let errorText {
                    Text(errorText).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Новое пространство")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Создать", action: create)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .frame(width: 520)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Выбрать"
        if panel.runModal() == .OK, let url = panel.url {
            parentFolder = url
        }
    }

    private func create() {
        Task {
            do {
                try await library.createSpace(name: name, kind: kind, in: parentFolder)
                dismiss()
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}

private struct CommandLineSettings: View {
    @State private var status = CommandLineTool.currentStatus()
    @State private var errorText: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Команда", value: "folio")
                LabeledContent("Состояние", value: status.description)
            } footer: {
                Text("Утилита работает с теми же пространствами, что и приложение: дерево, поиск, новые страницы, переименование с починкой ссылок, проверка и история.")
            }
            Section {
                Button(status == .installed ? "Переустановить" : "Установить в \(CommandLineTool.linkURL.deletingLastPathComponent().path(percentEncoded: false))") {
                    do {
                        try CommandLineTool.install()
                        errorText = nil
                    } catch {
                        errorText = error.localizedDescription
                    }
                    status = CommandLineTool.currentStatus()
                }
                .disabled(CommandLineTool.bundledURL == nil)
                if let errorText {
                    Text(errorText).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }
}

enum CommandLineTool {
    enum Status: Equatable {
        case installed
        case missing
        case occupied

        var description: String {
            switch self {
            case .installed: "установлена"
            case .missing: "не установлена"
            case .occupied: "по этому пути лежит другой файл"
            }
        }
    }

    static let linkURL = URL(fileURLWithPath: "/opt/homebrew/bin/folio")

    static var bundledURL: URL? {
        guard let url = Bundle.main.executableURL?.deletingLastPathComponent().appending(path: "folio"),
              FileManager.default.isExecutableFile(atPath: url.path(percentEncoded: false)) else { return nil }
        return url
    }

    static func currentStatus() -> Status {
        let linkPath = linkURL.path(percentEncoded: false)
        guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: linkPath) else {
            return FileManager.default.fileExists(atPath: linkPath) ? .occupied : .missing
        }
        return destination == bundledURL?.path(percentEncoded: false) ? .installed : .occupied
    }

    static func install() throws {
        guard let bundledURL else { return }
        let linkPath = linkURL.path(percentEncoded: false)
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: linkPath)) != nil {
            try FileManager.default.removeItem(atPath: linkPath)
        }
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: bundledURL)
    }
}
