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

import CryptoKit
import Foundation

// The ACP registry: the public list of agents that speak ACP, and how to
// install one. Follows T3 Code's
// `packages/provider-acp-registry/src/server/AcpRegistrySupport.ts`
// (commit d6e5f2e0): the same index URL, limits, timeouts, entry checks,
// install folders and package-manager commands. Where this differs, the
// comment says why.
//
// What it promises:
// * nothing is installed unless `ACPRegistryInstaller.install` is called,
//   which only a user's "add agent" does: reading the list, looking up an
//   install, or launching one never installs;
// * every install is of one exact version, in its own folder under
//   `<state>/agents/<id>/<version>/`;
// * a download whose entry gives a SHA-256 must match it;
// * nothing an archive holds lands outside its folder, and the command it
//   names must be a regular executable inside it.

/// Why a registry operation failed. The cases match T3 Code's
/// `AcpRegistryOperationErrorReason`.
public struct ACPRegistryError: LocalizedError, Equatable, Sendable, CustomStringConvertible {
    public enum Reason: String, Equatable, Sendable {
        case registryUnavailable = "registry_unavailable"
        case agentNotFound = "agent_not_found"
        case unsupportedPlatform = "unsupported_platform"
        /// The install needs `npm` or `uv` and it is not on this Mac.
        case runnerUnavailable = "runner_unavailable"
        case downloadFailed = "download_failed"
        case checksumMismatch = "checksum_mismatch"
        case archiveInvalid = "archive_invalid"
        case installFailed = "install_failed"
    }

    public var reason: Reason
    public var detail: String

    public init(_ reason: Reason, _ detail: String) {
        self.reason = reason
        self.detail = detail
    }

    public var description: String { detail }
    public var errorDescription: String? { detail }
}

public enum ACPRegistry {
    public static let indexURL = URL(string: "https://cdn.agentclientprotocol.com/registry/v1/latest/registry.json")!

    // T3 Code's limits and timeouts.
    public static let maxIndexBytes = 1024 * 1024
    public static let maxAgents = 512
    public static let maxArchiveBytes = 1024 * 1024 * 1024
    public static let maxCommandOutputBytes = 1024 * 1024
    public static let maxArchiveListingBytes = 64 * 1024 * 1024
    public static let maxPackageManifestBytes = 1024 * 1024
    public static let indexTimeout: TimeInterval = 30
    public static let archiveTimeout: TimeInterval = 20 * 60
    public static let packageInstallTimeout: TimeInterval = 20 * 60
    public static let packageQueryTimeout: TimeInterval = 30

    // MARK: Entries

    public struct Index: Equatable, Sendable {
        public var version: String
        public var agents: [Agent]
        /// How many entries were dropped because they failed a check.
        public var discarded: Int
    }

