import AppKit
import FolioCore
import SwiftUI
import UniformTypeIdentifiers
import WebKit
import os

enum AppScheme {
    static let name = "folio"
    static let appHost = "app"
    static let fileHost = "file"
    static let appURL = URL(string: "folio://app/index.html")!

    /// Адрес папки страницы: от него веб-часть разрешает относительные пути вложений.
    static func assetBase(spaceID: UUID, pagePath: String) -> String {
        var components = URLComponents()
        components.scheme = name
        components.host = fileHost
        let segments = [spaceID.uuidString] + pagePath.split(separator: "/").map(String.init)
        components.path = "/" + segments.joined(separator: "/") + "/"
        return components.url?.absoluteString ?? ""
    }

    static var webRoot: URL {
        if let override = ProcessInfo.processInfo.environment["FOLIO_WEB_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return (Bundle.main.resourceURL ?? Bundle.main.bundleURL).appending(path: "web", directoryHint: .isDirectory)
    }
}

enum BridgeMessage {
    case ready
    case openPage(space: String?, title: String)
    case openURL(String)
    case outline([OutlineItem])
    case renderError(String)
    case change(pageKey: String, markdown: String)
    case state(FormattingState)
    case renameTitle(pageKey: String, title: String)
    case saveAttachment(id: String, name: String, data: String)
    case pickAttachment
    case notice(String)

    init?(body: Any) {
        guard let fields = body as? [String: Any], let type = fields["type"] as? String else { return nil }
        switch type {
        case "ready":
            self = .ready
        case "openPage":
            guard let title = fields["title"] as? String, !title.isEmpty else { return nil }
            self = .openPage(space: fields["space"] as? String, title: title)
        case "openURL":
            guard let href = fields["href"] as? String, !href.isEmpty else { return nil }
            self = .openURL(href)
        case "outline":
            let items = (fields["items"] as? [[String: Any]] ?? []).compactMap { item -> OutlineItem? in
                guard let level = item["level"] as? Int, let text = item["text"] as? String, let index = item["index"] as? Int else {
                    return nil
                }
                return OutlineItem(level: level, text: text, index: index)
            }
            self = .outline(items)
        case "renderError":
            self = .renderError(fields["message"] as? String ?? "")
        case "change":
            guard let key = fields["pageKey"] as? String, let markdown = fields["markdown"] as? String else { return nil }
            self = .change(pageKey: key, markdown: markdown)
        case "state":
            self = .state(FormattingState(fields["state"] as? [String: Any] ?? [:]))
        case "renameTitle":
            guard let key = fields["pageKey"] as? String, let title = fields["title"] as? String else { return nil }
            self = .renameTitle(pageKey: key, title: title)
        case "saveAttachment":
            guard let id = fields["id"] as? String, let data = fields["data"] as? String else { return nil }
            self = .saveAttachment(id: id, name: fields["name"] as? String ?? "", data: data)
        case "pickAttachment":
            self = .pickAttachment
        case "notice":
            self = .notice(fields["message"] as? String ?? "")
        default:
            return nil
        }
    }
}

/// Данные для `window.folio.render` в веб-части.
struct PagePayload: Encodable, Sendable {
    struct Status: Encodable, Sendable {
        let label: String
        let color: String
    }

    struct Child: Encodable, Sendable {
        let title: String
    }

    struct PageEntry: Encodable, Sendable {
        let space: String
        let title: String
    }

    let pageKey: String
    let markdown: String
    let title: String
    let status: Status?
    let labels: [String]
    let meta: String
    let assetBase: String
    let links: [String: Bool]
    let children: [Child]
    let pages: [PageEntry]
    let spaceName: String
    let banner: String?
    let resetScroll: Bool
    let editable: Bool
}

/// Один WKWebView на окно: грузит веб-часть один раз и дальше только передаёт ей страницы и команды.
@MainActor
final class PageBridge: NSObject {
    private(set) var webView: WKWebView?
    private var isReady = false
    private var lastPayload: PagePayload?
    private let logger = Logger(subsystem: "org.sleepycoffee.folio", category: "web")

    var onMessage: (BridgeMessage) -> Void = { _ in }
    var spaceRoot: (UUID) -> URL? = { _ in nil }

    func makeWebView() -> WKWebView {
        if let webView { return webView }
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(AppSchemeHandler(bridge: self), forURLScheme: AppScheme.name)
        configuration.userContentController.add(ScriptMessageProxy(bridge: self), name: "folio")

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = self
        view.isInspectable = true
        view.load(URLRequest(url: AppScheme.appURL))
        webView = view
        return view
    }

    func render(_ payload: PagePayload) {
        lastPayload = payload
        send(payload, function: "render")
    }

    /// Шапка и контекст без замены текста — во время правки, когда текст на диске совпадает с редактором.
    func updateHeader(_ payload: PagePayload) {
        lastPayload = payload
        send(payload, function: "updateHeader")
    }

    func restoreHeader() {
        if let lastPayload { send(lastPayload, function: "updateHeader") }
    }

