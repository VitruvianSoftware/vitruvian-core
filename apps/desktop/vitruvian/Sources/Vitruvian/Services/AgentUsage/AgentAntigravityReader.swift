// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Darwin
import Foundation
import SQLite3
import VitruvianCore
import VitruvianDesign

/// Reads Antigravity session telemetry from `~/.gemini/antigravity/.telemetry_state.json`
/// and conversation metadata from `conversation_summaries.db`, and probes the local
/// Antigravity language_server daemon for live quota limits.
package enum AgentAntigravityReader {
    package static let telemetryStateFile = ".telemetry_state.json"
    package static let conversationDBFile = "conversation_summaries.db"

    // MARK: - Telemetry & History Reading

    /// Reads conversation IDs to workspace project names from `conversation_summaries.db`.
    package static func readProjects(from dbURL: URL) -> [String: String] {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            return [:]
        }
        sqlite3_busy_timeout(db, 1000)

        let query = "SELECT conversation_id, workspace_uris FROM conversation_summaries"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            return [:]
        }

        var projects: [String: String] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let convIDCol = sqlite3_column_text(stmt, 0) else { continue }
            let convID = String(cString: convIDCol)
            var project = "Workspace"
            if let urisCol = sqlite3_column_text(stmt, 1) {
                let urisText = String(cString: urisCol)
                project = extractProject(from: urisText)
            }
            projects[convID] = project
        }
        return projects
    }

    /// Extracts project directory name from workspace_uris text (JSON or plain URI).
    package static func extractProject(from urisText: String) -> String {
        var uriString = urisText
        if urisText.hasPrefix("[") && urisText.hasSuffix("]") {
            if let data = urisText.data(using: .utf8),
               let array = (try? JSONSerialization.jsonObject(with: data)) as? [String],
               let first = array.first {
                uriString = first
            }
        }
        if uriString.hasPrefix("file://") {
            uriString = String(uriString.dropFirst(7))
        }
        while uriString.hasSuffix("/") {
            uriString.removeLast()
        }
        let name = (uriString as NSString).lastPathComponent
        return name.isEmpty ? "Workspace" : AgentLogParser.projectName(name)
    }

    /// Parses telemetry state JSON data into records.
    package static func parseTelemetryState(_ data: Data, projects: [String: String]) -> [AgentUsageRecord] {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: [String: Any]] else {
            return []
        }

        var records: [AgentUsageRecord] = []
        for (transcriptPath, item) in json {
            guard let tokensObj = item["tokens"] as? [String: Any] else { continue }
            let input = AgentLogParser.int(tokensObj["input"])
            let output = AgentLogParser.int(tokensObj["output"])
            let cached = AgentLogParser.int(tokensObj["cached"])
            let thinking = AgentLogParser.int(tokensObj["thinking"])
            let model = (item["model"] as? String) ?? "gemini-3.7-flash"
            let turns = AgentLogParser.int(item["turns"])
            let mtime = (item["mtime"] as? NSNumber)?.doubleValue ?? Date().timeIntervalSince1970

            var convID = "unknown"
            if let brainRange = transcriptPath.range(of: "/brain/") {
                let after = transcriptPath[brainRange.upperBound...]
                if let slash = after.firstIndex(of: "/") {
                    convID = String(after[..<slash])
                } else {
                    convID = String(after)
                }
            }

            let project = projects[convID] ?? "Workspace"
            let tokens = AgentTokens(input: input, cacheRead: cached, output: output, reasoning: thinking)
            let billable = AgentBillable(tokens: tokens)
            let priced = AgentPricing.cost(billable, model: model)

            let record = AgentUsageRecord(
                provider: .antigravity,
                date: Date(timeIntervalSince1970: mtime),
                model: model,
                project: project,
                session: convID,
                requests: max(1, turns),
                tokens: tokens,
                cost: priced.cost,
                savings: priced.savings
            )
            records.append(record)
        }
        return records
    }

    /// Reads telemetry state and conversation DB, applying usage records to the store.
    package static func read(store: AgentUsageStore, enabled: Set<AgentProvider>, home: URL, now: Date) {
        guard enabled.contains(.antigravity) else { return }
        let base = home.appending(path: ".gemini/antigravity", directoryHint: .isDirectory)
        let dbURL = base.appending(path: conversationDBFile, directoryHint: .notDirectory)
        let stateURL = base.appending(path: telemetryStateFile, directoryHint: .notDirectory)

        let projects = FileManager.default.fileExists(atPath: dbURL.path) ? readProjects(from: dbURL) : [:]

        guard let data = try? Data(contentsOf: stateURL), !data.isEmpty else { return }
        let records = parseTelemetryState(data, projects: projects)

        for record in records {
            let billable = AgentBillable(tokens: record.tokens)
            let key = "antigravity:\(record.session):\(record.model)"
            let entry: AgentLogEntry = .usage(key: key, record: record, billable: billable)
            store.apply([entry], file: record.session, provider: .antigravity, tracksTurns: false, modified: record.date, now: now)
        }
    }

    // MARK: - Live Quota Probe

    /// Discovers the local language_server port and CSRF token, and requests quota limits.
    package static func probeQuota() -> AgentLimits? {
        guard let (pid, token) = findLanguageServer() else { return nil }
        guard let port = findListeningPort(for: pid) else { return nil }
        return fetchQuotaSummary(port: port, token: token)
    }

    /// Finds the running `language_server` process and extracts the CSRF token.
    package static func findLanguageServer() -> (pid: Int32, token: String)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-ww", "-eo", "pid,command"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return nil }
        for line in output.components(separatedBy: "\n") {
            guard line.contains("language_server") else { continue }
            let token: String?
            if let tokenRange = line.range(of: "--csrf_token ") {
                let rest = line[tokenRange.upperBound...].trimmingCharacters(in: .whitespaces)
                token = rest.components(separatedBy: " ").first
            } else if let tokenRange = line.range(of: "--extension_server_csrf_token ") {
                let rest = line[tokenRange.upperBound...].trimmingCharacters(in: .whitespaces)
                token = rest.components(separatedBy: " ").first
            } else {
                token = nil
            }
            guard let token, !token.isEmpty else { continue }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if let first = parts.first, let pid = Int32(first) {
                return (pid, token)
            }
        }
        return nil
    }

    /// Runs lsof to find the listening TCP port for the given PID.
    package static func findListeningPort(for pid: Int32) -> Int? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-a", "-p", "\(pid)", "-iTCP", "-sTCP:LISTEN", "-P", "-n"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return nil }
        for line in output.components(separatedBy: "\n") {
            guard line.contains("LISTEN") else { continue }
            let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            for part in parts {
                if let colon = part.lastIndex(of: ":") {
                    let portStr = String(part[part.index(after: colon)...])
                    if let port = Int(portStr) {
                        return port
                    }
                }
            }
        }
        return nil
    }

    /// Makes HTTPS POST to local language server to retrieve quota summary.
    package static func fetchQuotaSummary(port: Int, token: String, timeout: TimeInterval = 5.0) -> AgentLimits? {
        guard let url = URL(string: "https://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue(token, forHTTPHeaderField: "X-Codeium-Csrf-Token")
        request.httpBody = Data("{}".utf8)
        request.timeoutInterval = timeout

        let config = URLSessionConfiguration.ephemeral
        let delegate = InsecureCertificateDelegate()
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var responseData: Data?

        let task = session.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            guard error == nil, let http = response as? HTTPURLResponse, http.statusCode == 200, let data else {
                return
            }
            responseData = data
        }
        task.resume()

        _ = semaphore.wait(timeout: .now() + timeout)
        guard let responseData else { return nil }
        return parseQuotaResponse(responseData, observed: Date())
    }

    /// Parses RetrieveUserQuotaSummary JSON response payload into AgentLimits.
    package static func parseQuotaResponse(_ data: Data, observed: Date) -> AgentLimits? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let groups = json["groups"] as? [[String: Any]] else {
            return nil
        }

        var windows: [AgentLimitWindow] = []
        for group in groups {
            let groupName = (group["displayName"] as? String) ?? (group["name"] as? String)
            guard let buckets = group["buckets"] as? [[String: Any]] else { continue }
            for bucket in buckets {
                guard let bucketId = bucket["bucketId"] as? String ?? bucket["id"] as? String else { continue }
                let remainingFraction = (bucket["remainingFraction"] as? NSNumber)?.doubleValue ?? 1.0
                let resetTimeStr = bucket["resetTime"] as? String ?? ""
                let resetsAt = AgentTimestamp.parse(resetTimeStr)

                let isWeekly = bucketId.lowercased().contains("weekly")
                let kind: AgentLimitWindow.Kind = isWeekly ? .weekly : .session
                let minutes = isWeekly ? 10080 : 300
                let usedPercent = max(0.0, min(100.0, (1.0 - remainingFraction) * 100.0))

                let window = AgentLimitWindow(
                    id: bucketId,
                    kind: kind,
                    minutes: minutes,
                    scope: groupName,
                    usedPercent: usedPercent,
                    resetsAt: resetsAt
                )
                windows.append(window)
            }
        }

        guard !windows.isEmpty else { return nil }
        return AgentLimits(provider: .antigravity, windows: windows, observedAt: observed, source: .account)
    }

    private final class InsecureCertificateDelegate: NSObject, URLSessionDelegate, Sendable {
        func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
               let serverTrust = challenge.protectionSpace.serverTrust {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
        }
    }
}
