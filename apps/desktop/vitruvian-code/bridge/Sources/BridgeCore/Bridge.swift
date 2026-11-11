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

// The last release of Nexus Agent is this program. Old installs update
// themselves by downloading the release's "universal" zip and swapping
// NexusAgent.app in place; that zip holds this bridge, which fetches the
// current Vitruvian Code, installs it beside itself, opens it (its first launch
// moves the person's settings and folders over) and goes to the Trash.
//
// Everything that decides something is here, away from the window, so the
// tests can run it with a downloader that never touches the network.

public enum BridgeError: Error, Equatable, LocalizedError {
    /// No release could be found in any repository.
    case noRelease
    /// A release has no zip of the new app.
    case noAsset(String)
    /// The zip has no checksum file beside it, so it is not trusted.
    case noChecksum(String)
    case badChecksumFile
    case checksumMismatch
    case download(String)
    case install(String)

    public var errorDescription: String? {
        switch self {
        case .noRelease: return "No release of Vitruvian Code could be found."
        case .noAsset(let name): return "The release has no \(name)."
        case .noChecksum(let name): return "The release has no checksum for \(name), so it was not installed."
        case .badChecksumFile: return "The checksum file could not be read."
        case .checksumMismatch: return "The download does not match its checksum, so it was not installed."
        case .download(let why): return "Downloading failed: \(why)"
        case .install(let why): return "Installing failed: \(why)"
        }
    }
}

public struct Asset: Equatable, Sendable {
    public let name: String
    public let url: URL

    public init(name: String, url: URL) {
        self.name = name
        self.url = url
    }
}

public struct Release: Equatable, Sendable {
    public let tag: String
    public let assets: [Asset]

    public init(tag: String, assets: [Asset]) {
        self.tag = tag
        self.assets = assets
    }

    /// `1.2.3` from `v1.2.3`, `vitruvian-code-v1.2.3` or `nexus-agent-v1.2.3`.
    public var version: String { Releases.version(fromTag: tag) }
}

/// Where releases come from, and how bytes are fetched. The program's is
/// `GitHubNetwork`; the tests' is a fake.
public protocol ReleaseNetwork: Sendable {
    /// The release tagged `tag`, or the latest when `tag` is nil; nil when
    /// the repository has no such release.
    func release(repository: String, tag: String?) async throws -> Release?
    func download(_ url: URL) async throws -> Data
}

public enum Releases {
    /// The repositories to look in, in order: the app's own, then the one it
    /// had before it was renamed (GitHub redirects the old name once the
    /// repository is renamed, so either works then).
    public static let repositories = ["VitruvianSoftware/vitruvian-code", "VitruvianSoftware/nexus-agent"]

    public static func version(fromTag tag: String) -> String {
        guard let range = tag.range(of: #"(?:^|-)v?(\d+\.\d+\.\d+.*)$"#, options: .regularExpression) else { return tag }
        var text = String(tag[range])
        if text.hasPrefix("-") { text.removeFirst() }
        if text.hasPrefix("v") { text.removeFirst() }
        return text
    }

    /// The zip of the new app in a release: exactly `VitruvianCode-<v>-macos.zip`.
    /// The release's "universal" zip is the bridge itself, and is not it.
    public static func zipName(version: String) -> String { "VitruvianCode-\(version)-macos.zip" }

    /// The zip and its checksum, both required.
    public static func select(in release: Release) throws -> (zip: Asset, checksum: Asset) {
        let name = zipName(version: release.version)
        guard let zip = release.assets.first(where: { $0.name == name }) else { throw BridgeError.noAsset(name) }
        guard let checksum = release.assets.first(where: { $0.name == name + ".sha256" }) else {
            throw BridgeError.noChecksum(name)
        }
        return (zip, checksum)
    }

    /// The release for `version`: the one with its tag, in the first
    /// repository that has it with the new app's zip; failing that, the
    /// latest release of each repository in turn.
    public static func find(version: String, network: ReleaseNetwork) async throws -> Release {
        for tag in ["v\(version)", nil as String?] {
            for repository in repositories {
                if let release = try? await network.release(repository: repository, tag: tag),
                   (try? select(in: release)) != nil {
                    return release
                }
            }
        }
        throw BridgeError.noRelease
    }
}

public enum Checksum {
    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// `sha256sum`'s line (`<64 hex digits>  <name>`), or the bare digits.
    public static func expected(from file: Data) throws -> String {
        guard let text = String(data: file, encoding: .utf8),
              let first = text.split(whereSeparator: { $0.isWhitespace }).first else { throw BridgeError.badChecksumFile }
        let digits = first.lowercased()
        guard digits.count == 64, digits.allSatisfy({ $0.isHexDigit }) else { throw BridgeError.badChecksumFile }
        return digits
    }

    public static func verify(_ data: Data, against file: Data) throws {
        guard sha256Hex(data) == (try expected(from: file)) else { throw BridgeError.checksumMismatch }
    }
}

public enum InstallLocation {
    public static let appName = "Vitruvian Code.app"

