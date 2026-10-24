// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//
// Shared by the standalone Nexus Agent app and the Nexus Agent feature of the
// Vitruvian desktop app. Written for Vitruvian and released under MIT by its
// copyright holder on 2026-10-09 (apps/desktop/vitruvian/UPSTREAM.md).

import Combine
import Foundation

// MARK: - Worktree Configuration (.nexus.yaml / orca.yaml)

/// Declarative worktree bootstrap configuration parsed from `.nexus.yaml` or `orca.yaml`.
public struct NexusAgentWorktreeConfig: Equatable, Sendable, Codable {
    public static let supportedFileNames: [String] = [".nexus.yaml", "orca.yaml"]

    public var setup: [String]
    public var env: [String: String]
    public var baseBranch: String?

    public init(setup: [String] = [], env: [String: String] = [:], baseBranch: String? = nil) {
        self.setup = setup
        self.env = env
        self.baseBranch = baseBranch
    }

    private enum Section {
        case none
        case setup
        case env
    }

    /// Pure parser for `.nexus.yaml` / `orca.yaml` configuration text.
    public static func parse(yaml: String) -> NexusAgentWorktreeConfig {
        var config = NexusAgentWorktreeConfig()
        var section: Section = .none

        for rawLine in yaml.components(separatedBy: .newlines) {
            let trimmed = stripInlineComment(rawLine).trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            let leadingSpaces = rawLine.prefix { $0 == " " || $0 == "\t" }.count

            if leadingSpaces == 0 {
                section = .none
                if let (key, value) = splitKeyValue(trimmed) {
                    switch key {
                    case "baseBranch", "base_branch":
                        let cleaned = unquote(value)
                        config.baseBranch = cleaned.isEmpty ? nil : cleaned
                    case "setup":
                        if value.isEmpty {
                            section = .setup
                        } else if value.hasPrefix("[") && value.hasSuffix("]") {
                            let inner = String(value.dropFirst().dropLast())
                            config.setup = inner
                                .components(separatedBy: ",")
                                .map { unquote($0.trimmingCharacters(in: .whitespaces)) }
                                .filter { !$0.isEmpty }
                        }
                    case "env":
                        if value.isEmpty {
                            section = .env
                        }
                    default:
                        break
                    }
                }
                continue
            }

            switch section {
            case .setup:
                if trimmed.hasPrefix("-") {
                    let item = unquote(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
                    if !item.isEmpty {
                        config.setup.append(item)
                    }
                }
            case .env:
                if let (key, value) = splitKeyValue(trimmed), !key.isEmpty {
                    config.env[key] = unquote(value)
                }
            case .none:
                break
            }
        }

        return config
    }

    /// Serializes the configuration back into canonical YAML text.
    public func serialize() -> String {
        var lines: [String] = []
        if let baseBranch, !baseBranch.isEmpty {
            lines.append("baseBranch: \(baseBranch)")
        }
        if !env.isEmpty {
            lines.append("env:")
            for key in env.keys.sorted() {
                let value = env[key] ?? ""
                lines.append("  \(key): \"\(value)\"")
            }
        }
        if !setup.isEmpty {
            lines.append("setup:")
            for command in setup {
                lines.append("  - \"\(command)\"")
            }
        }
        return lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
    }

    private static func splitKeyValue(_ line: String) -> (String, String)? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let key = line[..<colon].trimmingCharacters(in: .whitespaces)
        let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        return (key, value)
    }

    private static func unquote(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return trimmed }
        if (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")) ||
           (trimmed.hasPrefix("'") && trimmed.hasSuffix("'")) {
            return String(trimmed.dropFirst().dropLast())
        }
        return trimmed
    }

    private static func stripInlineComment(_ line: String) -> String {
        var inSingleQuotes = false
        var inDoubleQuotes = false
        var result = ""
        for character in line {
            if character == "'" && !inDoubleQuotes {
                inSingleQuotes.toggle()
            } else if character == "\"" && !inSingleQuotes {
                inDoubleQuotes.toggle()
            } else if character == "#" && !inSingleQuotes && !inDoubleQuotes {
                break
            }
            result.append(character)
        }
        return result
    }
}

