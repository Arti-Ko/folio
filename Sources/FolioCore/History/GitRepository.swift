import Foundation

public struct ProcessResult: Sendable {
    public let status: Int32
    public let output: String
    public let error: String
}

public enum ProcessRunner {
    /// Запускает программу и ждёт её. Ошибки пишутся во временный файл, чтобы большой вывод не заблокировал канал.
    public static func run(_ executable: URL, arguments: [String], in directory: URL? = nil) throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardInput = FileHandle.nullDevice

        let outputPipe = Pipe()
        process.standardOutput = outputPipe

        let errorURL = FileManager.default.temporaryDirectory.appending(path: "folio-\(UUID().uuidString).stderr")
        FileManager.default.createFile(atPath: String.filePath(errorURL), contents: nil)
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        defer {
            try? errorHandle.close()
            try? FileManager.default.removeItem(at: errorURL)
        }
        process.standardError = errorHandle

        try process.run()
        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return ProcessResult(
            status: process.terminationStatus,
            output: String(decoding: output, as: UTF8.self),
            error: (try? String(contentsOf: errorURL, encoding: .utf8)) ?? ""
        )
    }
}

public struct GitRevision: Sendable, Hashable, Identifiable {
    public let hash: String
    public let date: Date
    public let author: String
    public let message: String
    /// Путь файла в этой версии: после переименований он отличается от текущего.
    public let path: String

    public var id: String { hash }
    public var shortHash: String { String(hash.prefix(7)) }
}

/// История пространства в git: снимки, журнал страницы и её старые версии.
public struct GitRepository: Sendable {
    public static let executable = URL(fileURLWithPath: "/usr/bin/git")
    private static let fieldSeparator: Character = "\u{1f}"
    private static let recordSeparator: Character = "\u{1e}"

    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public var isInitialized: Bool {
        FileManager.default.fileExists(atPath: String.filePath(root.appending(path: ".git")))
    }

    public func initialize() throws {
        guard !isInitialized else { return }
        try git(["init", "--quiet", "--initial-branch=main"])
        let email = try? git(["config", "user.email"])
        if email?.isEmpty ?? true {
            try git(["config", "user.name", "Folio"])
            try git(["config", "user.email", "folio@localhost"])
        }
    }

    public func hasChanges() throws -> Bool {
        !(try git(["status", "--porcelain"])).isEmpty
    }

    /// Сохраняет все изменения одним снимком; `false`, если сохранять нечего.
    @discardableResult
    public func commitAll(message: String) throws -> Bool {
        try git(["add", "--all"])
        guard try hasChanges() else { return false }
        try git(["commit", "--quiet", "-m", message])
        return true
    }

    public func history(of relativePath: String, limit: Int = 200) throws -> [GitRevision] {
        guard isInitialized, (try? git(["rev-parse", "--verify", "--quiet", "HEAD"])) != nil else { return [] }
        let format = "--format=\(Self.recordSeparator)%H\(Self.fieldSeparator)%aI\(Self.fieldSeparator)%an\(Self.fieldSeparator)%s"
        let output = try git(["log", "--follow", "--name-only", "-n", String(limit), format, "--", relativePath])
        return output.split(separator: Self.recordSeparator).compactMap(Self.parseRevision)
    }

    public func contents(of relativePath: String, at hash: String) throws -> String {
        try git(["show", "\(hash):\(relativePath)"], trimOutput: false)
    }

    private static func parseRevision(_ record: Substring) -> GitRevision? {
        let lines = record.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard lines.count >= 2 else { return nil }
        let fields = lines[0].split(separator: fieldSeparator, omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 4, let date = try? Date(fields[1], strategy: .iso8601) else { return nil }
        return GitRevision(hash: fields[0], date: date, author: fields[2], message: fields[3], path: lines[1])
    }

    @discardableResult
    private func git(_ arguments: [String], trimOutput: Bool = true) throws -> String {
        let result = try ProcessRunner.run(Self.executable, arguments: ["-c", "core.quotepath=false"] + arguments, in: root)
        guard result.status == 0 else {
            throw FolioError.commandFailed(
                command: "git \(arguments.first ?? "")",
                message: result.error.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return trimOutput ? result.output.trimmingCharacters(in: .whitespacesAndNewlines) : result.output
    }
}