    /// The folder the bridge runs from, when that is a real, writable
    /// folder (normally /Applications); otherwise /Applications, or failing
    /// that the person's own Applications folder. A quarantined download runs
    /// from a temporary translocated path that is gone at the next restart.
    public static func destination(bundleURL: URL, home: URL, isWritable: (URL) -> Bool) -> URL {
        let parent = bundleURL.deletingLastPathComponent()
        if !parent.path.contains("/AppTranslocation/"), isWritable(parent) {
            return parent.appendingPathComponent(appName)
        }
        let system = URL(fileURLWithPath: "/Applications", isDirectory: true)
        if isWritable(system) { return system.appendingPathComponent(appName) }
        return home.appendingPathComponent("Applications", isDirectory: true).appendingPathComponent(appName)
    }
}

public struct Installer {
    /// Unpacks a zip into a folder. The program's is `ditto`, which keeps
    /// what a signed app needs.
    public var unzip: (_ zip: URL, _ into: URL) throws -> Void
    public var fileManager: FileManager = .default

    public init(unzip: @escaping (URL, URL) throws -> Void, fileManager: FileManager = .default) {
        self.unzip = unzip
        self.fileManager = fileManager
    }

    /// Puts the app in `zip` at `destination`, in place of any app there. The
    /// old one is only replaced once the new one is whole.
    public func install(zip: Data, to destination: URL, scratch: URL) throws {
        let fm = fileManager
        do {
            try? fm.removeItem(at: scratch)
            try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: scratch) }
            let archive = scratch.appendingPathComponent("app.zip")
            let extracted = scratch.appendingPathComponent("extracted", isDirectory: true)
            try zip.write(to: archive)
            try fm.createDirectory(at: extracted, withIntermediateDirectories: true)
            try unzip(archive, extracted)
            let app = extracted.appendingPathComponent(InstallLocation.appName)
            guard fm.fileExists(atPath: app.path) else {
                throw BridgeError.install("the download has no \(InstallLocation.appName)")
            }
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: destination.path) {
                _ = try fm.replaceItemAt(destination, withItemAt: app)
            } else {
                try fm.moveItem(at: app, to: destination)
            }
        } catch let error as BridgeError {
            throw error
        } catch {
            throw BridgeError.install(error.localizedDescription)
        }
    }

    /// `ditto -x -k`.
    public static func ditto(_ zip: URL, _ into: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zip.path, into.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw BridgeError.install("the download could not be unpacked")
        }
    }
}

public struct Bridge {
    public var version: String
    public var network: ReleaseNetwork
    public var installer: Installer
    public var destination: URL
    public var scratch: URL
    /// Called with what is going on, for the window's one line.
    public var progress: (String) -> Void = { _ in }

    public init(version: String, network: ReleaseNetwork, installer: Installer, destination: URL, scratch: URL,
                progress: @escaping (String) -> Void = { _ in }) {
        self.version = version
        self.network = network
        self.installer = installer
        self.destination = destination
        self.scratch = scratch
        self.progress = progress
    }

    /// Finds, downloads, checks and installs the new app; returns where it is.
    public func install() async throws -> URL {
        progress("Looking for Vitruvian Code…")
        let release = try await Releases.find(version: version, network: network)
        let (zip, checksum) = try Releases.select(in: release)
        progress("Downloading Vitruvian Code \(release.version)…")
        let data: Data
        let digest: Data
        do {
            data = try await network.download(zip.url)
            digest = try await network.download(checksum.url)
        } catch let error as BridgeError {
            throw error
        } catch {
            throw BridgeError.download(error.localizedDescription)
        }
        progress("Checking the download…")
        try Checksum.verify(data, against: digest)
        progress("Installing…")
        try installer.install(zip: data, to: destination, scratch: scratch)
        return destination
    }

    /// `install()`, then what hands the person over: the new app is opened
    /// (which runs its migration) and only then does the bridge go to the
    /// Trash. A failure leaves the bridge where it is: it is the person's only
    /// way back to a working app.
    public func installAndHandOver(open: (URL) -> Void, trashSelf: () throws -> Void) async -> Result<URL, BridgeError> {
        do {
            let app = try await install()
            open(app)
            try? trashSelf()
            return .success(app)
        } catch let error as BridgeError {
            return .failure(error)
        } catch {
            return .failure(.install(error.localizedDescription))
        }
    }
}

/// GitHub's releases, over URLSession.
public struct GitHubNetwork: ReleaseNetwork {
    public init() {}

    public func release(repository: String, tag: String?) async throws -> Release? {
        let path = tag.map { "tags/\($0)" } ?? "latest"
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/\(path)") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return nil }
        if http.statusCode == 404 { return nil }
        guard http.statusCode == 200 else { throw BridgeError.download("GitHub answered \(http.statusCode)") }
        return Self.parse(data)
    }

    public func download(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw BridgeError.download("\(url.lastPathComponent): \(http.statusCode)")
        }
        return data
    }

    /// A release from GitHub's JSON.
    public static func parse(_ data: Data) -> Release? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else { return nil }
        let assets = (json["assets"] as? [[String: Any]] ?? []).compactMap { entry -> Asset? in
            guard let name = entry["name"] as? String, let link = entry["browser_download_url"] as? String,
                  let url = URL(string: link) else { return nil }
            return Asset(name: name, url: url)
        }
        return Release(tag: tag, assets: assets)
    }
}