    func setEditable(_ editable: Bool) {
        call("window.folio.setEditable(editable)", ["editable": editable])
    }

    func setPageKey(_ key: String) {
        call("window.folio.setPageKey(key)", ["key": key])
    }

    func run(_ name: String, arguments: [String: String] = [:]) {
        call("window.folio.run(name, args)", ["name": name, "args": arguments])
    }

    func scrollToHeading(_ index: Int) {
        call("window.folio.scrollToHeading(index)", ["index": index])
    }

    func attachmentSaved(id: String, item: AttachmentReply?) {
        call("window.folio.attachmentSaved(id, item)", ["id": id, "item": item?.dictionary ?? NSNull()])
    }

    /// Текст редактора, если он ещё не отправлен; force — отдать в любом случае.
    func takeMarkdown(force: Bool) async -> (pageKey: String, markdown: String)? {
        guard isReady, let webView else { return nil }
        return await withCheckedContinuation { continuation in
            webView.callAsyncJavaScript(
                "return window.folio.takeMarkdown(force)",
                arguments: ["force": force],
                in: nil,
                in: .page
            ) { result in
                guard case .success(let value) = result,
                      let fields = value as? [String: Any],
                      let key = fields["pageKey"] as? String,
                      let markdown = fields["markdown"] as? String else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: (key, markdown))
            }
        }
    }

    fileprivate func receive(_ message: BridgeMessage) {
        switch message {
        case .ready:
            isReady = true
            if let lastPayload { send(lastPayload, function: "render") }
        case .renderError(let text):
            logger.error("Страница не отрисовалась: \(text, privacy: .public)")
        default:
            onMessage(message)
        }
    }

    private func send(_ payload: PagePayload, function: String) {
        guard let data = try? JSONEncoder().encode(payload), let json = String(data: data, encoding: .utf8) else { return }
        call("window.folio.\(function)(JSON.parse(json))", ["json": json])
    }

    private func call(_ script: String, _ arguments: [String: Any]) {
        guard isReady, let webView else { return }
        webView.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .page) { [logger] result in
            if case .failure(let error) = result {
                logger.error("\(script, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

extension PageBridge: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        // Внутри окна живёт только сама веб-часть; вложения грузятся как ресурсы, а не переходами.
        if url.scheme == AppScheme.name, url.host() == AppScheme.appHost {
            decisionHandler(.allow)
            return
        }
        if navigationAction.navigationType == .linkActivated, ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
            NSWorkspace.shared.open(url)
        }
        decisionHandler(.cancel)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        isReady = false
        webView.load(URLRequest(url: AppScheme.appURL))
    }
}

/// Слабая ссылка на мост: иначе userContentController удерживал бы его вечно.
@MainActor
private final class ScriptMessageProxy: NSObject, WKScriptMessageHandler {
    private weak var bridge: PageBridge?

    init(bridge: PageBridge) {
        self.bridge = bridge
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let parsed = BridgeMessage(body: message.body) else { return }
        bridge?.receive(parsed)
    }
}

/// Отдаёт веб-часть из бандла (`folio://app/…`) и вложения страниц (`folio://file/<пространство>/…`).
@MainActor
private final class AppSchemeHandler: NSObject, WKURLSchemeHandler {
    private weak var bridge: PageBridge?

    init(bridge: PageBridge) {
        self.bridge = bridge
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              let fileURL = resolve(url),
              let data = try? Data(contentsOf: fileURL),
              let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": Self.mimeType(for: fileURL),
                    "Content-Length": String(data.count),
                    "Access-Control-Allow-Origin": "*",
                    "Cache-Control": "no-store",
                ]
              ) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}

    private func resolve(_ url: URL) -> URL? {
        let segments = url.path(percentEncoded: false).split(separator: "/").map(String.init)
        switch url.host() {
        case AppScheme.appHost:
            return Self.contained(in: AppScheme.webRoot, segments: segments)
        case AppScheme.fileHost:
            guard let first = segments.first, let id = UUID(uuidString: first), let root = bridge?.spaceRoot(id) else { return nil }
            return Self.contained(in: root, segments: Array(segments.dropFirst()))
        default:
            return nil
        }
    }

    /// Путь внутри корня без выходов наверх.
    private static func contained(in root: URL, segments: [String]) -> URL? {
        guard !segments.isEmpty, !segments.contains(where: { $0 == ".." || $0 == "." }) else { return nil }
        let candidate = segments.reduce(root) { $0.appending(path: $1) }.standardizedFileURL
        let rootPath = root.standardizedFileURL.path(percentEncoded: false)
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return candidate.path(percentEncoded: false).hasPrefix(prefix) ? candidate : nil
    }

    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "js", "mjs": "text/javascript; charset=utf-8"
        case "css": "text/css; charset=utf-8"
        case "html": "text/html; charset=utf-8"
        case "svg": "image/svg+xml"
        default: UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        }
    }
}

struct PageWebView: NSViewRepresentable {
    let bridge: PageBridge

    func makeNSView(context: Context) -> WKWebView {
        bridge.makeWebView()
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
