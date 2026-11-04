// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CryptoKit
import Darwin
import Foundation

// Courier checks for a newer release of itself and installs it (Settings ▸ About ▸ Updates, and Courier ▸ Check for
// Updates…). The design follows the Vitruvian app's own updater (apps/desktop/vitruvian, VitruvianReleases and its
// installer), written again here for Courier:
// - Releases are tags of the public monorepo, `courier-v1.2.3`. That repository releases many products, so GitHub's
//   "latest release" is usually another product's: the check lists the `courier-v` tags itself, with the request
//   `git ls-remote` makes, which is not counted against GitHub's API limit.
// - What it installs is checked before anything is replaced: the SHA-256 the release publishes beside the disk image,
//   the disk image's and the app's Developer ID signatures (Courier's bundle ID and team), Gatekeeper's verdict that
//   the app is notarized, and the version inside the app matching the release's tag.
// - The new app is copied next to the old one first, then a small script waits for Courier to quit, swaps the two,
//   puts the old one back if the swap fails, and opens Courier again.

/// Where Courier's releases are published, and how they are read.
public enum CourierReleases {
    public static let owner = "VitruvianSoftware"
    public static let repository = "vitruvian-core"
    public static let tagPrefix = "courier-v"
    public static let bundleIdentifier = "com.vitruviansoftware.courier"
    /// The Developer ID team that signs every VitruvianSoftware Mac app.
    public static let teamIdentifier = "Q5MH753M3F"

    /// What the downloaded disk image must be signed by.
    public static var diskImageRequirement: String {
        "anchor apple generic and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
    }

    /// What the app inside it must be: Courier, signed by the same team.
    public static var appRequirement: String {
        "identifier \"\(bundleIdentifier)\" and \(diskImageRequirement)"
    }

    /// Git's endpoint for listing the repository's refs.
    public static var tagListURL: URL {
        URL(string: "https://github.com/\(owner)/\(repository).git/git-upload-pack")!
    }

    public static func tag(for version: SemanticVersion) -> String { tagPrefix + version.description }

    /// The universal disk image, signed and notarized, that runs on Apple silicon and Intel alike.
    public static func diskImageURL(for version: SemanticVersion) -> URL {
        URL(string: "https://github.com/\(owner)/\(repository)/releases/download/\(tag(for: version))/Courier-\(version)-universal.dmg")!
    }

    /// The image's SHA-256, which the release publishes beside it (tools/desktop-package).
    public static func checksumURL(for version: SemanticVersion) -> URL {
        URL(string: diskImageURL(for: version).absoluteString + ".sha256")!
    }

    /// The release's page, with its notes.
    public static func releasePageURL(for version: SemanticVersion) -> URL {
        URL(string: "https://github.com/\(owner)/\(repository)/releases/tag/\(tag(for: version))")!
    }

    /// Git protocol version 2's `ls-refs`, asking only for the `courier-v` tags: what
    /// `git ls-remote <repo> 'refs/tags/courier-v*'` sends. Each line is a pkt-line (four hex digits giving its
    /// length, those four included); `0001` ends the command and `0000` the request.
    public static var tagListRequestBody: Data {
        pktLine("command=ls-refs\n") + Data("0001".utf8)
            + pktLine("ref-prefix refs/tags/\(tagPrefix)\n") + Data("0000".utf8)
    }

    private static func pktLine(_ text: String) -> Data {
        let payload = Data(text.utf8)
        return Data(String(format: "%04x", payload.count + 4).utf8) + payload
    }

