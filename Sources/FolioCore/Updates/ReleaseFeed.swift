import Foundation

public struct ReleaseInfo: Hashable, Identifiable, Sendable {
    public let version: AppVersion
    public let notes: String
    public let pageURL: URL
    public let archiveURL: URL
    public let archiveSize: Int

    public var id: String { version.description }
}

public enum UpdateError: LocalizedError, Equatable {
    case badResponse(Int)
    case rateLimited
    case missingArchive
    case invalidArchive
    case notInstalledAsApp
    case notWritable(String)

    public var errorDescription: String? {
        switch self {
        case .badResponse(let status): "GitHub ответил с ошибкой \(status)."
        case .rateLimited: "GitHub временно ограничил запросы. Попробуйте позже."
        case .missingArchive: "В выпуске нет архива приложения."
        case .invalidArchive: "Скачанный архив не похож на Folio."
        case .notInstalledAsApp: "Обновление работает только для собранного Folio.app."
        case .notWritable(let path): "Нет прав на запись в \(path). Скачайте установщик со страницы выпуска."
        }
    }
}

/// Выпуски Folio на GitHub Releases.
public enum ReleaseFeed {
    public static let repository = "Arti-Ko/folio"
    public static let archiveName = "Folio.zip"
    public static let releasesPage = URL(string: "https://github.com/\(repository)/releases")!
    private static let latestEndpoint = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    private static let requestTimeout: TimeInterval = 20

    /// Последний опубликованный выпуск; nil — выпусков ещё нет.
    public static func latest() async throws -> ReleaseInfo? {
        var request = URLRequest(url: latestEndpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: requestTimeout)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // Без User-Agent GitHub API отвечает 403.
        request.setValue("Folio/\(AppVersion.current?.description ?? "dev")", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200: return try parse(data)
        case 404: return nil
        case 403, 429: throw UpdateError.rateLimited
        default: throw UpdateError.badResponse(status)
        }
    }

    public static func parse(_ data: Data) throws -> ReleaseInfo? {
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard !release.draft, !release.prerelease,
              let version = AppVersion(release.tagName),
              let pageURL = URL(string: release.htmlURL) else { return nil }
        guard let asset = release.assets.first(where: { $0.name == archiveName }),
              let archiveURL = URL(string: asset.downloadURL) else {
            throw UpdateError.missingArchive
        }
        return ReleaseInfo(
            version: version,
            notes: release.body ?? "",
            pageURL: pageURL,
            archiveURL: archiveURL,
            archiveSize: asset.size
        )
    }

    /// Текст для окна обновления: без раздела «Установка», заголовки Markdown становятся жирными,
    /// потому что окно показывает только строчную разметку.
    public static func displayNotes(_ markdown: String) -> String {
        var lines: [String] = []
        var isSkipping = false
        for line in markdown.components(separatedBy: .newlines) {
            if line.hasPrefix("#") {
                let title = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                isSkipping = title.localizedCaseInsensitiveContains("установка")
                if !isSkipping {
                    lines.append("**\(title)**")
                }
                continue
            }
            if !isSkipping {
                lines.append(line)
            }
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let downloadURL: String
            let size: Int

            enum CodingKeys: String, CodingKey {
                case name
                case size
                case downloadURL = "browser_download_url"
            }
        }

        let tagName: String
        let body: String?
        let htmlURL: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case body, draft, prerelease, assets
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }
}

/// Скачивание выпуска, проверка и подмена бандла.
public enum UpdateInstaller {
    public static let appBundleName = "Folio.app"

