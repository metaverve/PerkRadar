import AppKit
import WebKit
import Darwin

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate {
    var window: NSWindow!
    var webView: WKWebView!
    var server: Process?
    var log: FileHandle?
    var timer: Timer?
    var deadline = Date()
    let origin = URL(string: "http://127.0.0.1:38471")!

    func fail(_ message: String) {
        timer?.invalidate()
        let alert = NSAlert()
        alert.messageText = "PerkRadar could not start"
        alert.informativeText = message
        alert.runModal()
        NSApp.terminate(nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit PerkRadar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let item = NSMenuItem()
        item.submenu = appMenu
        menu.addItem(item)
        let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = editMenu
        menu.addItem(editItem)
        NSApp.mainMenu = menu

        // Keep the origin stable: favorites in localStorage are scoped to the port.
        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else { fail("Could not allocate a local socket."); return }
        var reuse: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(38471).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let available = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
        close(socketFD)
        guard available else { fail("Port 38471 is already in use. Quit the other PerkRadar instance or service, then reopen this app."); return }

        do {
            let resources = Bundle.main.resourceURL!
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("PerkRadar")
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            let logURL = support.appendingPathComponent("server.log")
            if !FileManager.default.fileExists(atPath: logURL.path) {
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
            }
            log = try FileHandle(forWritingTo: logURL)
            log?.seekToEndOfFile()
            let process = Process()
            process.executableURL = resources.appendingPathComponent("node/bin/node")
            process.arguments = [resources.appendingPathComponent("server/server.js").path]
            process.currentDirectoryURL = resources.appendingPathComponent("server")
            var env = ProcessInfo.processInfo.environment
            env["NODE_ENV"] = "production"
            env["HOSTNAME"] = "127.0.0.1"
            env["PORT"] = "38471"
            env["DATA_DIR"] = support.appendingPathComponent("data").path
            env["PERKRADAR_SECURE_COOKIE"] = "0"
            env.removeValue(forKey: "NODE_OPTIONS")
            process.environment = env
            process.standardOutput = log
            process.standardError = log
            try process.run()
            server = process
        } catch { fail(error.localizedDescription); return }

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 850), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "PerkRadar — Starting…"
        window.contentView = webView
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        deadline = Date().addingTimeInterval(60)
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.checkServer() }
    }

    func checkServer() {
        guard server?.isRunning == true, Date() < deadline else {
            fail("The local server stopped or timed out. See ~/Library/Application Support/PerkRadar/server.log.")
            return
        }
        URLSession.shared.dataTask(with: origin.appendingPathComponent("api/health")) { [weak self] _, response, _ in
            DispatchQueue.main.async {
                guard let self = self, self.timer?.isValid == true,
                      self.server?.isRunning == true,
                      (response as? HTTPURLResponse)?.statusCode == 200 else { return }
                self.timer?.invalidate()
                self.window.title = "PerkRadar"
                self.webView.load(URLRequest(url: self.origin))
            }
        }.resume()
    }

    func isLocal(_ url: URL) -> Bool {
        url.scheme == origin.scheme && url.host == origin.host && url.port == origin.port
    }

    func openExternal(_ url: URL) {
        if ["http", "https"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        if isLocal(url) { decisionHandler(.allow) }
        else { openExternal(url); decisionHandler(.cancel) }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url {
            if isLocal(url) { webView.load(action.request) } else { openExternal(url) }
        }
        return nil
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        if let process = server, process.isRunning {
            process.terminate()
            let limit = Date().addingTimeInterval(3)
            while process.isRunning && Date() < limit { Thread.sleep(forTimeInterval: 0.05) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        try? log?.close()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.setActivationPolicy(.regular)
app.delegate = delegate
app.run()