// MARK: - Managed Worktree Model & Manager

/// An isolated git worktree managed by Nexus Agent for any CLI provider.
public struct NexusAgentManagedWorktree: Identifiable, Equatable, Sendable, Codable {
    public enum SetupStatus: Equatable, Sendable, Codable {
        case pending
        case running
        case ready
        case failed(String)
    }

    public var id: UUID
    public var taskName: String
    public var branchName: String
    public var worktreePath: String
    public var baseRepositoryPath: String
    public var baseRef: String
    public var providerID: UUID
    public var providerName: String
    public var createdAt: Date
    public var setupStatus: SetupStatus

    public init(
        id: UUID = UUID(),
        taskName: String,
        branchName: String,
        worktreePath: String,
        baseRepositoryPath: String,
        baseRef: String,
        providerID: UUID,
        providerName: String,
        createdAt: Date = Date(),
        setupStatus: SetupStatus = .pending
    ) {
        self.id = id
        self.taskName = taskName
        self.branchName = branchName
        self.worktreePath = worktreePath
        self.baseRepositoryPath = baseRepositoryPath
        self.baseRef = baseRef
        self.providerID = providerID
        self.providerName = providerName
        self.createdAt = createdAt
        self.setupStatus = setupStatus
    }
}

/// Manages engine-owned git worktrees across all CLI providers.
@MainActor
public final class NexusAgentWorktreeManager: ObservableObject {
    public typealias ProgramRunner = @Sendable (String, [String]) async -> String?

    /// A parsed entry from `git worktree list --porcelain`.
    public struct PorcelainWorktreeEntry: Equatable, Sendable {
        public var worktreePath: String
        public var headSHA: String?
        public var branchRef: String?
        public var isBare: Bool

        public init(worktreePath: String, headSHA: String? = nil, branchRef: String? = nil, isBare: Bool = false) {
            self.worktreePath = worktreePath
            self.headSHA = headSHA
            self.branchRef = branchRef
            self.isBare = isBare
        }

        public var shortBranchName: String? {
            guard let branchRef else { return nil }
            let prefix = "refs/heads/"
            return branchRef.hasPrefix(prefix) ? String(branchRef.dropFirst(prefix.count)) : branchRef
        }
    }

    @Published public private(set) var worktrees: [NexusAgentManagedWorktree] = []

    public init(worktrees: [NexusAgentManagedWorktree] = []) {
        self.worktrees = worktrees
    }

