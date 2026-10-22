import Foundation
import os
import UIKit

/// Bounded, local-only Release diagnostics. File I/O never runs on the UI thread.
final class PerformanceDiagnostics: @unchecked Sendable {
    static let shared = PerformanceDiagnostics()
    private let queue = DispatchQueue(label: "it.letscode.touge-dash.performance", qos: .utility)
    private let logger = Logger(subsystem: "it.letscode.touge-dash", category: "Performance")
    private let lock = NSLock()
    private var heartbeatPending = false
    private var generation = 0
    private var active = false
    private var timer: DispatchSourceTimer?
    private let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    private var fileURL: URL { directory.appendingPathComponent("tougedash-performance.log") }

    @MainActor
    func start() {
        guard timer == nil else { return }
        setActive(UIApplication.shared.applicationState == .active)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(250))
        timer.setEventHandler(handler: timerHandler())
        self.timer = timer
        timer.resume()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        event("launch version=\(version) build=\(build)")
    }

    func setActive(_ value: Bool) {
        lock.lock()
        active = value
        generation += 1
        heartbeatPending = false
        lock.unlock()
        event(value ? "foreground" : "background")
    }

    func event(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        let line = "\(Date.now.timeIntervalSince1970) \(message)\n"
        queue.async { [self] in
            let url = fileURL
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if size > 512 * 1024 {
                let previous = directory.appendingPathComponent("tougedash-performance.previous.log")
                try? FileManager.default.removeItem(at: previous)
                try? FileManager.default.moveItem(at: url, to: previous)
            }
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        }
    }

    static func measure<T>(_ operation: String, threshold: TimeInterval = 0.05, _ body: () throws -> T) rethrows -> T {
        let began = ProcessInfo.processInfo.systemUptime
        defer {
            let elapsed = ProcessInfo.processInfo.systemUptime - began
            if elapsed >= threshold { shared.event("slow operation=\(operation) ms=\(Int(elapsed * 1000))") }
        }
        return try body()
    }

    private func timerHandler() -> @Sendable () -> Void {
        { [weak self] in self?.heartbeat() }
    }

    private func heartbeat() {
        lock.lock()
        guard active, !heartbeatPending else { lock.unlock(); return }
        heartbeatPending = true
        let currentGeneration = generation
        lock.unlock()
        let began = ProcessInfo.processInfo.systemUptime
        DispatchQueue.main.async { [self] in
            lock.lock()
            let valid = active && generation == currentGeneration
            if generation == currentGeneration { heartbeatPending = false }
            lock.unlock()
            let delay = ProcessInfo.processInfo.systemUptime - began
            if valid, delay >= 0.5 { event("main-thread-delay ms=\(Int(delay * 1000))") }
        }
    }
}
