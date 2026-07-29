import Cocoa
import ScreenSaver
import WebKit
import CoreLocation

/// Screen saver host. Keep init lightweight — System Settings probes every .saver on open;
/// creating WKWebView too early can prevent the module from appearing in the list.
@objc(OverheadFlightsView)
final class OverheadFlightsView: ScreenSaverView, WKNavigationDelegate, CLLocationManagerDelegate {

    private var webView: WKWebView?
    private var locationManager: CLLocationManager?
    private var lastLocation: CLLocationCoordinate2D?
    private var started = false
    private var titleLabel: NSTextField?

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        animationTimeInterval = 0

        // Lightweight placeholder so Settings can enumerate / preview without WebKit
        let label = NSTextField(labelWithString: "Overhead Flights")
        label.textColor = NSColor(white: 0.55, alpha: 1)
        label.font = NSFont.systemFont(ofSize: isPreview ? 11 : 22, weight: .ultraLight)
        label.alignment = .center
        label.drawsBackground = false
        label.isBezeled = false
        label.isEditable = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        titleLabel = label
    }

    deinit {
        locationManager?.stopUpdatingLocation()
        webView?.navigationDelegate = nil
    }

    // MARK: - ScreenSaverView

    override func startAnimation() {
        super.startAnimation()
        guard !started else { return }
        started = true

        // Full-screen run: bring up web UI + location
        if !isPreview {
            titleLabel?.isHidden = true
            startLocation()
            installWebView()
            loadBundledPage()
        } else {
            // Preview thumbnail: keep lightweight label only
            titleLabel?.stringValue = "Overhead Flights"
        }
    }

    override func stopAnimation() {
        super.stopAnimation()
    }

    override func animateOneFrame() {}

    override var hasConfigureSheet: Bool { false }
    override var configureSheet: NSWindow? { nil }

    // MARK: - Web

    private func installWebView() {
        if webView != nil { return }

        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = false
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        let wv = WKWebView(frame: bounds, configuration: config)
        wv.autoresizingMask = [.width, .height]
        wv.navigationDelegate = self
        wv.setValue(false, forKey: "drawsBackground")
        wv.allowsBackForwardNavigationGestures = false
        if #available(macOS 13.3, *) {
            wv.isInspectable = false
        }
        addSubview(wv)
        webView = wv
    }

    private func loadBundledPage() {
        guard let wv = webView else { return }
        let bundle = Bundle(for: OverheadFlightsView.self)
        guard let pageURL = bundle.url(forResource: "index", withExtension: "html", subdirectory: "Web")
                ?? bundle.url(forResource: "index", withExtension: "html") else {
            titleLabel?.isHidden = false
            titleLabel?.stringValue = "Missing Web/index.html"
            titleLabel?.textColor = NSColor(white: 0.7, alpha: 1)
            return
        }
        let dir = pageURL.deletingLastPathComponent()
        wv.loadFileURL(pageURL, allowingReadAccessTo: dir)
    }

    private func injectLocationIfPossible() {
        guard let coord = lastLocation, let wv = webView else { return }
        let js = """
        window.__OVERHEAD_FIXED_POS__ = { lat: \(coord.latitude), lon: \(coord.longitude) };
        if (typeof window.__overheadApplyNativePos === 'function') {
          window.__overheadApplyNativePos();
        }
        """
        wv.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - Location

    private func startLocation() {
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        locationManager = manager
        manager.requestLocation()
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        injectLocationIfPossible()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.navigationType == .linkActivated {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        lastLocation = loc.coordinate
        injectLocationIfPossible()
        manager.stopUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // HTML falls back to cache / London
    }
}