    public static func tagListRequest(userAgent: String) -> URLRequest {
        var request = URLRequest(url: tagListURL)
        request.httpMethod = "POST"
        request.setValue("version=2", forHTTPHeaderField: "Git-Protocol")
        request.setValue("application/x-git-upload-pack-request", forHTTPHeaderField: "Content-Type")
        request.setValue("application/x-git-upload-pack-result", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        request.httpBody = tagListRequestBody
        return request
    }

    /// The tag names in an `ls-refs` reply. Nil for a reply that is not one: an error line, a bad length, or a reply
    /// cut short before its closing `0000`.
    public static func tags(fromRefList data: Data) -> [String]? {
        let bytes = [UInt8](data)
        var index = 0
        var tags: [String] = []
        while index + 4 <= bytes.count {
            let header = bytes[index ..< index + 4]
            guard header.allSatisfy({ Character(UnicodeScalar($0)).isHexDigit }),
                  let length = Int(String(decoding: header, as: UTF8.self), radix: 16) else { return nil }
            if length == 0 { return tags }
            if length < 4 { index += 4; continue } // 0001 and 0002 carry nothing
            guard index + length <= bytes.count else { return nil }
            let line = String(decoding: bytes[(index + 4) ..< (index + length)], as: UTF8.self)
                .trimmingCharacters(in: .newlines)
            index += length
            if line.hasPrefix("ERR ") { return nil }
            let fields = line.split(separator: " ")
            guard fields.count >= 2 else { return nil }
            if fields[1].hasPrefix("refs/tags/") { tags.append(String(fields[1].dropFirst("refs/tags/".count))) }
        }
        return nil
    }

    /// The newest release among the tags: a plain `courier-vX.Y.Z` (no pre-release), by version, not by the order
    /// listed (which is alphabetical, so 0.9.0 comes after 0.10.0).
    public static func newestVersion(in tags: [String]) -> SemanticVersion? {
        tags.compactMap { tag -> SemanticVersion? in
            guard tag.hasPrefix(tagPrefix) else { return nil }
            return SemanticVersion(String(tag.dropFirst(tagPrefix.count)))
        }.max()
    }

    /// The hex SHA-256 in a `.sha256` file (`<hex>  <file name>`), lowercased; nil when there is none.
    public static func checksum(fromSidecar data: Data) -> String? {
        let text = String(decoding: data, as: UTF8.self)
        guard let first = text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).first else {
            return nil
        }
        let hex = first.lowercased()
        guard hex.count == 64, hex.allSatisfy({ $0.isHexDigit }) else { return nil }
        return hex
    }
}

/// A release's version, `1.2.3`. Only plain releases: a pre-release label is not one Courier installs.
public struct SemanticVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init?(_ text: String) {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts.allSatisfy({ !$0.isEmpty && $0.count <= 6 && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2]) else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    public var description: String { "\(major).\(minor).\(patch)" }
}

/// One HTTP reply.
public struct UpdateReply: Sendable {
    public let status: Int
    public let body: Data

    public init(status: Int, body: Data = Data()) {
        self.status = status
        self.body = body
    }
}

/// What the updater asks of the network and of this Mac. The app's is `SystemUpdateEnvironment`; the tests answer
/// from fakes, so no test reaches the network, mounts a disk image or replaces an app.
public protocol UpdateEnvironment: Sendable {
    /// One small request (the tag list, a checksum).
    func send(_ request: URLRequest) async throws -> UpdateReply
    /// Downloads `url` to the file `destination`, telling `progress` the fraction done.
    func download(_ url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws
    /// The file's SHA-256, as lowercase hex.
    func sha256(of file: URL) throws -> String
    /// Whether the code at `url` (an app, or a disk image) is validly signed and satisfies `requirement`.
    func satisfies(_ url: URL, requirement: String) -> Bool
    /// Whether Gatekeeper would open the app: signed with a Developer ID and notarized by Apple.
    func passesGatekeeper(_ app: URL) -> Bool
    /// Mounts the disk image read-only, out of sight; returns where.
    func mount(_ diskImage: URL) throws -> URL
    func unmount(_ mountPoint: URL)
    /// The app's CFBundleShortVersionString.
    func bundleVersion(of app: URL) -> String?
    /// Copies the app, keeping its signature intact.
    func copy(_ source: URL, to destination: URL) throws
    func isWritableDirectory(_ url: URL) -> Bool
    func remove(_ url: URL)
    /// Starts the script that swaps the apps once Courier has quit; it outlives Courier.
    func launchInstaller(script: String, arguments: [String]) throws
}

/// Settings ▸ About ▸ Updates and Courier ▸ Check for Updates…: whether a newer Courier is out, and installing it.
@MainActor
public final class UpdateModel: ObservableObject {
    public enum Phase: Equatable, Sendable {
        case idle
        case checking
        case upToDate
        case available(SemanticVersion)
        case downloading(SemanticVersion, fraction: Double)
        case verifying(SemanticVersion)
        /// The new app is in place beside the old one; Courier quits and comes back as the new version.
        case installing(SemanticVersion)
        case failed(String)
    }

