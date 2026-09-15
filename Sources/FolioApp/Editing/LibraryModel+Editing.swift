import FolioCore
import Foundation
import UniformTypeIdentifiers

/// Файл, положенный рядом со страницей; веб-часть вставляет его картинкой или ссылкой.
struct AttachmentReply: Codable, Sendable {
    let path: String
    let name: String
    let isImage: Bool

    var dictionary: [String: Any] {
        ["path": path, "name": name, "isImage": isImage]
    }
}

extension LibraryModel {
    func saveAttachment(_ data: Data, named name: String, for ref: PageRef) throws -> AttachmentReply {
        let folder = try pageFolder(for: ref)
        let fileName = AttachmentNaming.availableName(for: name.isEmpty ? "Вставка" : name, in: folder)
        try data.write(to: folder.appending(path: fileName), options: .atomic)
        return AttachmentReply(path: fileName, name: fileName, isImage: Self.isImage(fileName))
    }

    func copyAttachment(from source: URL, for ref: PageRef) throws -> AttachmentReply {
        let folder = try pageFolder(for: ref)
        let fileName = AttachmentNaming.availableName(for: source.lastPathComponent, in: folder)
        try FileManager.default.copyItem(at: source, to: folder.appending(path: fileName))
        return AttachmentReply(path: fileName, name: source.lastPathComponent, isImage: Self.isImage(fileName))
    }

    /// Снимок в истории с понятным описанием; после него инспектор перечитывает историю.
    func commitEdits(in spaceID: UUID, message: String) async {
        guard let root = snapshot(for: spaceID)?.space.root else { return }
        let result = await Task.detached(priority: .utility) {
            Result { try GitRepository(root: root).commitAll(message: message) }
        }.value
        if case .failure(let error) = result {
            report(error)
        }
        rescanNow(spaceID)
    }

    private func pageFolder(for ref: PageRef) throws -> URL {
        guard let snapshot = snapshot(for: ref.spaceID), snapshot.page(at: ref.path) != nil else {
            throw FolioError.pageNotFound(ref.path)
        }
        return snapshot.folderURL(for: ref.path)
    }

    private static func isImage(_ fileName: String) -> Bool {
        UTType(filenameExtension: URL(fileURLWithPath: fileName).pathExtension)?.conforms(to: .image) ?? false
    }
}
