// Copyright (c) 2026 VitruvianSoftware

import Foundation

@MainActor
public class ChatMonitorService: ObservableObject {
    public static let shared = ChatMonitorService()

    @Published public var isRunning: Bool = false
    @Published public var lastPollTime: Date?
    @Published public var lastError: String?
    @Published public var pid: Int32?

    private var process: Process?
    private var logTimer: Timer?
    private var lastReadOffset: UInt64 = 0

    private let monitorScript: String
    private let logFilePath: String

    public init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.monitorScript = "\(home)/bin/chat-monitor"
        self.logFilePath = "\(home)/.gemini/chat_monitor.log"

        // Initialize log offset to end of current log so we only read new messages
        if let attrs = try? FileManager.default.attributesOfItem(atPath: logFilePath),
           let size = attrs[.size] as? UInt64 {
            self.lastReadOffset = size
        }

        // Check if already running from another process
        checkExistingProcess()

        // Auto-start on app launch if not already running
        if !isRunning {
            start()
        } else {
            startLogMonitor()
        }
    }

    public func start() {
        guard !isRunning else { return }

        // Clean up any stale or orphan processes first
        pkillExisting()

        guard FileManager.default.isExecutableFile(atPath: monitorScript) else {
            lastError = "Executable not found at \(monitorScript)"
            return
        }

        // Sources + poll interval come from Settings > Chat & Slack.
        guard let arguments = ConfigManager.shared.config.effectiveChatMonitor.daemonArguments else {
            lastError = "Both sources are off. Enable Google Chat or Slack to start monitoring."
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: monitorScript)
        proc.arguments = arguments

        // Configure environment with Homebrew and local user PATHs
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let existingPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = "\(home)/bin:\(home)/.local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:\(existingPath)"
        proc.environment = env

        // Redirect output to log file
        let logURL = URL(fileURLWithPath: logFilePath)
        if !FileManager.default.fileExists(atPath: logFilePath) {
            try? "".write(to: logURL, atomically: true, encoding: .utf8)
        }
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            proc.standardOutput = handle
            proc.standardError = handle
        }

        proc.terminationHandler = { [weak self] p in
            Task { @MainActor in
                self?.isRunning = false
                self?.pid = nil
                self?.stopLogMonitor()
            }
        }

        do {
            try proc.run()
            self.process = proc
            self.pid = proc.processIdentifier
            self.isRunning = true
            self.lastError = nil
            self.lastPollTime = Date()
            startLogMonitor()
        } catch {
            lastError = "Failed to start chat monitor: \(error.localizedDescription)"
        }
    }

    /// Re-launches the daemon so a changed source toggle or poll interval
    /// takes effect. No-op while stopped: the next `start()` reads the config.
    public func restartIfRunning() {
        guard isRunning else { return }
        stop()
        start()
    }

    public func stop() {
        if let p = process, p.isRunning {
            p.terminate()
        }
        process = nil
        pid = nil
        isRunning = false
        stopLogMonitor()
        pkillExisting()
    }

    private func checkExistingProcess() {
        let pipe = Pipe()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        proc.arguments = ["-f", "python.*chat-monitor"]
        proc.standardOutput = pipe
        try? proc.run()
        proc.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           let firstPid = output.components(separatedBy: .newlines).first,
           let parsedPid = Int32(firstPid) {
            self.pid = parsedPid
            self.isRunning = true
            self.lastPollTime = Date()
        }
    }

    private func pkillExisting() {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        proc.arguments = ["-f", "python.*chat-monitor"]
        try? proc.run()
        proc.waitUntilExit()
    }

    private func startLogMonitor() {
        stopLogMonitor()
        logTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.readNewLogLines()
            }
        }
    }

    private func stopLogMonitor() {
        logTimer?.invalidate()
        logTimer = nil
    }

    private func readNewLogLines() {
        guard FileManager.default.fileExists(atPath: logFilePath) else { return }
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: logFilePath)) else { return }
        defer { try? handle.close() }

        let currentSize = handle.seekToEndOfFile()
        guard currentSize > lastReadOffset else { return }

        try? handle.seek(toOffset: lastReadOffset)
        let newData = handle.readDataToEndOfFile()
        lastReadOffset = currentSize

        guard let text = String(data: newData, encoding: .utf8) else { return }

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            // Check if broadcast occurred
            // Format: [2026-09-18 13:00:15] Broadcast sent to Lake Office display: 'Slack message from alice in general: hi'
            if let range = trimmed.range(of: "Broadcast sent to ") {
                let rest = String(trimmed[range.upperBound...])
                let parts = rest.components(separatedBy: ": '")
                if parts.count >= 2 {
                    let targetName = parts[0]
                    var message = parts.dropFirst().joined(separator: ": '")
                    if message.hasSuffix("'") {
                        message.removeLast()
                    }

                    let source = message.lowercased().contains("slack") ? "Slack" : "Google Chat"
                    ConfigManager.shared.addLogItem(BroadcastLogItem(
                        text: message,
                        targetName: targetName,
                        source: source
                    ))
                }
            }

            // Update last poll time whenever log activity happens
            self.lastPollTime = Date()
        }
    }
}