    @Published public private(set) var phase: Phase = .idle
    @Published public private(set) var lastChecked: Date?
    /// Check at launch and once a day. On by default; Settings ▸ About turns it off.
    @Published public var checksAutomatically: Bool {
        didSet { defaults.set(checksAutomatically, forKey: Self.automaticKey) }
    }

    /// The version running now, nil for a build with no release version (which is never offered an update).
    public let currentVersion: SemanticVersion?
    /// The installed Courier.app the update replaces.
    public let appURL: URL
    private let environment: any UpdateEnvironment
    private let defaults: UserDefaults
    private let now: () -> Date
    private let processID: Int32
    private let quit: @MainActor () -> Void
    private var dailyTimer: Timer?

    public static let checkInterval: TimeInterval = 24 * 60 * 60
    static let automaticKey = "courier.updates.checkAutomatically"
    static let lastCheckedKey = "courier.updates.lastChecked"

    public init(
        currentVersion: String?,
        appURL: URL,
        environment: any UpdateEnvironment,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        processID: Int32 = ProcessInfo.processInfo.processIdentifier,
        quit: @escaping @MainActor () -> Void
    ) {
        self.currentVersion = currentVersion.flatMap(SemanticVersion.init)
        self.appURL = appURL
        self.environment = environment
        self.defaults = defaults
        self.now = now
        self.processID = processID
        self.quit = quit
        checksAutomatically = defaults.object(forKey: Self.automaticKey) as? Bool ?? true
        lastChecked = defaults.object(forKey: Self.lastCheckedKey) as? Date
    }

    /// The newer version on offer, if the last check found one.
    public var availableVersion: SemanticVersion? {
        switch phase {
        case let .available(version), let .downloading(version, _), let .verifying(version), let .installing(version):
            version
        default: nil
        }
    }

    public var isBusy: Bool {
        switch phase {
        case .checking, .downloading, .verifying, .installing: true
        default: false
        }
    }