    /// Converts an arbitrary task or provider name into a safe git branch/directory slug.
    public nonisolated static func sanitizeSlug(_ raw: String) -> String {
        let lower = raw.lowercased()
        var slug = ""
        var lastWasDash = false
        for scalar in lower.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                slug.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !lastWasDash && !slug.isEmpty {
                slug.append("-")
                lastWasDash = true
            }
        }
        while slug.hasSuffix("-") {
            slug.removeLast()
        }
        return slug.isEmpty ? "task" : slug
    }

    /// Builds `git` arguments for creating a new isolated worktree:
    /// `["-C", baseRepositoryPath, "worktree", "add", "-b", branchName, worktreePath, baseRef]`
    public nonisolated static func createWorktreeArguments(
        baseRepositoryPath: String? = nil,
        branchName: String,
        worktreePath: String,
        baseRef: String
    ) -> [String] {
        var args: [String] = []
        if let baseRepositoryPath, !baseRepositoryPath.isEmpty {
            args.append(contentsOf: ["-C", baseRepositoryPath])
        }
        args.append(contentsOf: ["worktree", "add", "-b", branchName, worktreePath, baseRef])
        return args
    }

    /// Builds `git` arguments for listing worktrees in porcelain format.
    public nonisolated static func listWorktreesArguments(baseRepositoryPath: String? = nil) -> [String] {
        var args: [String] = []
        if let baseRepositoryPath, !baseRepositoryPath.isEmpty {
            args.append(contentsOf: ["-C", baseRepositoryPath])
        }
        args.append(contentsOf: ["worktree", "list", "--porcelain"])
        return args
    }

    /// Builds `git` arguments for removing a managed worktree.
    public nonisolated static func removeWorktreeArguments(
        baseRepositoryPath: String? = nil,
        worktreePath: String,
        force: Bool = false
    ) -> [String] {
        var args: [String] = []
        if let baseRepositoryPath, !baseRepositoryPath.isEmpty {
            args.append(contentsOf: ["-C", baseRepositoryPath])
        }
        args.append("worktree")
        args.append("remove")
        if force {
            args.append("--force")
        }
        args.append(worktreePath)
        return args
    }

    /// Builds `git` arguments for force-deleting a worktree branch.
    public nonisolated static func deleteBranchArguments(
        baseRepositoryPath: String? = nil,
        branchName: String
    ) -> [String] {
        var args: [String] = []
        if let baseRepositoryPath, !baseRepositoryPath.isEmpty {
            args.append(contentsOf: ["-C", baseRepositoryPath])
        }
        args.append(contentsOf: ["branch", "-D", branchName])
        return args
    }

    /// Parses the output of `git worktree list --porcelain`.
    public nonisolated static func parsePorcelainList(_ output: String) -> [PorcelainWorktreeEntry] {
        var entries: [PorcelainWorktreeEntry] = []
        var currentPath: String?
        var currentHead: String?
        var currentBranch: String?
        var currentBare = false

        func flush() {
            if let path = currentPath {
                entries.append(
                    PorcelainWorktreeEntry(
                        worktreePath: path,
                        headSHA: currentHead,
                        branchRef: currentBranch,
                        isBare: currentBare
                    )
                )
            }
            currentPath = nil
            currentHead = nil
            currentBranch = nil
            currentBare = false
        }

        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flush()
                continue
            }
            if line.hasPrefix("worktree ") {
                flush()
                currentPath = String(line.dropFirst("worktree ".count))
            } else if line.hasPrefix("HEAD ") {
                currentHead = String(line.dropFirst("HEAD ".count))
            } else if line.hasPrefix("branch ") {
                currentBranch = String(line.dropFirst("branch ".count))
            } else if line == "bare" {
                currentBare = true
            }
        }
        flush()
        return entries
    }

    /// Creates a managed git worktree for any CLI provider and runs `.nexus.yaml` / `orca.yaml` setup commands.
    @discardableResult
    public func createWorktree(
        taskName: String,
        baseRepositoryPath: String,
        baseRef: String = "HEAD",
        worktreesRoot: String? = nil,
        provider: NexusAgentCLIProvider,
        config: NexusAgentWorktreeConfig? = nil,
        runGit: ProgramRunner,
        runSetup: ProgramRunner? = nil
    ) async -> NexusAgentManagedWorktree {
        let taskSlug = Self.sanitizeSlug(taskName)
        let providerSlug = Self.sanitizeSlug(provider.name)
        let branchName = "nexus/\(providerSlug)/\(taskSlug)"
        let rootDir = worktreesRoot ?? (baseRepositoryPath + "-worktrees")
        let worktreePath = (rootDir as NSString).appendingPathComponent("\(providerSlug)-\(taskSlug)")
        let effectiveBaseRef = config?.baseBranch ?? baseRef

        var managed = NexusAgentManagedWorktree(
            taskName: taskName,
            branchName: branchName,
            worktreePath: worktreePath,
            baseRepositoryPath: baseRepositoryPath,
            baseRef: effectiveBaseRef,
            providerID: provider.id,
            providerName: provider.name,
            setupStatus: .running
        )
        worktrees.append(managed)

        let addArgs = Self.createWorktreeArguments(
            baseRepositoryPath: baseRepositoryPath,
            branchName: branchName,
            worktreePath: worktreePath,
            baseRef: effectiveBaseRef
        )
        guard await runGit("git", addArgs) != nil else {
            managed.setupStatus = .failed("git worktree add failed")
            updateManagedWorktree(managed)
            return managed
        }

        if let config, !config.setup.isEmpty {
            let envPrefix = config.env.keys.sorted().map { key in
                let escaped = (config.env[key] ?? "").replacingOccurrences(of: "'", with: "'\\''")
                return "export \(key)='\(escaped)'; "
            }.joined()
            for command in config.setup {
                let shellArgs = ["-c", "cd \"$1\" && \(envPrefix)\(command)", "sh", worktreePath]
                let output: String?
                if let runSetup {
                    output = await runSetup("/bin/sh", shellArgs)
                } else {
                    output = await runGit("/bin/sh", shellArgs)
                }
                if output == nil {
                    managed.setupStatus = .failed("Setup command failed: \(command)")
                    updateManagedWorktree(managed)
                    return managed
                }
            }
        }

        managed.setupStatus = .ready
        updateManagedWorktree(managed)
        return managed
    }

    /// Removes a managed worktree and optionally deletes its branch.
    @discardableResult
    public func removeWorktree(
        id: UUID,
        force: Bool = false,
        deleteBranch: Bool = false,
        runGit: ProgramRunner
    ) async -> Bool {
        guard let index = worktrees.firstIndex(where: { $0.id == id }) else { return false }
        let entry = worktrees[index]
        let removeArgs = Self.removeWorktreeArguments(
            baseRepositoryPath: entry.baseRepositoryPath,
            worktreePath: entry.worktreePath,
            force: force
        )
        guard await runGit("git", removeArgs) != nil else { return false }
        if deleteBranch {
            let branchArgs = Self.deleteBranchArguments(
                baseRepositoryPath: entry.baseRepositoryPath,
                branchName: entry.branchName
            )
            _ = await runGit("git", branchArgs)
        }
        worktrees.removeAll { $0.id == id }
        return true
    }

    /// Lists all git worktrees reported by `git worktree list --porcelain`.
    public func listPorcelainWorktrees(
        baseRepositoryPath: String,
        runGit: ProgramRunner
    ) async -> [PorcelainWorktreeEntry] {
        let args = Self.listWorktreesArguments(baseRepositoryPath: baseRepositoryPath)
        guard let output = await runGit("git", args) else { return [] }
        return Self.parsePorcelainList(output)
    }

    private func updateManagedWorktree(_ updated: NexusAgentManagedWorktree) {
        if let index = worktrees.firstIndex(where: { $0.id == updated.id }) {
            worktrees[index] = updated
        }
    }
}