    public struct Agent: Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var version: String
        public var description: String
        public var authors: [String]
        public var license: String?
        public var website: String?
        public var repository: String?
        public var icon: String?
        public var distribution: Distribution
    }

    public struct Distribution: Equatable, Sendable {
        /// Keyed by platform target, for example `darwin-aarch64`.
        public var binary: [String: BinaryTarget]
        public var npx: Package?
        public var uvx: Package?
    }

    public struct BinaryTarget: Equatable, Sendable {
        public var archive: String
        public var cmd: String
        public var sha256: String?
        public var args: [String]
        public var env: [String: String]
    }

    public struct Package: Equatable, Sendable {
        /// An exact spec: `name@1.2.3`, or for uv also `name==1.2.3`.
        public var package: String
        public var args: [String]
        public var env: [String: String]
    }

    public enum DistributionKind: String, Codable, Equatable, Sendable, CaseIterable {
        case binary
        case npx
        case uvx

        /// The program the install needs on the Mac, if any.
        public var runner: String? {
            switch self {
            case .binary: return nil
            case .npx: return "npm"
            case .uvx: return "uv"
            }
        }
    }

    /// Which distribution to use. `auto` takes a binary first, then npx,
    /// then uvx, as T3 Code does.
    public enum Preference: String, Codable, Equatable, Sendable {
        case auto
        case binary
        case npx
        case uvx
    }

    // MARK: Checks (T3 Code's schema, as plain functions)

    static func isAgentID(_ value: String) -> Bool {
        value.count <= 128 && matches(value, "^[a-z0-9][a-z0-9._-]*$")
    }

    /// Versions become folder names, so `.` and `..` must not pass.
    static func isVersion(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == value && !value.isEmpty && value.count <= 128
            && matches(value, "^[A-Za-z0-9][A-Za-z0-9._+-]*$")
    }

    private static let exactRunnerVersion = "v?[0-9]+\\.[0-9]+\\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\\+[0-9A-Za-z.-]+)?"

    static func isExactNpxPackage(_ value: String) -> Bool {
        value.count <= 256
            && matches(value, "^(?:@[^/@\\s]+/[^@\\s]+|[a-z0-9][a-z0-9._-]*)@\(exactRunnerVersion)$", caseInsensitive: true)
    }

    static func isExactUvxPackage(_ value: String) -> Bool {
        value.count <= 256
            && matches(value, "^[a-z0-9][a-z0-9._-]*(?:@|==)\(exactRunnerVersion)$", caseInsensitive: true)
    }

    /// HTTPS, absolute, and with no user or password in it.
    static func isHTTPSURL(_ value: String) -> Bool {
        guard value.count <= 2048, let url = URLComponents(string: value) else { return false }
        return url.scheme?.lowercased() == "https" && url.host?.isEmpty == false
            && url.user == nil && url.password == nil
    }

    static func isPackageCommandName(_ value: String) -> Bool {
        value.count <= 128 && matches(value, "^[a-z0-9][a-z0-9._-]*$", caseInsensitive: true)
    }

    private static func matches(_ value: String, _ pattern: String, caseInsensitive: Bool = false) -> Bool {
        var options: String.CompareOptions = [.regularExpression]
        if caseInsensitive { options.insert(.caseInsensitive) }
        return value.range(of: pattern, options: options) != nil
    }

    // MARK: Parsing

    /// Reads the registry index. The envelope must be valid; an entry that
    /// fails a check is dropped and counted, as in T3 Code.
    public static func parseIndex(_ data: Data) throws -> Index {
        guard data.count <= maxIndexBytes else {
            throw ACPRegistryError(.registryUnavailable, "The ACP registry index is larger than \(maxIndexBytes) bytes.")
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw ACPRegistryError(.registryUnavailable, "The ACP registry index is not valid UTF-8.")
        }
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            throw ACPRegistryError(.registryUnavailable, "The ACP registry returned invalid JSON.")
        }
        guard let version = object["version"] as? String, isVersion(version),
              let entries = object["agents"] as? [Any], entries.count <= maxAgents else {
            throw ACPRegistryError(.registryUnavailable, "The ACP registry returned an invalid index.")
        }
        let agents = entries.compactMap(parseAgent)
        return Index(version: version, agents: agents, discarded: entries.count - agents.count)
    }

    static func parseAgent(_ value: Any) -> Agent? {
        guard let object = value as? [String: Any],
              let id = object["id"] as? String, isAgentID(id),
              let rawName = object["name"] as? String,
              let version = object["version"] as? String, isVersion(version),
              let description = object["description"] as? String, description.count <= 1024,
              let rawDistribution = object["distribution"] as? [String: Any] else { return nil }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name == rawName, name.count <= 160 else { return nil }

        var authors: [String] = []
        if let raw = object["authors"] {
            guard let list = raw as? [String], list.count <= 16, list.allSatisfy({ $0.count <= 256 }) else { return nil }
            authors = list
        }
        var license: String?
        if let raw = object["license"] {
            guard let text = raw as? String, text.count <= 128 else { return nil }
            license = text
        }
        func optionalURL(_ key: String) -> (ok: Bool, value: String?) {
            guard let raw = object[key] else { return (true, nil) }
            guard let text = raw as? String, isHTTPSURL(text) else { return (false, nil) }
            return (true, text)
        }
        let website = optionalURL("website"), repository = optionalURL("repository"), icon = optionalURL("icon")
        guard website.ok, repository.ok, icon.ok else { return nil }

        var binary: [String: BinaryTarget] = [:]
        if let raw = rawDistribution["binary"] {
            guard let targets = raw as? [String: Any] else { return nil }
            for (platform, value) in targets {
                guard let target = parseBinaryTarget(value) else { return nil }
                binary[platform] = target
            }
        }
        var npx: Package?
        if let raw = rawDistribution["npx"] {
            guard let package = parsePackage(raw, isExact: isExactNpxPackage) else { return nil }
            npx = package
        }
        var uvx: Package?
        if let raw = rawDistribution["uvx"] {
            guard let package = parsePackage(raw, isExact: isExactUvxPackage) else { return nil }
            uvx = package
        }
        return Agent(id: id, name: name, version: version, description: description, authors: authors,
                     license: license, website: website.value, repository: repository.value, icon: icon.value,
                     distribution: Distribution(binary: binary, npx: npx, uvx: uvx))
    }

    private static func parseArguments(_ value: Any?) -> [String]? {
        guard let value else { return [] }
        guard let list = value as? [String], list.count <= 64, list.allSatisfy({ $0.count <= 1024 }) else { return nil }
        return list
    }

    private static func parseEnvironment(_ value: Any?) -> [String: String]? {
        guard let value else { return [:] }
        guard let map = value as? [String: String],
              map.allSatisfy({ $0.key.count <= 256 && $0.value.count <= 1024 }) else { return nil }
        return map
    }

    private static func parseBinaryTarget(_ value: Any) -> BinaryTarget? {
        guard let object = value as? [String: Any],
              let archive = object["archive"] as? String, isHTTPSURL(archive),
              let cmd = object["cmd"] as? String, cmd.count <= 1024,
              let args = parseArguments(object["args"]),
              let env = parseEnvironment(object["env"]) else { return nil }
        var sha: String?
        if let raw = object["sha256"] {
            guard let text = raw as? String, matches(text, "^[a-f0-9]{64}$", caseInsensitive: true) else { return nil }
            sha = text.lowercased()
        }
        return BinaryTarget(archive: archive, cmd: cmd, sha256: sha, args: args, env: env)
    }

    private static func parsePackage(_ value: Any, isExact: (String) -> Bool) -> Package? {
        guard let object = value as? [String: Any],
              let spec = object["package"] as? String, isExact(spec),
              let args = parseArguments(object["args"]),
              let env = parseEnvironment(object["env"]) else { return nil }
        return Package(package: spec, args: args, env: env)
    }

    // MARK: Platform and distribution

    /// This Mac's registry target, from the slice that is running (a
    /// universal app under Rosetta is `darwin-x86_64`).
    public static func platformTarget(architecture: String = HelperArchitecture.current) -> String? {
        switch architecture {
        case "arm64": return "darwin-aarch64"
        case "x86_64": return "darwin-x86_64"
        default: return nil
        }
    }

    public struct ResolvedDistribution: Equatable, Sendable {
        public var kind: DistributionKind
        public var args: [String]
        public var env: [String: String]
        public var binary: BinaryTarget?
        public var platformTarget: String?
        public var packageSpec: String?
    }

    /// The distribution to install for `preference` on `platformTarget`,
    /// or nil when the agent offers none that fits.
    public static func resolveDistribution(_ agent: Agent, preference: Preference = .auto,
                                           platformTarget: String? = ACPRegistry.platformTarget()) -> ResolvedDistribution? {
        let order: [DistributionKind] = switch preference {
        case .auto: [.binary, .npx, .uvx]
        case .binary: [.binary]
        case .npx: [.npx]
        case .uvx: [.uvx]
        }
        for kind in order {
            switch kind {
            case .binary:
                if let platformTarget, let target = agent.distribution.binary[platformTarget] {
                    return ResolvedDistribution(kind: .binary, args: target.args, env: target.env,
                                                binary: target, platformTarget: platformTarget)
                }
            case .npx:
                if let package = agent.distribution.npx {
                    return ResolvedDistribution(kind: .npx, args: package.args, env: package.env, packageSpec: package.package)
                }
            case .uvx:
                if let package = agent.distribution.uvx {
                    return ResolvedDistribution(kind: .uvx, args: package.args, env: package.env, packageSpec: package.package)
                }
            }
        }
        return nil
    }

    // MARK: Paths

    /// A command path from an entry, split into segments, or nil when it is
    /// absolute or steps out with `..`.
    public static func commandSegments(_ command: String) -> [String]? {
        var normalized = command.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\\", with: "/")
        if normalized.hasPrefix("./") { normalized.removeFirst(2) }
        let segments = normalized.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if segments.isEmpty || normalized.hasPrefix("/") || matches(normalized, "^[a-zA-Z]:")
            || segments.contains(where: { $0 == "." || $0 == ".." }) {
            return nil
        }
        return segments
    }

    /// True when every name an archive lists stays inside it.
    public static func archiveEntriesAreSafe(_ listing: String) -> Bool {
        listing.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .allSatisfy { $0 == "./" || commandSegments($0) != nil }
    }

    public enum ArchiveKind: Equatable, Sendable {
        case raw, tarGz, tarBz2, zip

        var fileName: String {
            switch self {
            case .raw: return "agent.bin"
            case .tarGz: return "agent.tar.gz"
            case .tarBz2: return "agent.tar.bz2"
            case .zip: return "agent.zip"
            }
        }
    }

    public static func archiveKind(_ url: String) -> ArchiveKind {
        let path = (URLComponents(string: url)?.path ?? url).lowercased()
        if path.hasSuffix(".tar.gz") || path.hasSuffix(".tgz") { return .tarGz }
        if path.hasSuffix(".tar.bz2") || path.hasSuffix(".tbz2") { return .tarBz2 }
        if path.hasSuffix(".zip") { return .zip }
        return .raw
    }

    /// A version as a folder name, as T3 Code's `encodeURIComponent` gives
    /// it for the characters a version may hold (`+` becomes `%2B`).
    public static func versionFolderName(_ version: String) -> String {
        var allowed = CharacterSet.alphanumerics.intersection(.init(charactersIn: Unicode.Scalar(0)...Unicode.Scalar(127)))
        allowed.insert(charactersIn: "-_.!~*'()")
        return version.addingPercentEncoding(withAllowedCharacters: allowed) ?? version
    }

    /// The npm command a package's manifest provides for `agent`, as T3
    /// Code's `npmCommandName` picks it.
    static func npmCommandName(agentID: String, packageName: String, bin: Any) -> String? {
        let baseName = packageName.split(separator: "/").last.map(String.init) ?? packageName
        if bin is String { return baseName }
        guard let map = bin as? [String: String] else { return nil }
        let entries = map.filter { isPackageCommandName($0.key) }.sorted { $0.key < $1.key }
        if entries.count == 1 { return entries[0].key }
        if map[baseName] != nil { return baseName }
        if map[agentID] != nil { return agentID }
        return Set(entries.map(\.value)).count == 1 ? entries.first?.key : nil
    }

    /// The uv command names to look for, as T3 Code's `packageCommandCandidates`.
    static func packageCommandCandidates(agentID: String, packageName: String) -> [String] {
        let unscoped = packageName.split(separator: "/").last.map(String.init) ?? packageName
        var seen = Set<String>()
        let trimmed = unscoped.hasSuffix("-acp") ? String(unscoped.dropLast(4)) : unscoped
        return [agentID, unscoped, trimmed].filter { isPackageCommandName($0) && seen.insert($0).inserted }
    }

    static func splitPackageSpec(_ spec: String, kind: DistributionKind) -> (name: String, version: String) {
        if kind == .uvx, let range = spec.range(of: "==", options: .backwards) {
            return (String(spec[..<range.lowerBound]), stripV(String(spec[range.upperBound...])))
        }
        guard let at = spec.lastIndex(of: "@"), at != spec.startIndex else { return (spec, "") }
        return (String(spec[..<at]), stripV(String(spec[spec.index(after: at)...])))
    }

    private static func stripV(_ version: String) -> String {
        version.first == "v" || version.first == "V" ? String(version.dropFirst()) : version
    }
}

