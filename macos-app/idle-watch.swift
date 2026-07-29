import Foundation
import AppKit
import IOKit

/// Idle → launch Overhead Flights fullscreen (acts as screensaver).
/// Logs to /tmp/overhead-flights-idle.log

let appName = "Overhead Flights"
let appBundleId = "com.portfolio.overheadflights.app"
let appPath = "/Applications/Overhead Flights.app"
var idleSecondsThreshold: Double = 90
let pollInterval: TimeInterval = 5
let cooldownSeconds: TimeInterval = 45

func log(_ msg: String) {
    let line = "\(ISO8601DateFormatter().string(from: Date()))  \(msg)\n"
    if let data = line.data(using: .utf8) {
        let path = "/tmp/overhead-flights-idle.log"
        if let fh = FileHandle(forWritingAtPath: path) {
            fh.seekToEndOfFile()
            fh.write(data)
            try? fh.close()
        } else {
            FileManager.default.createFile(atPath: path, contents: data)
        }
    }
}

func hidIdleSeconds() -> Double {
    var iter: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"), &iter) == KERN_SUCCESS else {
        return 0
    }
    defer { IOObjectRelease(iter) }
    let entry = IOIteratorNext(iter)
    guard entry != 0 else { return 0 }
    defer { IOObjectRelease(entry) }

    var props: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
          let dict = props?.takeRetainedValue() as? [String: Any] else {
        return 0
    }
    // HIDIdleTime may be NSNumber
    let raw = dict["HIDIdleTime"]
    let ns: UInt64
    if let n = raw as? UInt64 {
        ns = n
    } else if let n = raw as? Int {
        ns = UInt64(n)
    } else if let n = raw as? NSNumber {
        ns = n.uint64Value
    } else {
        return 0
    }
    return Double(ns) / 1_000_000_000.0
}

func isAppRunning() -> Bool {
    NSWorkspace.shared.runningApplications.contains {
        $0.bundleIdentifier == appBundleId
            || $0.localizedName == appName
            || ($0.bundleURL?.path.contains("Overhead Flights.app") ?? false)
    }
}

func launchApp() {
    let url = URL(fileURLWithPath: appPath)
    guard FileManager.default.fileExists(atPath: appPath) else {
        log("ERROR: app missing at \(appPath)")
        return
    }
    let config = NSWorkspace.OpenConfiguration()
    config.activates = true
    NSWorkspace.shared.openApplication(at: url, configuration: config) { app, err in
        if let err = err {
            log("launch error: \(err.localizedDescription)")
        } else {
            log("launched pid=\(app?.processIdentifier ?? -1)")
        }
    }
}

var lastLaunchAttempt: Date?
var wasRunning = false

func tick() {
    let running = isAppRunning()
    if wasRunning && !running {
        log("app quit")
        lastLaunchAttempt = Date() // cooldown after quit
    }
    wasRunning = running
    if running { return }

    if let t = lastLaunchAttempt, Date().timeIntervalSince(t) < cooldownSeconds {
        return
    }

    let idle = hidIdleSeconds()
    if idle >= idleSecondsThreshold {
        log(String(format: "idle %.0fs ≥ %.0fs → launch", idle, idleSecondsThreshold))
        lastLaunchAttempt = Date()
        launchApp()
        wasRunning = true
    }
}

// Optional threshold from env
if let env = ProcessInfo.processInfo.environment["OVERHEAD_IDLE_SECONDS"],
   let v = Double(env), v >= 15 {
    idleSecondsThreshold = v
}

log("idle-watch start threshold=\(idleSecondsThreshold)s")
let timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { _ in
    tick()
}
RunLoop.main.add(timer, forMode: .common)
tick()
RunLoop.main.run()