    /// The check at launch, then one a day while Courier runs, when checking automatically is on.
    public func startAutomaticChecks() {
        dailyTimer?.invalidate()
        dailyTimer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.automaticCheck() }
        }
        Task { await automaticCheck() }
    }

    func automaticCheck() async {
        // A build with no release version (run from source) is never offered one, and says nothing about it.
        guard checksAutomatically, !isBusy, currentVersion != nil else { return }
        await check()
    }

    /// Asks which Courier releases exist and offers the newest if it is newer than this one.
    public func check() async {
        guard !isBusy else { return }
        guard let currentVersion else {
            phase = .failed(String(localized: "This build of Courier has no release version, so it can’t be updated."))
            return
        }
        phase = .checking
        let reply: UpdateReply
        do {
            reply = try await environment.send(CourierReleases.tagListRequest(userAgent: "Courier/\(currentVersion)"))
        } catch {
            phase = .failed(String(localized: "Couldn’t check for updates: \(error.localizedDescription)"))
            return
        }
        guard reply.status == 200 else {
            phase = .failed(reply.status == 429
                ? String(localized: "Couldn’t check for updates: GitHub is limiting requests. Try again later.")
                : String(localized: "Couldn’t check for updates: GitHub answered \(reply.status)."))
            return
        }
        guard let tags = CourierReleases.tags(fromRefList: reply.body) else {
            phase = .failed(String(localized: "Couldn’t check for updates: GitHub’s answer wasn’t a list of releases."))
            return
        }
        let checked = now()
        lastChecked = checked
        defaults.set(checked, forKey: Self.lastCheckedKey)
        if let newest = CourierReleases.newestVersion(in: tags), newest > currentVersion {
            phase = .available(newest)
        } else {
            phase = .upToDate
        }
    }

    /// Downloads the offered version, checks it, puts it beside this one and quits so the installer can swap them.
    /// Nothing is replaced unless every check passes.
    public func installUpdate() async {
        guard case let .available(version) = phase else { return }
        let parent = appURL.deletingLastPathComponent()
        guard environment.isWritableDirectory(parent) else {
            phase = .failed(String(localized: "Courier can’t replace itself in \(parent.path). Download Courier \(version.description) from its release page and put it in Applications."))
            return
        }
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("CourierUpdate-\(UUID().uuidString)", isDirectory: true)
        defer { environment.remove(work) }
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let staged = try await fetchAndVerify(version, into: work, beside: parent)
            phase = .installing(version)
            try environment.launchInstaller(script: Self.installerScript,
                                            arguments: [appURL.path, staged.path, String(processID), "/usr/bin/open"])
        } catch let failure as UpdateFailure {
            phase = .failed(failure.message)
            return
        } catch {
            phase = .failed(String(localized: "Couldn’t install the update: \(error.localizedDescription)"))
            return
        }
        quit()
    }

    private struct UpdateFailure: Error {
        let message: String
    }

    /// Every check, in order; returns the verified new app staged next to the installed one.
    private func fetchAndVerify(_ version: SemanticVersion, into work: URL, beside parent: URL) async throws -> URL {
        phase = .downloading(version, fraction: 0)
        let sidecar = try await environment.send(URLRequest(url: CourierReleases.checksumURL(for: version)))
        guard sidecar.status == 200, let expected = CourierReleases.checksum(fromSidecar: sidecar.body) else {
            throw UpdateFailure(message: String(localized: "Couldn’t read the update’s checksum, so it wasn’t downloaded."))
        }
        let diskImage = work.appendingPathComponent("Courier-\(version)-universal.dmg")
        try await environment.download(CourierReleases.diskImageURL(for: version), to: diskImage) { fraction in
            Task { @MainActor [weak self] in
                guard let self, case .downloading(version, _) = self.phase else { return }
                self.phase = .downloading(version, fraction: min(max(fraction, 0), 1))
            }
        }

        phase = .verifying(version)
        guard try environment.sha256(of: diskImage) == expected else {
            throw UpdateFailure(message: String(localized: "The download didn’t match its checksum, so nothing was installed."))
        }
        guard environment.satisfies(diskImage, requirement: CourierReleases.diskImageRequirement) else {
            throw UpdateFailure(message: String(localized: "The download isn’t signed by Courier’s developer, so nothing was installed."))
        }
        let mountPoint = try environment.mount(diskImage)
        defer { environment.unmount(mountPoint) }
        let newApp = mountPoint.appendingPathComponent("Courier.app")
        guard environment.satisfies(newApp, requirement: CourierReleases.appRequirement) else {
            throw UpdateFailure(message: String(localized: "The new Courier isn’t signed by Courier’s developer, so nothing was installed."))
        }
        guard environment.passesGatekeeper(newApp) else {
            throw UpdateFailure(message: String(localized: "macOS didn’t accept the new Courier as notarized, so nothing was installed."))
        }
        guard environment.bundleVersion(of: newApp) == version.description else {
            throw UpdateFailure(message: String(localized: "The download isn’t Courier \(version.description), so nothing was installed."))
        }
        // Beside the installed app, on the same disk, so the swap is a rename; hidden, so Spotlight and the Finder
        // don't show a second Courier while it waits.
        let staged = parent.appendingPathComponent(".Courier.app.update-\(version)")
        environment.remove(staged)
        try environment.copy(newApp, to: staged)
        guard environment.satisfies(staged, requirement: CourierReleases.appRequirement) else {
            environment.remove(staged)
            throw UpdateFailure(message: String(localized: "The new Courier didn’t copy intact, so nothing was installed."))
        }
        return staged
    }

    /// Run with `/bin/sh -c`: $1 the installed app, $2 the verified new app beside it, $3 Courier's process ID, $4 the
    /// program that opens Courier again (/usr/bin/open). It waits for Courier (and so its engine) to quit, moves the
    /// old app aside, moves the new one in, puts the old one back if that fails, and opens Courier.
    public static let installerScript = """
    APP="$1"; NEW="$2"; PID="$3"; OPEN="$4"
    BACKUP="$APP.update-old.$$"
    i=0
    while /bin/kill -0 "$PID" 2>/dev/null; do
        i=$((i + 1))
        if [ "$i" -gt 600 ]; then /bin/rm -rf "$NEW"; exit 1; fi
        /bin/sleep 0.2
    done
    if /bin/mv "$APP" "$BACKUP"; then
        if /bin/mv "$NEW" "$APP"; then
            /bin/rm -rf "$BACKUP"
        else
            /bin/mv "$BACKUP" "$APP"
            /bin/rm -rf "$NEW"
        fi
    else
        /bin/rm -rf "$NEW"
    fi
    "$OPEN" "$APP"
    """
}