    /// Скачивает и распаковывает выпуск; возвращает путь к проверенному Folio.app.
    public static func download(
        _ release: ReleaseInfo,
        expectedBundleID: String?,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let staging = FileManager.default.temporaryDirectory
            .appending(path: "folio-update-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let archive = staging.appending(path: ReleaseFeed.archiveName)

        try await FileDownloader.download(release.archiveURL, to: archive, expectedSize: release.archiveSize, progress: progress)
        try await Task.detached {
            let result = try ProcessRunner.run(
                URL(fileURLWithPath: "/usr/bin/ditto"),
                arguments: ["-x", "-k", String.filePath(archive), String.filePath(staging)]
            )
            guard result.status == 0 else { throw UpdateError.invalidArchive }
        }.value

        let app = staging.appending(path: appBundleName, directoryHint: .isDirectory)
        let bundle = Bundle(url: app)
        let version = (bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(AppVersion.init)
        guard let expectedBundleID, bundle?.bundleIdentifier == expectedBundleID, version == release.version else {
            throw UpdateError.invalidArchive
        }
        return app
    }

    /// Можно ли заменить бандл: это .app и в его папку разрешена запись.
    public static func canReplace(bundleAt target: URL) -> Bool {
        target.pathExtension == "app"
            && FileManager.default.isWritableFile(atPath: String.filePath(target.deletingLastPathComponent()))
    }

    /// Запускает скрипт, который дождётся выхода процесса и заменит бандл.
    /// relaunch — открыть новую версию сразу после замены; выход из приложения — забота вызывающего.
    public static func startSwap(stagedApp: URL, replacing target: URL, processID: Int32, relaunch: Bool) throws {
        guard target.pathExtension == "app" else { throw UpdateError.notInstalledAsApp }
        let parent = target.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: String.filePath(parent)) else {
            throw UpdateError.notWritable(String.filePath(parent))
        }
        guard FileManager.default.fileExists(atPath: String.filePath(stagedApp)) else { throw UpdateError.invalidArchive }

        let staging = stagedApp.deletingLastPathComponent()
        let script = staging.appending(path: "install.sh")
        try swapScript.write(to: script, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            String.filePath(script),
            String(processID),
            String.filePath(target),
            String.filePath(stagedApp),
            String.filePath(staging),
        ] + (relaunch ? [] : ["--no-launch"])
        try process.run()
    }

    /// Старый бандл сначала отодвигается в сторону: если копирование не удалось, он возвращается на место.
    /// Ссылка на утилиту folio указывает внутрь бандла по неизменному пути и после замены остаётся рабочей.
    /// Пятый аргумент `--no-launch` нужен тестам и установке при выходе.
    public static let swapScript = """
    #!/bin/sh
    pid="$1"; target="${2%/}"; staged="${3%/}"; staging="${4%/}"
    while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
    backup="$target.previous"
    rm -rf "$backup"
    mv "$target" "$backup" || exit 1
    if /usr/bin/ditto "$staged" "$target"; then
        rm -rf "$backup"
    else
        rm -rf "$target"
        mv "$backup" "$target"
    fi
    /usr/bin/xattr -dr com.apple.quarantine "$target" 2>/dev/null
    [ "$5" = "--no-launch" ] || /usr/bin/open "$target"
    rm -rf "$staging"
    """
}

/// Загрузка файла с прогрессом через делегат URLSession.
private final class FileDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let expectedSize: Int
    private let progress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, any Error>?
    private var failure: (any Error)?

    private init(destination: URL, expectedSize: Int, progress: @escaping @Sendable (Double) -> Void) {
        self.destination = destination
        self.expectedSize = expectedSize
        self.progress = progress
    }

    static func download(
        _ url: URL,
        to destination: URL,
        expectedSize: Int,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let downloader = FileDownloader(destination: destination, expectedSize: expectedSize, progress: progress)
        let session = URLSession(configuration: .ephemeral, delegate: downloader, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                downloader.lock.withLock { downloader.continuation = continuation }
                session.downloadTask(with: url).resume()
            }
        } onCancel: {
            session.invalidateAndCancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : Int64(expectedSize)
        guard total > 0 else { return }
        progress(min(1, Double(totalBytesWritten) / Double(total)))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Временный файл удаляется сразу после возврата из метода — переносим его синхронно.
        do {
            if let response = downloadTask.response as? HTTPURLResponse, response.statusCode != 200 {
                throw UpdateError.badResponse(response.statusCode)
            }
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            lock.withLock { failure = error }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let pending = lock.withLock { () -> (CheckedContinuation<Void, any Error>?, (any Error)?) in
            defer { continuation = nil }
            return (continuation, error ?? failure)
        }
        guard let continuation = pending.0 else { return }
        if let error = pending.1 {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }
}
