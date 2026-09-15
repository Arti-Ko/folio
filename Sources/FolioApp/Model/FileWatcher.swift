import CoreServices
import Foundation

/// Следит за папкой пространства через FSEvents и сообщает пути изменившихся файлов.
final class FileWatcher: @unchecked Sendable {
    /// Обработчик живёт, пока его держит поток событий: колбэк не переживёт своего получателя.
    private final class Handler {
        let callback: @Sendable ([String]) -> Void

        init(callback: @escaping @Sendable ([String]) -> Void) {
            self.callback = callback
        }
    }

    private var stream: FSEventStreamRef?

    init(path: String, latency: TimeInterval = 0.3, callback: @escaping @Sendable ([String]) -> Void) {
        let handler = Handler(callback: callback)
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(handler).toOpaque(),
            retain: { info in
                guard let info else { return nil }
                _ = Unmanaged<Handler>.fromOpaque(info).retain()
                return info
            },
            release: { info in
                guard let info else { return }
                Unmanaged<Handler>.fromOpaque(info).release()
            },
            copyDescription: nil
        )
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        let eventHandler: FSEventStreamCallback = { _, info, _, eventPaths, _, _ in
            guard let info else { return }
            let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
            Unmanaged<Handler>.fromOpaque(info).takeUnretainedValue().callback(paths)
        }
        stream = FSEventStreamCreate(
            nil,
            eventHandler,
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        )
        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(stream)
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    /// Служебные файлы git и временные имена при переименовании дерево не меняют.
    static func isRelevant(_ path: String) -> Bool {
        !path.contains("/.git/") && !path.hasSuffix("/.git") && !path.contains("/.folio-rename-") && !path.hasSuffix(".DS_Store")
    }
}
