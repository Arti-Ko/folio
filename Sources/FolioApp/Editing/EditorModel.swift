import FolioCore
import Observation
import SwiftUI

/// Что под курсором в редакторе — для меню и кнопок в панели окна.
struct FormattingState: Equatable, Sendable {
    var bold = false
    var italic = false
    var strike = false
    var code = false
    var link = false
    var block = "paragraph"
    var inTable = false
    var canUndo = false
    var canRedo = false

    init() {}

    init(_ fields: [String: Any]) {
        bold = fields["bold"] as? Bool ?? false
        italic = fields["italic"] as? Bool ?? false
        strike = fields["strike"] as? Bool ?? false
        code = fields["code"] as? Bool ?? false
        link = fields["link"] as? Bool ?? false
        block = fields["block"] as? String ?? "paragraph"
        inTable = fields["inTable"] as? Bool ?? false
        canUndo = fields["canUndo"] as? Bool ?? false
        canRedo = fields["canRedo"] as? Bool ?? false
    }
}

enum SaveState: Equatable {
    case idle
    case saved(Date)
    case failed(String)
}

struct EditorCommand: Equatable {
    let name: String
    let arguments: [String: String]
    let token = UUID()
}

struct FlushRequest: Equatable {
    enum Reason: Equatable {
        /// «Готово»: забрать последний текст и сохранить снимок.
        case finish
        /// «Оставить мою»: записать текст редактора поверх изменений на диске.
        case overwrite
    }

    let reason: Reason
    let token = UUID()
}

/// Адрес страницы, который веб-часть возвращает вместе с текстом: правка пишется в свою страницу, даже если окно уже на другой.
enum PageKey {
    static func make(_ ref: PageRef) -> String {
        "\(ref.spaceID.uuidString)\n\(ref.path)"
    }

    static func ref(from key: String) -> PageRef? {
        let parts = key.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, let spaceID = UUID(uuidString: String(parts[0])) else { return nil }
        return PageRef(spaceID: spaceID, path: String(parts[1]))
    }
}

/// Режим правки одного окна: автосохранение, конфликты с правками снаружи и снимки в истории.
@MainActor
@Observable
final class EditorModel {
    private(set) var isEditing = false
    private(set) var editingRef: PageRef?
    private(set) var saveState: SaveState = .idle
    private(set) var conflictRef: PageRef?
    private(set) var command: EditorCommand?
    private(set) var flushRequest: FlushRequest?
    /// Растёт, когда страницу нужно перечитать с диска даже во время правки.
    private(set) var reloadToken = 0
    var formatting = FormattingState()

    /// Текст файла, который мы последний раз показали или записали.
    @ObservationIgnored private var baselines: [PageRef: String] = [:]
    @ObservationIgnored private var editedRefs: Set<PageRef> = []
    @ObservationIgnored private var forceOverwrite = false

    private static let lateChangeDelay: Duration = .seconds(1)

    func begin(_ ref: PageRef, library: LibraryModel) {
        guard let url = library.fileURL(for: ref) else { return }
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            baselines[ref] = text
        }
        editingRef = ref
        conflictRef = nil
        saveState = .idle
        formatting = FormattingState()
        isEditing = true
    }

    func requestFinish() {
        guard isEditing else { return }
        flushRequest = FlushRequest(reason: .finish)
    }

    /// Веб-часть отдала последний текст: выходим из правки и сохраняем снимок.
    func completeFinish(library: LibraryModel) {
        let ref = editingRef
        isEditing = false
        editingRef = nil
        conflictRef = nil
        if let ref { snapshot(ref, library: library, after: .zero) }
    }

    /// Окно ушло на другую страницу посреди правки; последний текст веб-часть пришлёт вдогонку.
    func pageChanged(to ref: PageRef?, library: LibraryModel) {
        guard isEditing, let editingRef, editingRef != ref else { return }
        isEditing = false
        self.editingRef = nil
        conflictRef = nil
        snapshot(editingRef, library: library, after: Self.lateChangeDelay)
    }

    func send(_ name: String, _ arguments: [String: String] = [:]) {
        guard isEditing else { return }
        command = EditorCommand(name: name, arguments: arguments)
    }

    /// Показывать ли свежий текст с диска. Во время правки собственное эхо пропускаем, чужую правку считаем конфликтом.
    func shouldRender(_ text: String, for ref: PageRef) -> Bool {
        guard isEditing, editingRef == ref, let baseline = baselines[ref] else {
            baselines[ref] = text
            return true
        }
        guard baseline != text else { return false }
        conflictRef = ref
        return false
    }

    func applyChange(markdown: String, pageKey: String, library: LibraryModel) {
        guard let ref = PageKey.ref(from: pageKey), let url = library.fileURL(for: ref) else { return }
        do {
            let disk = try String(contentsOf: url, encoding: .utf8)
            if !forceOverwrite, let baseline = baselines[ref], baseline != disk {
                conflictRef = ref
                saveState = .failed("страницу изменили снаружи")
                return
            }
            forceOverwrite = false
            let composed = PageWriter.replacingBody(in: disk, with: markdown)
            if composed != disk {
                try Data(composed.utf8).write(to: url, options: .atomic)
                editedRefs.insert(ref)
            }
            baselines[ref] = composed
            if conflictRef == ref { conflictRef = nil }
            saveState = .saved(.now)
        } catch {
            saveState = .failed(error.localizedDescription)
        }
    }

    func keepMyVersion() {
        guard conflictRef != nil else { return }
        forceOverwrite = true
        flushRequest = FlushRequest(reason: .overwrite)
    }

    func takeDiskVersion() {
        guard let ref = conflictRef else { return }
        baselines[ref] = nil
        conflictRef = nil
        saveState = .idle
        reloadToken += 1
    }

    func setProperties(for ref: PageRef, status: String?, labels: [String], library: LibraryModel) {
        guard let url = library.fileURL(for: ref) else { return }
        do {
            let disk = try String(contentsOf: url, encoding: .utf8)
            let updated = PageWriter.settingProperties(in: disk, status: status, labels: labels)
            guard updated != disk else { return }
            try Data(updated.utf8).write(to: url, options: .atomic)
            if baselines[ref] == nil || baselines[ref] == disk {
                baselines[ref] = updated
            }
            editedRefs.insert(ref)
            library.rescanNow(ref.spaceID)
            if !(isEditing && editingRef == ref) {
                snapshot(ref, library: library, after: .zero)
            }
        } catch {
            library.report(error)
        }
    }

    func rename(_ ref: PageRef, to title: String, library: LibraryModel) throws -> PageRef {
        let renamed = try library.renamePage(ref, to: title)
        if let url = library.fileURL(for: renamed), let text = try? String(contentsOf: url, encoding: .utf8) {
            baselines[renamed] = text
        }
        if renamed != ref { baselines[ref] = nil }
        editedRefs.insert(renamed)
        if editingRef == ref { editingRef = renamed }
        if !isEditing { snapshot(renamed, library: library, after: .zero) }
        return renamed
    }

    /// Один снимок в истории на заход в правку.
    private func snapshot(_ ref: PageRef, library: LibraryModel, after delay: Duration) {
        guard editedRefs.remove(ref) != nil else { return }
        let title = library.node(for: ref)?.title ?? ref.path
        Task {
            if delay > .zero { try? await Task.sleep(for: delay) }
            await library.commitEdits(in: ref.spaceID, message: "Правка страницы «\(title)»")
        }
    }
}

extension FocusedValues {
    @Entry var editor: EditorModel?
}