// MARK: - The installed agent

/// One installed agent: what the app saves and launches. Written as
/// `receipt.json` in the agent's version folder.
public struct ACPRegistryInstall: Codable, Equatable, Sendable {
    public var agentID: String
    public var name: String
    public var version: String
    public var distribution: ACPRegistry.DistributionKind
    /// Absolute path of the agent's program, inside its version folder.
    public var executablePath: String
    public var arguments: [String]
    public var environment: [String: String]
    /// Put in front of PATH when it runs: npm and uv put the command there.
    public var binDirectory: String?
    public var packageSpec: String?
}

// MARK: - What the installer needs from the Mac

/// The installer's view of the network, programs and lookups, so tests can
/// stand in for them. `live` is the real Mac.
public struct ACPRegistryHost: Sendable {
    public struct CommandResult: Equatable, Sendable {
        public var status: Int32
        public var stdout: String
        public var stderr: String
        public var stdoutTruncated: Bool

        public init(status: Int32, stdout: String, stderr: String = "", stdoutTruncated: Bool = false) {
            self.status = status
            self.stdout = stdout
            self.stderr = stderr
            self.stdoutTruncated = stdoutTruncated
        }
    }

    /// GETs `url` over HTTPS within `timeout`, refusing more than `maxBytes`.
    public var fetch: @Sendable (_ url: URL, _ maxBytes: Int, _ timeout: TimeInterval) async throws -> Data
    /// Saves `url` to `destination` within `timeout`, refusing more than
    /// `maxBytes`, and gives back the SHA-256 of what it saved, in hex.
    public var download: @Sendable (_ url: URL, _ destination: String, _ maxBytes: Int, _ timeout: TimeInterval) async throws -> String
    /// Runs a program with exactly these arguments (no shell) and this
    /// environment, killing it after `timeout`.
    public var run: @Sendable (_ executable: String, _ arguments: [String], _ environment: [String: String],
                               _ timeout: TimeInterval, _ maxStdoutBytes: Int) async throws -> CommandResult
    /// Where a program the install needs (`npm`, `uv`) is, or nil.
    public var findProgram: @Sendable (_ name: String, _ environment: [String: String]) -> String?