/// The updater's real network and Mac: URLSession, CryptoKit, codesign, spctl, hdiutil and ditto.
public struct SystemUpdateEnvironment: UpdateEnvironment {
    public init() {}

    public func send(_ request: URLRequest) async throws -> UpdateReply {
        let (data, response) = try await URLSession.shared.data(for: request)
        return UpdateReply(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: data)
    }

    public func download(_ url: URL, to destination: URL,
                         progress: @escaping @Sendable (Double) -> Void) async throws {
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let expected = response.expectedContentLength
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }
        var buffer = Data()
        buffer.reserveCapacity(1 << 20)
        var written: Int64 = 0
        var lastReported = -1
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 1 << 20 {
                try handle.write(contentsOf: buffer)
                written += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if expected > 0 {
                    let percent = Int(written * 100 / expected)
                    if percent != lastReported { lastReported = percent; progress(Double(percent) / 100) }
                }
                // A release is tens of megabytes; this stops a reply that never ends.
                if written > 1 << 30 { throw URLError(.dataLengthExceedsMaximum) }
            }
        }
        try handle.write(contentsOf: buffer)
        progress(1)
    }

    public func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public func satisfies(_ url: URL, requirement: String) -> Bool {
        // An app's nested code (the engine in Contents/Helpers) is checked too; a disk image has none.
        let deep = url.pathExtension == "app" ? ["--deep"] : []
        return run("/usr/bin/codesign", ["--verify"] + deep + ["--strict", "-R=\(requirement)", url.path]) == 0
    }

    public func passesGatekeeper(_ app: URL) -> Bool {
        run("/usr/sbin/spctl", ["--assess", "--type", "execute", app.path]) == 0
    }

    public func mount(_ diskImage: URL) throws -> URL {
        let mountPoint = FileManager.default.temporaryDirectory
            .appendingPathComponent("CourierUpdateMount-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        guard run("/usr/bin/hdiutil", ["attach", diskImage.path, "-nobrowse", "-readonly", "-noautoopen", "-quiet",
                                       "-mountpoint", mountPoint.path]) == 0 else {
            try? FileManager.default.removeItem(at: mountPoint)
            throw CocoaError(.fileReadCorruptFile)
        }
        return mountPoint
    }

    public func unmount(_ mountPoint: URL) {
        if run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-quiet"]) != 0 {
            _ = run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force", "-quiet"])
        }
        try? FileManager.default.removeItem(at: mountPoint)
    }

    public func bundleVersion(of app: URL) -> String? {
        Bundle(url: app)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    public func copy(_ source: URL, to destination: URL) throws {
        guard run("/usr/bin/ditto", [source.path, destination.path]) == 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    public func isWritableDirectory(_ url: URL) -> Bool {
        FileManager.default.isWritableFile(atPath: url.path)
    }

    public func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    public func launchInstaller(script: String, arguments: [String]) throws {
        // POSIX_SPAWN_SETSID puts the installer in its own session so launchd does not sweep it away when Courier
        // quits; POSIX_SPAWN_CLOEXEC_DEFAULT keeps Courier's open descriptors out of the child.
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT))

        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        posix_spawn_file_actions_addopen(&fileActions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&fileActions, 1, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addopen(&fileActions, 2, "/dev/null", O_WRONLY, 0)

        let executable = "/bin/sh"
        let argv: [UnsafeMutablePointer<CChar>?] =
            ([executable, "-c", script, "courier-update"] + arguments).map { strdup($0) } + [nil]
        defer { for argument in argv { free(argument) } }

        var pid: pid_t = 0
        let status = posix_spawn(&pid, executable, &fileActions, &attributes, argv, environ)
        guard status == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(status))])
        }
    }

    private func run(_ tool: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return -1
        }
        process.waitUntilExit()
        return process.terminationStatus
    }
}
