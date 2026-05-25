import SwiftUI
import Foundation
import Combine

/// Manages the Node.js bot process lifecycle.
@MainActor
class BotManager: ObservableObject {
    @Published var isRunning = false
    @Published var lastLogLines: [String] = []
    @Published var pid: Int32? = nil

    private var process: Process?
    private var logFileHandle: FileHandle?
    private var logMonitorTimer: Timer?

    var botDirectory: String {
        NSHomeDirectory() + "/.config/nexus-agent"
    }
    let logFilePath: String
    let pidFilePath: String

    init() {

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("NexusAgent")
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)

        logFilePath = appSupport.appendingPathComponent("bot.log").path
        pidFilePath = appSupport.appendingPathComponent(".bot.pid").path

        // Check if bot is already running from a previous session
        checkExistingProcess()
        startLogMonitor()
    }



    // MARK: - Process Control

    func start() {
        guard !isRunning else { return }

        if botDirectory.isEmpty || !FileManager.default.fileExists(atPath: "\(botDirectory)/src/bot.js") {
            appendLog("Bot source directory not configured. Please set the 'Bot Source' path in Settings.")
            return
        }

        let proc = Process()

        // Find node binary — .app bundles don't inherit shell PATH
        let nodePaths = [
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            "/usr/bin/node",
        ]
        let nodeBin = nodePaths.first { FileManager.default.fileExists(atPath: $0) } ?? "/opt/homebrew/bin/node"

        proc.executableURL = URL(fileURLWithPath: nodeBin)
        proc.arguments = ["src/bot.js"]
        proc.currentDirectoryURL = URL(fileURLWithPath: botDirectory)

        // Redirect stdout/stderr to log file
        FileManager.default.createFile(atPath: logFilePath, contents: nil)
        let logFile = FileHandle(forWritingAtPath: logFilePath)
        proc.standardOutput = logFile
        proc.standardError = logFile

        // Inherit environment and ensure Homebrew paths are in PATH
        var env = ProcessInfo.processInfo.environment
        let existingPath = env["PATH"] ?? ""
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(existingPath)"
        env["NO_COLOR"] = "1"
        proc.environment = env

        proc.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.isRunning = false
                self?.pid = nil
                self?.cleanPidFile()
            }
        }

        do {
            try proc.run()
            process = proc
            pid = proc.processIdentifier
            isRunning = true
            writePidFile(proc.processIdentifier)
            appendLog("Bot started (PID \(proc.processIdentifier))")
        } catch {
            appendLog("Failed to start bot: \(error.localizedDescription)")
        }
    }

    func stop() {
        // Try managed process first
        if let proc = process, proc.isRunning {
            proc.terminate()

            // Wait briefly for graceful shutdown
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                if proc.isRunning {
                    proc.interrupt()
                }
            }
            process = nil
        }

        // Also kill by PID file (handles processes started by bot.sh)
        if let existingPid = readPidFile() {
            kill(existingPid, SIGTERM)
        }

        // Kill any orphan processes
        let killTask = Process()
        killTask.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        killTask.arguments = ["-f", "node src/bot.js"]
        try? killTask.run()
        killTask.waitUntilExit()

        isRunning = false
        pid = nil
        cleanPidFile()
        appendLog("Bot stopped")
    }

    func restart() {
        stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.start()
        }
    }

    // MARK: - Log Monitoring

    private func startLogMonitor() {
        logMonitorTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.readRecentLogs()
                self?.checkExistingProcess()
            }
        }
    }

    private func readRecentLogs() {
        guard FileManager.default.fileExists(atPath: logFilePath) else { return }
        guard let data = FileManager.default.contents(atPath: logFilePath) else { return }
        let text = String(data: data, encoding: .utf8) ?? ""
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        lastLogLines = Array(lines.suffix(20))
    }

    func openLogs() {
        NSWorkspace.shared.open(URL(fileURLWithPath: logFilePath))
    }

    // MARK: - PID File Management

    private func checkExistingProcess() {
        if let existingPid = readPidFile() {
            // Check if process is actually running
            if kill(existingPid, 0) == 0 {
                isRunning = true
                pid = existingPid
            } else {
                cleanPidFile()
                isRunning = false
                pid = nil
            }
        }
    }

    private func readPidFile() -> Int32? {
        guard let data = FileManager.default.contents(atPath: pidFilePath),
              let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let pid = Int32(text) else { return nil }
        return pid
    }

    private func writePidFile(_ pid: Int32) {
        try? "\(pid)".write(toFile: pidFilePath, atomically: true, encoding: .utf8)
    }

    private func cleanPidFile() {
        try? FileManager.default.removeItem(atPath: pidFilePath)
    }

    private func appendLog(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        lastLogLines.append("[\(timestamp)] \(message)")
        if lastLogLines.count > 20 {
            lastLogLines.removeFirst(lastLogLines.count - 20)
        }
    }

    deinit {
        logMonitorTimer?.invalidate()
    }
}