    public init(
        fetch: @escaping @Sendable (URL, Int, TimeInterval) async throws -> Data,
        download: @escaping @Sendable (URL, String, Int, TimeInterval) async throws -> String,
        run: @escaping @Sendable (String, [String], [String: String], TimeInterval, Int) async throws -> CommandResult,
        findProgram: @escaping @Sendable (String, [String: String]) -> String?
    ) {
        self.fetch = fetch
        self.download = download
        self.run = run
        self.findProgram = findProgram
    }
}

extension ACPRegistryHost {
    /// The real Mac: URLSession for the network, `Process` for programs, and
    /// the same folders the app looks for agents in, then PATH.
    public static func live(home: String = NSHomeDirectory()) -> ACPRegistryHost {
        ACPRegistryHost(
            fetch: { url, maxBytes, timeout in
                try await ACPRegistryLive.get(url: url, maxBytes: maxBytes, timeout: timeout, destination: nil).data
            },
            download: { url, destination, maxBytes, timeout in
                try await ACPRegistryLive.get(url: url, maxBytes: maxBytes, timeout: timeout, destination: destination).sha256
            },
            run: { executable, arguments, environment, timeout, maxStdout in
                try await ACPRegistryLive.run(executable, arguments, environment, timeout, maxStdout)
            },
            findProgram: { name, environment in
                let fileManager = FileManager.default
                return VitruvianCodeSupport.locateChatProgram(
                    named: name, environment: environment, home: home,
                    isExecutable: { fileManager.isExecutableFile(atPath: $0) },
                    fileExists: { fileManager.fileExists(atPath: $0) })
            }
        )
    }
}

enum ACPRegistryLive {
    /// Streams a GET, hashing as it goes so a large archive is never held
    /// in memory, and stops at `maxBytes`. Redirects must stay on HTTPS.
    static func get(url: URL, maxBytes: Int, timeout: TimeInterval,
                    destination: String?) async throws -> (data: Data, sha256: String) {
        guard url.scheme?.lowercased() == "https" else {
            throw ACPRegistryError(.downloadFailed, "Only HTTPS downloads are allowed.")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = min(timeout, 60)
        configuration.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: configuration, delegate: HTTPSOnlyRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let (bytes, response) = try await session.bytes(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              http.url?.scheme?.lowercased() == "https" else {
            throw ACPRegistryError(.downloadFailed, "The server answered \((response as? HTTPURLResponse)?.statusCode ?? 0) for \(url.absoluteString).")
        }
        if http.expectedContentLength > Int64(maxBytes) {
            throw ACPRegistryError(.archiveInvalid, "The download is larger than \(maxBytes) bytes.")
        }

        var handle: FileHandle?
        if let destination {
            guard FileManager.default.createFile(atPath: destination, contents: nil, attributes: [.posixPermissions: 0o600]),
                  let opened = FileHandle(forWritingAtPath: destination) else {
                throw ACPRegistryError(.downloadFailed, "Could not save the download.")
            }
            handle = opened
        }
        defer { try? handle?.close() }

        var hasher = SHA256()
        var kept = Data()
        var buffer = Data()
        buffer.reserveCapacity(1 << 16)
        var total = 0
        func flush() throws {
            guard !buffer.isEmpty else { return }
            hasher.update(data: buffer)
            if let handle { try handle.write(contentsOf: buffer) } else { kept.append(buffer) }
            buffer.removeAll(keepingCapacity: true)
        }
        for try await byte in bytes {
            total += 1
            if total > maxBytes {
                throw ACPRegistryError(.archiveInvalid, "The download is larger than \(maxBytes) bytes.")
            }
            buffer.append(byte)
            if buffer.count >= 1 << 16 { try flush() }
        }
        try flush()
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return (kept, digest)
    }

    private final class HTTPSOnlyRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? {
            request.url?.scheme?.lowercased() == "https" ? request : nil
        }
    }

    static func run(_ executable: String, _ arguments: [String], _ environment: [String: String],
                    _ timeout: TimeInterval, _ maxStdout: Int) async throws -> ACPRegistryHost.CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.environment = environment
            process.standardInput = FileHandle.nullDevice
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err

            let collected = OutputBox(maxStdout: maxStdout)
            out.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if !chunk.isEmpty { collected.appendStdout(chunk) }
            }
            err.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if !chunk.isEmpty { collected.appendStderr(chunk) }
            }
            process.terminationHandler = { finished in
                out.fileHandleForReading.readabilityHandler = nil
                err.fileHandleForReading.readabilityHandler = nil
                collected.appendStdout(out.fileHandleForReading.readDataToEndOfFile())
                collected.appendStderr(err.fileHandleForReading.readDataToEndOfFile())
                ChildProcesses.shared.remove(finished.processIdentifier)
                let result = collected.result(status: finished.terminationStatus)
                if collected.timedOut {
                    continuation.resume(throwing: ACPRegistryError(.installFailed, "'\((executable as NSString).lastPathComponent)' did not finish within \(Int(timeout)) seconds."))
                } else {
                    continuation.resume(returning: result)
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: ACPRegistryError(.installFailed, "Could not run '\((executable as NSString).lastPathComponent)': \(error.localizedDescription)"))
                return
            }
            ChildProcesses.shared.add(process.processIdentifier, leadsGroup: false)
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning {
                    collected.timedOut = true
                    process.terminate()
                    DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                    }
                }
            }
        }
    }

    private final class OutputBox: @unchecked Sendable {
        private let lock = NSLock()
        private let maxStdout: Int
        private var stdout = Data()
        private var stderr = Data()
        private var truncated = false
        var timedOut = false

        init(maxStdout: Int) { self.maxStdout = maxStdout }

        func appendStdout(_ data: Data) {
            lock.lock(); defer { lock.unlock() }
            let room = maxStdout - stdout.count
            if data.count > room { truncated = true }
            if room > 0 { stdout.append(data.prefix(room)) }
        }

        func appendStderr(_ data: Data) {
            lock.lock(); defer { lock.unlock() }
            let room = ACPRegistry.maxCommandOutputBytes - stderr.count
            if room > 0 { stderr.append(data.prefix(room)) }
        }

        func result(status: Int32) -> ACPRegistryHost.CommandResult {
            lock.lock(); defer { lock.unlock() }
            return .init(status: status, stdout: String(decoding: stdout, as: UTF8.self),
                         stderr: String(decoding: stderr, as: UTF8.self), stdoutTruncated: truncated)
        }
    }
}

