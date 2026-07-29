import Cocoa
import WebKit
import CoreLocation

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, CLLocationManagerDelegate {
    var window: NSWindow!
    var webView: WKWebView!
    var locationManager: CLLocationManager?
    var lastLocation: CLLocationCoordinate2D?
    var monitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)

        window = NSWindow(
            contentRect: screen,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = true
        window.backgroundColor = .black
        window.level = .screenSaver
        window.collectionBehavior = [.fullScreenPrimary, .canJoinAllSpaces, .stationary]
        window.setFrame(screen, display: true)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Hide cursor like a screensaver
        NSCursor.hide()
        CGDisplayHideCursor(CGMainDisplayID())

        let config = WKWebViewConfiguration()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        webView = WKWebView(frame: window.contentView!.bounds, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        window.contentView?.addSubview(webView)

        loadPage()
        startLocation()
        installExitMonitors()
    }

    private func loadPage() {
        // Prefer bundled Web/, else sibling ../index.html when running from build folder
        let bundle = Bundle.main
        if let url = bundle.url(forResource: "index", withExtension: "html", subdirectory: "Web")
            ?? bundle.url(forResource: "index", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            return
        }

        let fallback = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("index.html")
        if FileManager.default.fileExists(atPath: fallback.path) {
            webView.loadFileURL(fallback, allowingReadAccessTo: fallback.deletingLastPathComponent())
        }
    }

    private func startLocation() {
        let m = CLLocationManager()
        m.delegate = self
        m.desiredAccuracy = kCLLocationAccuracyKilometer
        locationManager = m
        m.requestLocation()
    }

    private func injectLocation() {
        guard let c = lastLocation else { return }
        let js = """
        window.__OVERHEAD_FIXED_POS__ = { lat: \(c.latitude), lon: \(c.longitude) };
        if (typeof window.__overheadApplyNativePos === 'function') {
          window.__overheadApplyNativePos();
        }
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func installExitMonitors() {
        // Any key or mouse movement ends "screensaver" mode
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .mouseMoved, .scrollWheel]) { [weak self] _ in
            self?.quitSaver()
        }
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.quitSaver()
            return nil
        }
    }

    private func quitSaver() {
        NSCursor.unhide()
        CGDisplayShowCursor(CGMainDisplayID())
        NSApp.terminate(nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        injectLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastLocation = locations.last?.coordinate
        injectLocation()
        manager.stopUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