// MARK: - Multi-Agent Race Mode

/// A single contender in a Multi-Agent Race Mode session.
public struct NexusAgentRaceContender: Identifiable, Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case queued
        case running
        case completed
        case failed(String)
        case winner
        case discarded
    }

    public var id: UUID
    public var provider: NexusAgentCLIProvider
    public var model: String
    public var worktree: NexusAgentManagedWorktree
    public var status: Status
    public var responseText: String
    public var durationMs: Int?
    public var addedLines: Int
    public var removedLines: Int
    public var filesChanged: Int

    public init(
        id: UUID = UUID(),
        provider: NexusAgentCLIProvider,
        model: String,
        worktree: NexusAgentManagedWorktree,
        status: Status = .queued,
        responseText: String = "",
        durationMs: Int? = nil,
        addedLines: Int = 0,
        removedLines: Int = 0,
        filesChanged: Int = 0
    ) {
        self.id = id
        self.provider = provider
        self.model = model
        self.worktree = worktree
        self.status = status
        self.responseText = responseText
        self.durationMs = durationMs
        self.addedLines = addedLines
        self.removedLines = removedLines
        self.filesChanged = filesChanged
    }
}

/// Coordinates a parallel multi-agent race across isolated worktrees.
@MainActor
public final class NexusAgentRaceSession: ObservableObject {
    @Published public var prompt: String = ""
    @Published public private(set) var contenders: [NexusAgentRaceContender] = []
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var winnerID: UUID?

    private let worktreeManager: NexusAgentWorktreeManager

    public init(worktreeManager: NexusAgentWorktreeManager? = nil) {
        self.worktreeManager = worktreeManager ?? NexusAgentWorktreeManager()
    }