// MARK: - The installer

/// Installs registry agents into `<state>/agents/` and reads them back.
/// One install per agent runs at a time in this process; a lock file keeps
/// a second process (the app and the tool) from installing the same copy.
public actor ACPRegistryInstaller {
    public nonisolated let agentsDirectory: String
    public nonisolated let cacheDirectory: String
    private let host: ACPRegistryHost
    private let platformTarget: String?
    private let environment: [String: String]
    private let indexURL: URL
    private var busy: Set<String> = []

    static let lockRetries = 300
    static let lockRetryDelay: UInt64 = 100_000_000
    static let lockStaleAfter: TimeInterval = 5 * 60

    /// - Parameter environment: what npm and uv run with: the app's own,
    ///   with the agent install folders in front of PATH.
    public init(stateDirectory: String, host: ACPRegistryHost, environment: [String: String],
                platformTarget: String? = ACPRegistry.platformTarget(), indexURL: URL = ACPRegistry.indexURL) {
        self.agentsDirectory = (stateDirectory as NSString).appendingPathComponent("agents")
        self.cacheDirectory = (stateDirectory as NSString).appendingPathComponent("acp-registry")
        self.host = host
        self.environment = environment
        self.platformTarget = platformTarget
        self.indexURL = indexURL
    }

    private var indexCachePath: String { (cacheDirectory as NSString).appendingPathComponent("registry.json") }

    /// The registry index: fetched now, and saved; if the fetch fails, the
    /// last saved copy, as T3 Code falls back to its cache.
    public func loadIndex() async throws -> ACPRegistry.Index {
        do {
            guard indexURL.scheme?.lowercased() == "https" else {
                throw ACPRegistryError(.registryUnavailable, "The ACP registry index URL must use HTTPS.")
            }
            let data = try await host.fetch(indexURL, ACPRegistry.maxIndexBytes + 1, ACPRegistry.indexTimeout)
            let index = try ACPRegistry.parseIndex(data)
            saveIndexCache(data)
            return index
        } catch {
            if let cached = FileManager.default.contents(atPath: indexCachePath),
               let index = try? ACPRegistry.parseIndex(cached) {
                return index
            }
            if let registryError = error as? ACPRegistryError { throw registryError }
            throw ACPRegistryError(.registryUnavailable, "Could not fetch the ACP registry: \(error.localizedDescription)")
        }
    }

    private func saveIndexCache(_ data: Data) {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(atPath: cacheDirectory, withIntermediateDirectories: true)
        let temporary = indexCachePath + ".\(getpid())-\(UUID().uuidString).tmp"
        guard fileManager.createFile(atPath: temporary, contents: data) else { return }
        if rename(temporary, indexCachePath) != 0 { try? fileManager.removeItem(atPath: temporary) }
    }

    /// The runner `agent` would need that this Mac lacks (`npm` or `uv`), so
    /// Settings can flag it before the user adds it; nil when none is missing.
    public nonisolated func missingRunner(for agent: ACPRegistry.Agent, preference: ACPRegistry.Preference = .auto) -> String? {
        guard let resolved = ACPRegistry.resolveDistribution(agent, preference: preference, platformTarget: platformTarget),
              let runner = resolved.kind.runner else { return nil }
        return host.findProgram(runner, environment) == nil ? runner : nil
    }

    // MARK: Paths

    private func versionRoot(agentID: String, version: String) -> String {
        ((agentsDirectory as NSString).appendingPathComponent(agentID) as NSString)
            .appendingPathComponent(ACPRegistry.versionFolderName(version))
    }

    private func receiptPath(agentID: String, version: String) -> String {
        (versionRoot(agentID: agentID, version: version) as NSString).appendingPathComponent("receipt.json")
    }

    // MARK: Reading installs

    /// The installed copy of `agentID` at `version`, if one is there and
    /// still sound. Never installs.
    public func installed(agentID: String, version: String) -> ACPRegistryInstall? {
        Self.installedReceipt(agentsDirectory: agentsDirectory, agentID: agentID, version: version)
    }

    /// The same lookup without the installer, for a chat about to start
    /// (`ACPRegistryConnection`) and for Settings. Never installs.
    public static func installedReceipt(stateDirectory: String, agentID: String, version: String) -> ACPRegistryInstall? {
        installedReceipt(agentsDirectory: (stateDirectory as NSString).appendingPathComponent("agents"),
                         agentID: agentID, version: version)
    }

    static func installedReceipt(agentsDirectory: String, agentID: String, version: String) -> ACPRegistryInstall? {
        guard ACPRegistry.isAgentID(agentID), ACPRegistry.isVersion(version) else { return nil }
        let root = ((agentsDirectory as NSString).appendingPathComponent(agentID) as NSString)
            .appendingPathComponent(ACPRegistry.versionFolderName(version))
        guard let data = FileManager.default.contents(atPath: (root as NSString).appendingPathComponent("receipt.json")),
              let receipt = try? JSONDecoder().decode(ACPRegistryInstall.self, from: data),
              receipt.agentID == agentID, receipt.version == version,
              (try? Self.executableInside(root: root, path: receipt.executablePath)) != nil else { return nil }
        return receipt
    }

    /// Every version of every agent installed, by agent id then version folder.
    public func allInstalled() -> [ACPRegistryInstall] {
        let fileManager = FileManager.default
        let agentIDs = (try? fileManager.contentsOfDirectory(atPath: agentsDirectory)) ?? []
        return agentIDs.sorted().flatMap { agentID -> [ACPRegistryInstall] in
            let agentRoot = (agentsDirectory as NSString).appendingPathComponent(agentID)
            let folders = (try? fileManager.contentsOfDirectory(atPath: agentRoot)) ?? []
            return folders.sorted().compactMap { folder in
                guard let version = folder.removingPercentEncoding else { return nil }
                return installed(agentID: agentID, version: version)
            }
        }
    }

    // MARK: Installing

    /// Installs `agent` at the version the registry lists for it. Only a
    /// user's "add agent" calls this. An install already in place is reused.
    public func install(_ agent: ACPRegistry.Agent, preference: ACPRegistry.Preference = .auto) async throws -> ACPRegistryInstall {
        guard ACPRegistry.isAgentID(agent.id), ACPRegistry.isVersion(agent.version) else {
            throw ACPRegistryError(.installFailed, "The registry entry has an invalid id or version.")
        }
        guard let resolved = ACPRegistry.resolveDistribution(agent, preference: preference, platformTarget: platformTarget) else {
            if platformTarget == nil {
                throw ACPRegistryError(.unsupportedPlatform, "The ACP registry has no build for this Mac.")
            }
            throw ACPRegistryError(.unsupportedPlatform, "\(agent.name) has no install for this Mac.")
        }
        if let existing = installed(agentID: agent.id, version: agent.version), existing.distribution == resolved.kind {
            return existing
        }
        while busy.contains(agent.id) {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        busy.insert(agent.id)
        defer { busy.remove(agent.id) }

        let root = versionRoot(agentID: agent.id, version: agent.version)
        try makeDirectory((root as NSString).deletingLastPathComponent)
        let lockPath = root + ".lock"
        try await acquireLock(lockPath)
        defer { unlink(lockPath) }
        if let existing = installed(agentID: agent.id, version: agent.version), existing.distribution == resolved.kind {
            return existing
        }

        let receipt: ACPRegistryInstall
        switch resolved.kind {
        case .binary:
            receipt = try await installBinary(agent, resolved, root: root)
        case .npx, .uvx:
            receipt = try await installPackage(agent, resolved, root: root)
        }
        try writeReceipt(receipt)
        return receipt
    }

    private func installBinary(_ agent: ACPRegistry.Agent, _ resolved: ACPRegistry.ResolvedDistribution,
                               root: String) async throws -> ACPRegistryInstall {
        guard let target = resolved.binary, let platformTarget = resolved.platformTarget else {
            throw ACPRegistryError(.unsupportedPlatform, "\(agent.name) has no build for this Mac.")
        }
        guard let segments = ACPRegistry.commandSegments(target.cmd) else {
            throw ACPRegistryError(.archiveInvalid, "\(agent.name) names an unsafe command path '\(target.cmd)'.")
        }
        guard let archiveURL = URL(string: target.archive), ACPRegistry.isHTTPSURL(target.archive) else {
            throw ACPRegistryError(.downloadFailed, "\(agent.name) has an invalid download address.")
        }
        let installRoot = (root as NSString).appendingPathComponent(platformTarget)
        let finalExecutable = segments.reduce(installRoot) { ($0 as NSString).appendingPathComponent($1) }

        try makeDirectory(root)
        let temporary = (root as NSString).appendingPathComponent(".\(agent.id)-install-\(UUID().uuidString)")
        try makeDirectory(temporary)
        defer { try? FileManager.default.removeItem(atPath: temporary) }
        let extraction = (temporary as NSString).appendingPathComponent("extracted")
        try makeDirectory(extraction)
        let kind = ACPRegistry.archiveKind(target.archive)
        let archivePath = (temporary as NSString).appendingPathComponent(kind.fileName)

        let digest: String
        do {
            digest = try await host.download(archiveURL, archivePath, ACPRegistry.maxArchiveBytes, ACPRegistry.archiveTimeout)
        } catch let error as ACPRegistryError {
            throw error
        } catch {
            throw ACPRegistryError(.downloadFailed, "Could not download \(agent.name) \(agent.version): \(error.localizedDescription)")
        }
        if let expected = target.sha256, digest.lowercased() != expected.lowercased() {
            throw ACPRegistryError(.checksumMismatch, "The \(agent.name) download did not match its published SHA-256.")
        }

        let staged = segments.reduce(extraction) { ($0 as NSString).appendingPathComponent($1) }
        if kind == .raw {
            try makeDirectory((staged as NSString).deletingLastPathComponent)
            try moveItem(archivePath, staged)
        } else {
            // macOS's bsdtar reads zip as well as tar. Unlike Info-ZIP's
            // `unzip` (which T3 Code uses off Windows), it refuses `..`,
            // absolute names and writing through a symlink by default.
            let listFlag = kind == .tarGz ? "-tzf" : kind == .tarBz2 ? "-tjf" : "-tf"
            let listing = try await runChecked("/usr/bin/tar", [listFlag, archivePath],
                                               timeout: ACPRegistry.packageQueryTimeout * 4,
                                               maxStdout: ACPRegistry.maxArchiveListingBytes, truncatedReason: .archiveInvalid)
            guard ACPRegistry.archiveEntriesAreSafe(listing) else {
                throw ACPRegistryError(.archiveInvalid, "The \(agent.name) archive holds an unsafe path.")
            }
            let extractFlag = kind == .tarGz ? "-xzf" : kind == .tarBz2 ? "-xjf" : "-xf"
            _ = try await runChecked("/usr/bin/tar", [extractFlag, archivePath, "-C", extraction],
                                     timeout: ACPRegistry.archiveTimeout, maxStdout: ACPRegistry.maxCommandOutputBytes,
                                     truncatedReason: .archiveInvalid)
        }
        guard FileManager.default.fileExists(atPath: staged) else {
            throw ACPRegistryError(.archiveInvalid, "The \(agent.name) archive did not contain '\(target.cmd)'.")
        }
        var info = stat()
        if lstat(staged, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG {
            chmod(staged, 0o755)
        }
        _ = try Self.executableInside(root: extraction, path: staged)
        try? FileManager.default.removeItem(atPath: installRoot)
        try moveItem(extraction, installRoot)
        let executable = try Self.executableInside(root: installRoot, path: finalExecutable)
        return ACPRegistryInstall(agentID: agent.id, name: agent.name, version: agent.version, distribution: .binary,
                                  executablePath: executable, arguments: resolved.args, environment: resolved.env,
                                  binDirectory: nil, packageSpec: nil)
    }

    private func installPackage(_ agent: ACPRegistry.Agent, _ resolved: ACPRegistry.ResolvedDistribution,
                                root: String) async throws -> ACPRegistryInstall {
        guard let spec = resolved.packageSpec, let runner = resolved.kind.runner else {
            throw ACPRegistryError(.installFailed, "\(agent.name) has no package to install.")
        }
        // T3 Code runs npm and uv from PATH. The app bundles Node but not
        // npm, so npm comes from the Mac too; a Mac without it is flagged.
        guard let manager = host.findProgram(runner, environment) else {
            throw ACPRegistryError(.runnerUnavailable, "\(agent.name) needs '\(runner)', which is not installed on this Mac.")
        }
        let packageRoot = (root as NSString).appendingPathComponent(resolved.kind == .npx ? "npm" : "python")
        let binDirectory = (packageRoot as NSString).appendingPathComponent("bin")
        try makeDirectory(packageRoot)

        var packageEnvironment = environment
        if resolved.kind == .npx {
            packageEnvironment["npm_config_prefix"] = packageRoot
        } else {
            packageEnvironment["UV_TOOL_DIR"] = packageRoot
            packageEnvironment["UV_TOOL_BIN_DIR"] = binDirectory
        }
        let managerDirectory = (Self.resolvingSymlinks(manager) as NSString).deletingLastPathComponent
        packageEnvironment["PATH"] = Self.prependPath(managerDirectory, to: packageEnvironment["PATH"])

        let installArguments = resolved.kind == .npx ? ["install", "--global", spec] : ["tool", "install", "--force", spec]
        _ = try await runChecked(manager, installArguments, environment: packageEnvironment,
                                 timeout: ACPRegistry.packageInstallTimeout, maxStdout: ACPRegistry.maxCommandOutputBytes,
                                 truncatedReason: .installFailed)

        let executable: String
        if resolved.kind == .npx {
            executable = try await discoverNpm(agent, spec: spec, manager: manager, environment: packageEnvironment, root: root)
        } else {
            executable = try await discoverUv(agent, spec: spec, manager: manager, environment: packageEnvironment, root: root)
        }
        return ACPRegistryInstall(agentID: agent.id, name: agent.name, version: agent.version, distribution: resolved.kind,
                                  executablePath: executable, arguments: resolved.args, environment: resolved.env,
                                  binDirectory: (executable as NSString).deletingLastPathComponent, packageSpec: spec)
    }

    private func discoverNpm(_ agent: ACPRegistry.Agent, spec: String, manager: String,
                             environment: [String: String], root: String) async throws -> String {
        let identity = ACPRegistry.splitPackageSpec(spec, kind: .npx)
        let globalRoot = try await singlePath(manager, ["root", "--global"], environment: environment)
        let globalPrefix = try await singlePath(manager, ["prefix", "--global"], environment: environment)
        let packageRoot = identity.name.split(separator: "/").reduce(globalRoot) { ($0 as NSString).appendingPathComponent(String($1)) }
        let manifestPath = (packageRoot as NSString).appendingPathComponent("package.json")
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: manifestPath),
              let size = attributes[.size] as? Int, size <= ACPRegistry.maxPackageManifestBytes,
              let data = FileManager.default.contents(atPath: manifestPath),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              manifest["name"] as? String == identity.name, manifest["version"] as? String == identity.version,
              let bin = manifest["bin"],
              let command = ACPRegistry.npmCommandName(agentID: agent.id, packageName: identity.name, bin: bin) else {
            throw ACPRegistryError(.installFailed, "npm installed \(spec), but its command could not be found.")
        }
        let path = ((globalPrefix as NSString).appendingPathComponent("bin") as NSString).appendingPathComponent(command)
        return try Self.executableInside(root: root, path: path)
    }

    private func discoverUv(_ agent: ACPRegistry.Agent, spec: String, manager: String,
                            environment: [String: String], root: String) async throws -> String {
        let identity = ACPRegistry.splitPackageSpec(spec, kind: .uvx)
        let listing = try await runChecked(manager, ["tool", "list"], environment: environment,
                                           timeout: ACPRegistry.packageQueryTimeout, maxStdout: ACPRegistry.maxCommandOutputBytes,
                                           truncatedReason: .installFailed)
        func normalized(_ name: String) -> String {
            name.lowercased().replacingOccurrences(of: "[._-]+", with: "-", options: .regularExpression)
        }
        let wanted = normalized(identity.name)
        let installed = listing.split(whereSeparator: \.isNewline).contains { line in
            let parts = line.split(separator: " ", maxSplits: 2)
            return parts.count >= 2 && normalized(String(parts[0])) == wanted && parts[1] == "v\(identity.version)"
        }
        guard installed else {
            throw ACPRegistryError(.installFailed, "uv installed \(spec), but it is not listed at that version.")
        }
        let binDirectory = try await singlePath(manager, ["tool", "dir", "--bin"], environment: environment)
        for candidate in ACPRegistry.packageCommandCandidates(agentID: agent.id, packageName: identity.name) {
            let path = (binDirectory as NSString).appendingPathComponent(candidate)
            if let found = try? Self.executableInside(root: root, path: path) { return found }
        }
        throw ACPRegistryError(.installFailed, "uv installed \(spec), but its command could not be found.")
    }

    // MARK: Removing

    /// Removes every installed version of `agentID`.
    public func uninstall(agentID: String) throws {
        guard ACPRegistry.isAgentID(agentID) else {
            throw ACPRegistryError(.installFailed, "Invalid agent id.")
        }
        let path = (agentsDirectory as NSString).appendingPathComponent(agentID)
        if FileManager.default.fileExists(atPath: path) {
            try FileManager.default.removeItem(atPath: path)
        }
    }

    /// Removes one installed version of `agentID`, and the agent's folder
    /// once no version is left.
    public func uninstall(agentID: String, version: String) throws {
        guard ACPRegistry.isAgentID(agentID), ACPRegistry.isVersion(version) else {
            throw ACPRegistryError(.installFailed, "Invalid agent id or version.")
        }
        let fileManager = FileManager.default
        let root = versionRoot(agentID: agentID, version: version)
        if fileManager.fileExists(atPath: root) { try fileManager.removeItem(atPath: root) }
        let agentRoot = (agentsDirectory as NSString).appendingPathComponent(agentID)
        if let left = try? fileManager.contentsOfDirectory(atPath: agentRoot), left.isEmpty {
            try? fileManager.removeItem(atPath: agentRoot)
        }
    }

    // MARK: Launching

    /// How to start an installed agent: its own program and arguments, the
    /// environment its entry asks for, and npm's or uv's bin folder first on
    /// PATH. Never installs.
    public static func launchSpec(for install: ACPRegistryInstall, workingDirectory: String?,
                                              baseEnvironment: [String: String]) -> AgentProcessLaunchSpec {
        var environment = baseEnvironment.merging(install.environment) { _, entry in entry }
        if let bin = install.binDirectory {
            environment["PATH"] = prependPath(bin, to: environment["PATH"])
        }
        return AgentProcessLaunchSpec(executable: install.executablePath, arguments: install.arguments,
                                      environment: environment, workingDirectory: workingDirectory)
    }

    // MARK: Helpers

    static func prependPath(_ directory: String, to path: String?) -> String {
        let existing = (path ?? "").split(separator: ":").map(String.init).filter { !$0.isEmpty && $0 != directory }
        return ([directory] + existing).joined(separator: ":")
    }

    private func writeReceipt(_ receipt: ACPRegistryInstall) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(receipt)
        let path = receiptPath(agentID: receipt.agentID, version: receipt.version)
        let temporary = path + ".\(UUID().uuidString).tmp"
        guard FileManager.default.createFile(atPath: temporary, contents: data) else {
            throw ACPRegistryError(.installFailed, "Could not save the install record for \(receipt.name).")
        }
        if rename(temporary, path) != 0 {
            unlink(temporary)
            throw ACPRegistryError(.installFailed, "Could not save the install record for \(receipt.name).")
        }
    }

    /// The real path of `path` when it is a regular executable file whose
    /// real path is inside `root`'s real path; throws otherwise.
    static func executableInside(root: String, path: String) throws -> String {
        let realRoot = Self.resolvingSymlinks(root)
        let realPath = Self.resolvingSymlinks(path)
        guard realPath.hasPrefix(realRoot + "/") else {
            throw ACPRegistryError(.archiveInvalid, "The agent's command resolves outside its install folder.")
        }
        var info = stat()
        guard stat(realPath, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, (info.st_mode & 0o111) != 0 else {
            throw ACPRegistryError(.archiveInvalid, "The agent's command is not a regular executable file.")
        }
        return realPath
    }

    static func resolvingSymlinks(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    private func makeDirectory(_ path: String) throws {
        do {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        } catch {
            throw ACPRegistryError(.installFailed, "Could not create \(path).")
        }
    }

    private func moveItem(_ source: String, _ destination: String) throws {
        guard rename(source, destination) == 0 else {
            throw ACPRegistryError(.installFailed, "Could not move the agent into place.")
        }
    }

    private func runChecked(_ executable: String, _ arguments: [String], environment: [String: String]? = nil,
                            timeout: TimeInterval, maxStdout: Int,
                            truncatedReason: ACPRegistryError.Reason) async throws -> String {
        let name = (executable as NSString).lastPathComponent
        let result: ACPRegistryHost.CommandResult
        do {
            result = try await host.run(executable, arguments, environment ?? self.environment, timeout, maxStdout)
        } catch let error as ACPRegistryError {
            throw error
        } catch {
            throw ACPRegistryError(.installFailed, "Could not run '\(name)': \(error.localizedDescription)")
        }
        guard result.status == 0 else {
            throw ACPRegistryError(.installFailed, "'\(name)' exited with code \(result.status): \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        // A cut-short listing would let an unsafe archive name through.
        guard !result.stdoutTruncated else {
            throw ACPRegistryError(truncatedReason, "'\(name)' printed more than expected.")
        }
        return result.stdout
    }

    private func singlePath(_ manager: String, _ arguments: [String], environment: [String: String]) async throws -> String {
        let output = try await runChecked(manager, arguments, environment: environment,
                                          timeout: ACPRegistry.packageQueryTimeout,
                                          maxStdout: ACPRegistry.maxCommandOutputBytes, truncatedReason: .installFailed)
        let lines = output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard lines.count == 1, lines[0].hasPrefix("/") else {
            throw ACPRegistryError(.installFailed, "'\((manager as NSString).lastPathComponent) \(arguments.joined(separator: " "))' gave an invalid path.")
        }
        return lines[0]
    }

    private func acquireLock(_ path: String) async throws {
        for _ in 0..<Self.lockRetries {
            let descriptor = open(path, O_CREAT | O_EXCL | O_WRONLY, 0o600)
            if descriptor >= 0 {
                close(descriptor)
                return
            }
            if let attributes = try? FileManager.default.attributesOfItem(atPath: path),
               let modified = attributes[.modificationDate] as? Date,
               Date().timeIntervalSince(modified) > Self.lockStaleAfter {
                unlink(path)
                continue
            }
            try await Task.sleep(nanoseconds: Self.lockRetryDelay)
        }
        throw ACPRegistryError(.installFailed, "Timed out waiting for another install of this agent to finish.")
    }
}
