// Copyright (c) 2026 VitruvianSoftware

import Foundation

public struct AgentIntegration {
    public static let shared = AgentIntegration()

    private let fileManager = FileManager.default
    private var homeDir: URL { fileManager.homeDirectoryForCurrentUser }

    public func isClaudeCodeHookInstalled() -> Bool {
        let settingsPath = homeDir.appendingPathComponent(".claude/settings.json")
        guard fileManager.fileExists(atPath: settingsPath.path) else { return false }
        do {
            let data = try Data(contentsOf: settingsPath)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let hooks = json["hooks"] as? [String: Any],
               hooks["Stop"] != nil {
                return true
            }
        } catch {}
        return false
    }

    public func isLaunchAgentInstalled() -> Bool {
        let plistPath = homeDir.appendingPathComponent("Library/LaunchAgents/com.james.chat-monitor.plist")
        return fileManager.fileExists(atPath: plistPath.path)
    }

    public func installClaudeCodeHook() throws {
        let settingsPath = homeDir.appendingPathComponent(".claude/settings.json")
        var json: [String: Any] = [:]
        if fileManager.fileExists(atPath: settingsPath.path) {
            let data = try Data(contentsOf: settingsPath)
            json = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        }
        var hooks = (json["hooks"] as? [String: Any]) ?? [:]
        let stopHook: [[String: Any]] = [
            [
                "hooks": [
                    [
                        "type": "command",
                        "command": "python3 /Users/james/.claude/skills/google-home/hooks/stop_broadcast.py",
                        "timeout": 5
                    ]
                ]
            ]
        ]
        hooks["Stop"] = stopHook
        json["hooks"] = hooks
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: settingsPath, options: .atomic)
    }

    public func installLaunchAgent() throws {
        let agentsDir = homeDir.appendingPathComponent("Library/LaunchAgents")
        if !fileManager.fileExists(atPath: agentsDir.path) {
            try fileManager.createDirectory(at: agentsDir, withIntermediateDirectories: true)
        }
        let plistPath = agentsDir.appendingPathComponent("com.james.chat-monitor.plist")
        let plistContent = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.james.chat-monitor</string>
    <key>ProgramArguments</key>
    <array>
        <string>\(homeDir.path)/bin/chat-monitor</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>\(homeDir.path)/.gemini/chat_monitor.log</string>
    <key>StandardErrorPath</key>
    <string>\(homeDir.path)/.gemini/chat_monitor.log</string>
</dict>
</plist>
"""
        try plistContent.write(to: plistPath, atomically: true, encoding: .utf8)
    }
}