    /// Resets the race session so a new race can be configured.
    public func reset() {
        contenders = []
        winnerID = nil
        isRunning = false
    }

    /// Fans out `prompt` across `specs`, provisioning an isolated worktree per contender.
    public func startRace(
        prompt: String,
        specs: [(provider: NexusAgentCLIProvider, model: String)],
        baseDirectory: String,
        baseRef: String = "HEAD",
        runGit: @Sendable (String, [String]) async -> String?
    ) async {
        self.prompt = prompt
        self.winnerID = nil
        self.contenders = []
        self.isRunning = true

        for (index, spec) in specs.enumerated() {
            let taskName = "race-\(index + 1)-\(spec.model.isEmpty ? "default" : spec.model)"
            let worktree = await worktreeManager.createWorktree(
                taskName: taskName,
                baseRepositoryPath: baseDirectory,
                baseRef: baseRef,
                provider: spec.provider,
                runGit: runGit
            )
            let status: NexusAgentRaceContender.Status = {
                if case .failed(let reason) = worktree.setupStatus {
                    return .failed(reason)
                }
                return .running
            }()
            let contender = NexusAgentRaceContender(
                provider: spec.provider,
                model: spec.model,
                worktree: worktree,
                status: status
            )
            contenders.append(contender)
        }

        refreshRunningState()
    }

    /// Updates a contender's status, response preview, duration, and parsed `git diff --shortstat` metrics.
    public func updateContender(
        id: UUID,
        status: NexusAgentRaceContender.Status,
        responseText: String? = nil,
        durationMs: Int? = nil,
        diffStat: String? = nil
    ) {
        guard let index = contenders.firstIndex(where: { $0.id == id }) else { return }
        contenders[index].status = status
        if let responseText {
            contenders[index].responseText = responseText
        }
        if let durationMs {
            contenders[index].durationMs = durationMs
        }
        if let diffStat {
            let parsed = Self.parseGitShortStat(diffStat)
            contenders[index].filesChanged = parsed.files
            contenders[index].addedLines = parsed.added
            contenders[index].removedLines = parsed.removed
        }
        refreshRunningState()
    }

    /// Selects a winning contender, marks all other contenders `.discarded`, and removes loser worktrees.
    @discardableResult
    public func pickWinner(
        id: UUID,
        runGit: @Sendable (String, [String]) async -> String?
    ) async -> NexusAgentRaceContender? {
        guard contenders.contains(where: { $0.id == id }) else { return nil }
        winnerID = id
        isRunning = false

        for index in contenders.indices {
            if contenders[index].id == id {
                contenders[index].status = .winner
            } else {
                let loserWorktree = contenders[index].worktree
                contenders[index].status = .discarded
                _ = await worktreeManager.removeWorktree(
                    id: loserWorktree.id,
                    force: true,
                    deleteBranch: true,
                    runGit: runGit
                )
            }
        }
        return contenders.first { $0.id == id }
    }

    /// Parses `git diff --shortstat` output such as:
    /// `" 3 files changed, 42 insertions(+), 7 deletions(-)"`
    public nonisolated static func parseGitShortStat(_ statOutput: String) -> (files: Int, added: Int, removed: Int) {
        var files = 0
        var added = 0
        var removed = 0

        for segment in statOutput.components(separatedBy: ",") {
            let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            let tokens = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard let first = tokens.first, let value = Int(first) else { continue }
            if trimmed.contains("file") {
                files = value
            } else if trimmed.contains("insertion") || trimmed.contains("(+) ") || trimmed.hasSuffix("(+)") {
                added = value
            } else if trimmed.contains("deletion") || trimmed.contains("(-) ") || trimmed.hasSuffix("(-)") {
                removed = value
            }
        }

        return (files, added, removed)
    }

    private func refreshRunningState() {
        isRunning = contenders.contains { contender in
            switch contender.status {
            case .queued, .running:
                return true
            case .completed, .failed, .winner, .discarded:
                return false
            }
        }
    }
}

// MARK: - Checkpoint Timeline & AI vs Human Attribution

