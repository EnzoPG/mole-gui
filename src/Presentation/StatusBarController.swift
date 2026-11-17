import Cocoa
import WebKit

/// Single Responsibility: Translates between `WKWebView` JavaScript messages and the `BridgeActionRouter`.
public final class WebViewBridgeAdapter: NSObject, WKScriptMessageHandler, BridgeEventEmitting {
    public weak var webView: WKWebView?
    private let router: BridgeActionRouter

    public init(router: BridgeActionRouter) {
        self.router = router
        super.init()
    }

    public func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }

        let reqId = body["reqId"] as? String ?? ""
        let payload = body["payload"] as? [String: Any] ?? [:]
        let request = BridgeRequest(reqId: reqId, action: action, payload: payload)

        router.route(request: request, emitter: self)
    }

    public func resolveRequest(reqId: String, data: [String: Any]) {
        guard !reqId.isEmpty,
              let jsonStr = serializeToJSON(data) else { return }

        let js = "window.__resolveMoleBridge && window.__resolveMoleBridge(\(singleQuotedJS(reqId)), \(jsonStr));"
        evaluateJS(js)
    }

    public func emitEvent(name: String, data: [String: Any]) {
        guard let jsonStr = serializeToJSON(data) else { return }
        let js = "window.__onMoleEvent && window.__onMoleEvent(\(singleQuotedJS(name)), \(jsonStr));"
        evaluateJS(js)
    }

    private func evaluateJS(_ script: String) {
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(script, completionHandler: nil)
        }
    }

    private func serializeToJSON(_ dictionary: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: dictionary, options: []) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func singleQuotedJS(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        return "'\(escaped)'"
    }
}

/// Single Responsibility: Resolves the bundled or local HTML entrypoint URL.
public struct UIResourceLocator {
    public static func resolveIndexURL() -> URL? {
        if let bundleURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "ui") {
            return bundleURL
        }
        if let bundleRootURL = Bundle.main.url(forResource: "index", withExtension: "html") {
            return bundleRootURL
        }
        let localPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("ui/index.html")
        if FileManager.default.fileExists(atPath: localPath.path) {
            return localPath
        }
        return nil
    }
}

/// Single Responsibility: Manages the macOS `NSStatusItem`, `NSPopover`, and standard Edit menu shortcuts.
public final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let webView: WKWebView
    private let emitter: BridgeEventEmitting

    public init(
        bridgeAdapter: WebViewBridgeAdapter,
        popoverSize: NSSize = NSSize(width: 400, height: 540)
    ) {
        self.emitter = bridgeAdapter

        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        contentController.add(bridgeAdapter, name: "moleBridge")
        config.userContentController = contentController

        let rect = NSRect(origin: .zero, size: popoverSize)
        self.webView = WKWebView(frame: rect, configuration: config)
        self.webView.setValue(false, forKey: "drawsBackground")
        self.webView.autoresizingMask = [.width, .height]

        super.init()
        bridgeAdapter.webView = self.webView

        setupEditMenu()
        setupStatusBar(size: popoverSize)
        loadFrontend()
    }

    public func updateTitle(ramUsedGB: String) {
        DispatchQueue.main.async { [weak self] in
            self?.statusItem.button?.title = "🧹 \(ramUsedGB)G"
        }
    }

    public func openPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
        emitter.emitEvent(name: "popoverOpened", data: [:])
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            openPopover()
        }
    }

    private func loadFrontend() {
        if let htmlURL = UIResourceLocator.resolveIndexURL() {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        }
    }

    private func setupStatusBar(size: NSSize) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "🧹"
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        popover = NSPopover()
        popover.contentSize = size
        popover.behavior = .transient
        popover.animates = true

        let viewController = NSViewController()
        viewController.view = webView
        popover.contentViewController = viewController
    }

    private func setupEditMenu() {
        let mainMenu = NSMenu()
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        editMenuItem.submenu = editMenu
        NSApp.mainMenu = mainMenu
    }
}
