// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import CryptoKit
import Foundation
import os
import VitruvianCore

/// Why a tool from the catalog was not offered.
package enum CatalogueRefusal: Error, Equatable, Sendable {
    /// The download could not be fetched.
    case unreachable
    /// Its size or its SHA-256 is not the one the catalog pins.
    case mismatch
    /// It is no tool, would leave its folder, holds a link, or is another
    /// tool or version than the catalog says.
    case notTheTool
    /// The store refused the folder, as it would a folder the person picked.
    case store(ExternalToolStore.Refusal)
}

extension CatalogueEntry {
    /// What the store remembers about where a tool it adds came from.
    package var origin: CatalogueOrigin {
        CatalogueOrigin(id: id.rawValue, version: version, source: source.absoluteString,
                        download: download.url.absoluteString)
    }
}

/// Turns an entry of the catalog into an offer the agreement sheet can show,
/// and nothing more. Nothing is installed, started or remembered here: that
/// is `ExternalToolStore.add`, after the person agrees.
///
/// In this order, each step only when the one before passed: the download is
/// fetched into a folder of its own and refused as soon as it is larger than
/// the pinned size; its size and SHA-256 must be the pinned ones; its zip is
/// read and refused when an entry would leave the folder; it is unpacked and
/// looked over; its manifest must be the entry's id and version; then the
/// store makes the offer, as it does for a folder the person picked. A
/// refusal at any step deletes the folder. The folder of an offer is
/// deleted when the sheet is done with it (`finished(with:)`).
@MainActor
package final class CatalogueInstaller {
    package struct Parts: Sendable {
        package var fetcher: any CatalogueFetching
        package var source: CatalogueSource
        /// The folder downloads are unpacked in, one folder each. Nothing
        /// else is ever in it.
        package var scratch: URL
        package var limits: ToolLimits
        /// Unpacks a zip into a folder that does not exist yet.
        package var unpack: @Sendable (_ zip: URL, _ folder: URL) -> Bool
        /// Runs work off the main thread.
        package var work: @Sendable (@escaping @Sendable () -> Void) -> Void
        /// Runs work on the main thread.
        package var toMain: @Sendable (@escaping @Sendable @MainActor () -> Void) -> Void

        package init(fetcher: any CatalogueFetching, source: CatalogueSource, scratch: URL,
                     limits: ToolLimits = .standard,
                     unpack: @escaping @Sendable (URL, URL) -> Bool = { CatalogueArchive.unpack($0, into: $1) },
                     work: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void,
                     toMain: @escaping @Sendable (@escaping @Sendable @MainActor () -> Void) -> Void) {
            self.fetcher = fetcher
            self.source = source
            self.scratch = scratch
            self.limits = limits
            self.unpack = unpack
            self.work = work
            self.toMain = toMain
        }

        /// The app as it is: the network, a folder of its own under the
        /// temporary folder, and a queue of its own.
        @MainActor package static var live: Parts {
            Parts(fetcher: URLSessionCatalogueFetcher(), source: CatalogueSource.inUse,
                  scratch: FileManager.default.temporaryDirectory
                      .appendingPathComponent("com.vitruviansoftware.vitruvian.catalog", isDirectory: true),
                  work: { DispatchQueue.global(qos: .utility).async(execute: $0) },
                  toMain: { work in DispatchQueue.main.async { MainActor.assumeIsolated { work() } } })
        }
    }

    package static let shared = CatalogueInstaller(parts: .live, store: { .shared })

    private let parts: Parts
    private let store: @MainActor () -> ExternalToolStore
    /// What to call when each download in flight is done, by its folder.
    private var waiting: [URL: @MainActor (Result<ToolOffer, CatalogueRefusal>) -> Void] = [:]

    package init(parts: Parts, store: @escaping @MainActor () -> ExternalToolStore) {
        self.parts = parts
        self.store = store
    }

    /// Fetches, checks and unpacks an entry, and has the store offer it.
    /// `then` is called once, on the main thread, with the offer or why
    /// there is none.
    package func prepare(_ entry: CatalogueEntry, then: @escaping @MainActor (Result<ToolOffer, CatalogueRefusal>) -> Void) {
        let job = parts.scratch.appendingPathComponent(UUID().uuidString, isDirectory: true)
        guard parts.source.permits(entry.download.url), entry.download.size <= parts.limits.folderBytes,
              PrivateFileStore.createDirectory(at: job, container: parts.scratch),
              FileManager.default.createFile(atPath: job.appendingPathComponent("download.zip").path, contents: nil),
              let file = try? FileHandle(forWritingTo: job.appendingPathComponent("download.zip")) else {
            try? FileManager.default.removeItem(at: job)
            then(.failure(.unreachable))
            return
        }
        waiting[job] = then
        let download = Download(file: file, size: entry.download.size)
        let parts = self.parts
        parts.fetcher.fetch(
            CatalogueRequest(url: entry.download.url, limit: entry.download.size),
            permits: { [source = parts.source] in source.permits($0) },
            body: { download.append($0) },
            done: { response in
                parts.work {
                    let result = Self.check(response, download, entry: entry, job: job, parts: parts)
                    parts.toMain { [weak self] in self?.offer(result, entry: entry, job: job) }
                }
            })
    }

    /// The folder of an offer this made is deleted, with its download. For
    /// any other offer, such as one of a folder the person picked, nothing
    /// happens.
    package func finished(with offer: ToolOffer) {
        guard owns(offer.folder) else { return }
        try? FileManager.default.removeItem(at: offer.folder.deletingLastPathComponent())
    }

    /// True for a folder inside this installer's own.
    package func owns(_ folder: URL) -> Bool {
        let root = parts.scratch.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let path = folder.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        return path.count == root.count + 2 && Array(path.prefix(root.count)) == root
    }

    /// Deletes whatever an earlier run left in the installer's own folder:
    /// a download the app quit in the middle of. At launch, before anything
    /// is fetched.
    package func sweep() {
        try? FileManager.default.removeItem(at: parts.scratch)
    }

    // MARK: - The steps

    /// The steps after the download, off the main thread. On any refusal
    /// the job's folder is gone when this returns.
    nonisolated private static func check(_ response: CatalogueResponse, _ download: Download, entry: CatalogueEntry,
                                          job: URL, parts: Parts) -> Result<URL, CatalogueRefusal> {
        let got = download.close()
        let result: Result<URL, CatalogueRefusal>
        switch response {
        case .complete where got.size == entry.download.size && got.digest == entry.download.sha256:
            result = unpack(job, entry: entry, parts: parts)
        case .complete, .stopped:
            result = .failure(.mismatch)
        case .notModified, .failed:
            result = .failure(.unreachable)
        }
        if case .failure = result { try? FileManager.default.removeItem(at: job) }
        return result
    }

    nonisolated private static func unpack(_ job: URL, entry: CatalogueEntry, parts: Parts) -> Result<URL, CatalogueRefusal> {
        let zip = job.appendingPathComponent("download.zip")
        let tool = job.appendingPathComponent("tool", isDirectory: true)
        guard case .success(let listing) = CatalogueArchive.vet(zip, limits: parts.limits),
              parts.unpack(zip, tool),
              CatalogueArchive.looksRight(tool, listing: listing, limits: parts.limits),
              case .success(let read) = ExternalToolManifest.read(folder: tool),
              read.manifest.id == entry.id, read.version == entry.version else { return .failure(.notTheTool) }
        try? FileManager.default.removeItem(at: zip)
        return .success(tool)
    }

    /// Back on the main thread: the store makes the offer.
    private func offer(_ checked: Result<URL, CatalogueRefusal>, entry: CatalogueEntry, job: URL) {
        guard let then = waiting.removeValue(forKey: job) else { return }
        switch checked {
        case .failure(let refusal):
            then(.failure(refusal))
        case .success(let tool):
            switch store().offer(from: tool, catalogue: entry.origin) {
            case .success(let offer):
                then(.success(offer))
            case .failure(let refusal):
                try? FileManager.default.removeItem(at: job)
                then(.failure(.store(refusal)))
            }
        }
    }

    /// A download as it arrives: written to its file and hashed on the way,
    /// and refused once it is larger than the pinned size. The fetcher calls
    /// it from one thread at a time.
    private final class Download: @unchecked Sendable {
        private let lock = NSLock()
        private let file: FileHandle
        private let size: Int
        private var hasher = SHA256()
        private var written = 0
        private var failed = false

        init(file: FileHandle, size: Int) {
            self.file = file
            self.size = size
        }

        /// False to stop: past the pinned size, or the file would not take it.
        func append(_ chunk: Data) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            written += chunk.count
            guard !failed, written <= size, (try? file.write(contentsOf: chunk)) != nil else {
                failed = true
                return false
            }
            hasher.update(data: chunk)
            return true
        }

        /// Closes the file, and says how much arrived and its SHA-256 in hex;
        /// an empty digest when it failed.
        func close() -> (size: Int, digest: String) {
            lock.lock()
            defer { lock.unlock() }
            try? file.close()
            guard !failed else { return (written, "") }
            return (written, hasher.finalize().map { String(format: "%02x", $0) }.joined())
        }
    }
}