/// Aggregated AI vs human line-change attribution metrics.
public struct NexusAgentAttributionSummary: Equatable, Sendable, Codable {
    public var aiAddedLines: Int
    public var aiRemovedLines: Int
    public var humanAddedLines: Int
    public var humanRemovedLines: Int

    public init(
        aiAddedLines: Int = 0,
        aiRemovedLines: Int = 0,
        humanAddedLines: Int = 0,
        humanRemovedLines: Int = 0
    ) {
        self.aiAddedLines = max(0, aiAddedLines)
        self.aiRemovedLines = max(0, aiRemovedLines)
        self.humanAddedLines = max(0, humanAddedLines)
        self.humanRemovedLines = max(0, humanRemovedLines)
    }

    public var totalAILines: Int {
        aiAddedLines + aiRemovedLines
    }

    public var totalHumanLines: Int {
        humanAddedLines + humanRemovedLines
    }

    public var totalLines: Int {
        totalAILines + totalHumanLines
    }

    /// Percentage (0...100) of changed lines attributed to AI.
    public var aiAttributionPercentage: Int {
        guard totalLines > 0 else { return 0 }
        return Int((Double(totalAILines) / Double(totalLines) * 100.0).rounded())
    }
}

/// A single turn checkpoint in the conversation timeline.
public struct NexusAgentCheckpointEntry: Identifiable, Equatable, Sendable, Codable {
    public var id: UUID
    public var turnIndex: Int
    public var promptPreview: String
    public var commitOrStashRef: String
    public var timestamp: Date
    public var aiAddedLines: Int
    public var aiRemovedLines: Int
    public var humanAddedLines: Int
    public var humanRemovedLines: Int

    public init(
        id: UUID = UUID(),
        turnIndex: Int,
        promptPreview: String,
        commitOrStashRef: String,
        timestamp: Date = Date(),
        aiAddedLines: Int = 0,
        aiRemovedLines: Int = 0,
        humanAddedLines: Int = 0,
        humanRemovedLines: Int = 0
    ) {
        self.id = id
        self.turnIndex = turnIndex
        self.promptPreview = promptPreview
        self.commitOrStashRef = commitOrStashRef
        self.timestamp = timestamp
        self.aiAddedLines = max(0, aiAddedLines)
        self.aiRemovedLines = max(0, aiRemovedLines)
        self.humanAddedLines = max(0, humanAddedLines)
        self.humanRemovedLines = max(0, humanRemovedLines)
    }

    public var attributionSummary: NexusAgentAttributionSummary {
        NexusAgentAttributionSummary(
            aiAddedLines: aiAddedLines,
            aiRemovedLines: aiRemovedLines,
            humanAddedLines: humanAddedLines,
            humanRemovedLines: humanRemovedLines
        )
    }

    public var aiAttributionPercentage: Int {
        attributionSummary.aiAttributionPercentage
    }
}

/// Multi-turn checkpoint timeline supporting attribution tracking and turn rewind.
@MainActor
public final class NexusAgentCheckpointTimeline: ObservableObject {
    @Published public private(set) var entries: [NexusAgentCheckpointEntry] = []

    public init(entries: [NexusAgentCheckpointEntry] = []) {
        self.entries = entries
    }

    /// Clears all recorded checkpoint entries (e.g. when starting or resuming another conversation).
    public func clear() {
        entries = []
    }

    public var overallAttribution: NexusAgentAttributionSummary {
        entries.reduce(into: NexusAgentAttributionSummary()) { acc, entry in
            acc.aiAddedLines += entry.aiAddedLines
            acc.aiRemovedLines += entry.aiRemovedLines
            acc.humanAddedLines += entry.humanAddedLines
            acc.humanRemovedLines += entry.humanRemovedLines
        }
    }

    /// Records a new checkpoint turn entry on the timeline.
    @discardableResult
    public func recordTurnCheckpoint(
        id: UUID = UUID(),
        turnIndex: Int? = nil,
        promptPreview: String,
        commitOrStashRef: String,
        timestamp: Date = Date(),
        aiAddedLines: Int = 0,
        aiRemovedLines: Int = 0,
        humanAddedLines: Int = 0,
        humanRemovedLines: Int = 0
    ) -> NexusAgentCheckpointEntry {
        let resolvedTurn = turnIndex ?? ((entries.last?.turnIndex ?? 0) + 1)
        let entry = NexusAgentCheckpointEntry(
            id: id,
            turnIndex: resolvedTurn,
            promptPreview: promptPreview,
            commitOrStashRef: commitOrStashRef,
            timestamp: timestamp,
            aiAddedLines: aiAddedLines,
            aiRemovedLines: aiRemovedLines,
            humanAddedLines: humanAddedLines,
            humanRemovedLines: humanRemovedLines
        )
        entries.append(entry)
        return entry
    }

    /// Rewinds the timeline to `entryID`, removing and returning all subsequent turns.
    @discardableResult
    public func rewind(to entryID: UUID) -> [NexusAgentCheckpointEntry] {
        guard let targetIndex = entries.firstIndex(where: { $0.id == entryID }) else {
            return []
        }
        let undone = Array(entries[(targetIndex + 1)...])
        entries.removeSubrange((targetIndex + 1)...)
        return undone
    }

    /// Async rewind overload that also resets git state to the checkpoint's `commitOrStashRef` when a runner is provided.
    @discardableResult
    public func rewind(
        to entryID: UUID,
        repositoryPath: String,
        runGit: @Sendable (String, [String]) async -> String?
    ) async -> [NexusAgentCheckpointEntry] {
        guard let target = entries.first(where: { $0.id == entryID }) else {
            return []
        }
        let undone = rewind(to: entryID)
        _ = await runGit("git", ["-C", repositoryPath, "reset", "--hard", target.commitOrStashRef])
        return undone
    }
}

// MARK: - Multi-Repo Parent Workspace

/// Discovers child git repositories inside a parent directory and coordinates multi-repo CLI flags and checkpoints.
public struct NexusAgentMultiRepoWorkspace: Equatable, Sendable {
    public var parentPath: String
    public var childRepositories: [String]

    public init(parentPath: String, childRepositories: [String] = []) {
        self.parentPath = parentPath
        self.childRepositories = childRepositories
    }

    public var isMultiRepoActive: Bool {
        !childRepositories.isEmpty
    }

    /// Discovers immediate child directories inside `parentPath` that are git repositories, sorted alphabetically.
    public static func discoverRepositories(
        in parentPath: String,
        listDirectory: (String) -> [String],
        isGitRepo: (String) -> Bool
    ) -> [String] {
        let normalizedParent = parentPath.hasSuffix("/") && parentPath.count > 1
            ? String(parentPath.dropLast())
            : parentPath
        let children = listDirectory(normalizedParent)
        var discovered: [String] = []

        for child in children where !child.isEmpty && !child.hasPrefix(".") {
            let fullPath: String
            if child.hasPrefix("/") {
                fullPath = child
            } else {
                fullPath = (normalizedParent as NSString).appendingPathComponent(child)
            }
            if isGitRepo(fullPath) {
                discovered.append(fullPath)
            }
        }

        return discovered.sorted()
    }

    /// Generates additional directory CLI arguments (such as `--add-dir <repo>`) for providers that support them.
    public static func additionalDirectoryArguments(
        for route: NexusAgentProviderRoute,
        childRepos: [String]
    ) -> [String] {
        guard !childRepos.isEmpty else { return [] }
        switch route {
        case .claude, .ollama, .antigravity:
            return childRepos.flatMap { ["--add-dir", $0] }
        case .opencode, .custom:
            return []
        }
    }

    /// Records `HEAD` commit SHAs across all discovered child repositories for a synchronized multi-repo checkpoint.
    public static func captureMultiRepoCheckpoint(
        childRepos: [String],
        runGit: @Sendable (String, [String]) async -> String?
    ) async -> [String: String] {
        var refs: [String: String] = [:]
        for repo in childRepos {
            if let sha = await runGit("git", ["-C", repo, "rev-parse", "HEAD"])?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !sha.isEmpty {
                refs[repo] = sha
            }
        }
        return refs
    }
}
