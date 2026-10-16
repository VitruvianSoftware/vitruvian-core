// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Combine
import Foundation
import os
import VitruvianCore

/// The list of tools, kept current: fetched with its signature, verified,
/// remembered, and asked which tools from the catalog have a newer version.
///
/// It fetches when the person opens the catalog, and, while at least one
/// tool from the catalog is installed, at launch and once a day after. With
/// none installed it fetches nothing on its own. Each fetch sends the ETag of
/// the list it has, so an unchanged list costs one small answer. The last
/// list that verified is kept in the app's support folder, with its
/// signature and its ETag, and is verified again whenever it is read.
@MainActor
package final class CatalogueWatch: ObservableObject {
    package enum State: Equatable, Sendable {
        /// Nothing fetched and nothing kept.
        case unknown
        /// A fetch is in flight and there is nothing to show yet.
        case loading
        /// A list that verified.
        case ready(Catalogue)
        /// The list could not be fetched, and none was kept.
        case unreachable
        /// A list was fetched and its signature is not ours, or it is older
        /// than one accepted before.
        case notOurs
    }

    package struct Parts {
        package var fetcher: any CatalogueFetching
        package var source: CatalogueSource
        package var clock: any ToolClock
        /// The file the last list that verified is kept in; nil keeps none.
        package var kept: URL?
        /// This app's version, as `CFBundleShortVersionString` gives it.
        package var appVersion: String
        /// The tools the person added, as the store lists them.
        package var listed: @MainActor () -> [ExternalToolStore.Listed]
        package var toMain: @Sendable (@escaping @Sendable @MainActor () -> Void) -> Void

        package init(fetcher: any CatalogueFetching, source: CatalogueSource, clock: any ToolClock, kept: URL?,
                     appVersion: String, listed: @escaping @MainActor () -> [ExternalToolStore.Listed],
                     toMain: @escaping @Sendable (@escaping @Sendable @MainActor () -> Void) -> Void) {
            self.fetcher = fetcher
            self.source = source
            self.clock = clock
            self.kept = kept
            self.appVersion = appVersion
            self.listed = listed
            self.toMain = toMain
        }

        @MainActor package static var live: Parts {
            Parts(fetcher: URLSessionCatalogueFetcher(), source: CatalogueSource.inUse, clock: SystemToolClock.shared,
                  kept: ToolFolders.live?.root.appendingPathComponent(CatalogueWatch.keptFileName),
                  appVersion: AppInfo.version, listed: { ExternalToolStore.shared.listed },
                  toMain: { work in DispatchQueue.main.async { MainActor.assumeIsolated { work() } } })
        }
    }

    /// How long between two fetches made on the app's own: a day of the Mac
    /// being awake, as `SystemToolClock` counts.
    package static let day: TimeInterval = 86_400
    /// The file in the app's support folder the last list is kept in.
    package static let keptFileName = "Catalog.json"

    package static let shared = CatalogueWatch(parts: .live)

    @Published package private(set) var state: State = .unknown

    private let parts: Parts
    /// The last list that verified: its bytes, its signature and its ETag.
    private var last: Kept?
    private var fetching = false
    private var daily: (any ToolTimer)?

    package init(parts: Parts) {
        self.parts = parts
    }

    /// At launch: reads the list kept from before, fetches a new one when a
    /// tool from the catalog is installed, and does the same once a day.
    package func start() {
        if let kept = parts.kept, let data = FileManager.default.contents(atPath: kept.path),
           let file = try? JSONDecoder().decode(Kept.self, from: data),
           CatalogueSigning.verify(file.list, signatureFile: file.signature, publicKey: parts.source.publicKey),
           let catalogue = Catalogue.read(file.list, permits: parts.source.permits) {
            last = file
            state = .ready(catalogue)
        }
        if watchesSomething { refresh() }
        scheduleDaily()
    }

    /// Fetches the list now, unless a fetch is already in flight.
    package func refresh() {
        guard !fetching else { return }
        fetching = true
        if last == nil { state = .loading }
        let list = Buffer(limit: Catalogue.mostBytes)
        let toMain = parts.toMain
        parts.fetcher.fetch(
            CatalogueRequest(url: parts.source.list, etag: last?.etag, limit: Catalogue.mostBytes),
            permits: { [source = parts.source] in source.permits($0) }, body: { list.append($0) },
            done: { response in
                toMain { [weak self] in self?.listArrived(response, list.data) }
            })
    }

    /// The entries this app can install.
    package var entries: [CatalogueEntry] {
        guard case .ready(let catalogue) = state else { return [] }
        return catalogue.installable(appVersion: parts.appVersion)
    }

    /// The newer version the catalog lists of a tool the person added, or
    /// nil. A tool installed from the catalog is compared at the version it
    /// was installed at (`ToolRecord.catalogue`). One added from a folder is
    /// matched by its id and compared at the version the person agreed to:
    /// updating it from the catalog moves it onto the catalog. The same
    /// version, or an older one, is never offered.
    package func update(for listed: ExternalToolStore.Listed) -> CatalogueEntry? {
        guard let installed = Self.comparedVersion(of: listed) else { return nil }
        return entries.first { $0.id == listed.id && Catalogue.isNewer($0.version, than: installed) }
    }

    /// The version an added tool is compared with the catalog at; nil for
    /// one that is never compared. A tool from the catalog is compared at
    /// the entry it came from, when that entry is its own id. One added from
    /// a folder is compared at the version the person agreed to, unless it
    /// is held back: its copy is then no version they agreed to, and only
    /// its folder brings it back.
    package static func comparedVersion(of listed: ExternalToolStore.Listed) -> String? {
        guard let origin = listed.record.catalogue else {
            return listed.isHeld ? nil : listed.record.agreement.version
        }
        return origin.id == listed.id.rawValue ? origin.version : nil
    }

    // MARK: - Fetching

    private var watchesSomething: Bool {
        parts.listed().contains { $0.record.catalogue != nil }
    }

    private func scheduleDaily() {
        daily?.cancel()
        daily = parts.clock.after(Self.day) { [weak self] in
            guard let self else { return }
            if watchesSomething { refresh() }
            scheduleDaily()
        }
    }

    private func listArrived(_ response: CatalogueResponse, _ data: Data) {
        switch response {
        case .notModified:
            guard let last else { return failed() }
            accept(list: last.list, signature: last.signature, etag: last.etag)
        case .complete(let etag):
            let signature = Buffer(limit: CatalogueSigning.signatureFileBytes)
            let toMain = parts.toMain
            parts.fetcher.fetch(
                CatalogueRequest(url: parts.source.signature, limit: CatalogueSigning.signatureFileBytes),
                permits: { [source = parts.source] in source.permits($0) }, body: { signature.append($0) },
                done: { response in
                    toMain { [weak self] in
                        guard case .complete = response else {
                            self?.failed()
                            return
                        }
                        self?.accept(list: data, signature: signature.data, etag: etag)
                    }
                })
        case .stopped, .failed:
            failed()
        }
    }

    /// Verifies a list, and takes it when it is ours and no older than the
    /// last one taken.
    private func accept(list: Data, signature: Data, etag: String?) {
        fetching = false
        guard CatalogueSigning.verify(list, signatureFile: signature, publicKey: parts.source.publicKey) else {
            state = .notOurs
            return
        }
        guard let catalogue = Catalogue.read(list, permits: parts.source.permits) else {
            failed()
            return
        }
        if let before = last.flatMap({ Catalogue.read($0.list, permits: parts.source.permits) }),
           catalogue.generated < before.generated {
            state = .notOurs
            return
        }
        let file = Kept(list: list, signature: signature, etag: etag)
        if file != last, let kept = parts.kept, let data = try? JSONEncoder().encode(file),
           PrivateFileStore.createDirectory(at: kept.deletingLastPathComponent(),
                                            container: kept.deletingLastPathComponent()) {
            _ = PrivateFileStore.write(data, to: kept)
        }
        last = file
        state = .ready(catalogue)
    }

    /// A fetch that did not work: the list kept from before stays.
    private func failed() {
        fetching = false
        if case .ready = state { return }
        state = last.flatMap { Catalogue.read($0.list, permits: parts.source.permits) }.map(State.ready) ?? .unreachable
    }

    /// The list as it is kept: its bytes and signature in base64, and the
    /// ETag that came with it.
    private struct Kept: Codable, Equatable {
        let list: Data
        let signature: Data
        let etag: String?
    }

    /// Bytes as they arrive, no more than `limit`.
    private final class Buffer: @unchecked Sendable {
        private let lock = NSLock()
        private let limit: Int
        private var bytes = Data()

        init(limit: Int) {
            self.limit = limit
        }

        func append(_ chunk: Data) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard bytes.count + chunk.count <= limit else { return false }
            bytes.append(chunk)
            return true
        }

        var data: Data {
            lock.lock()
            defer { lock.unlock() }
            return bytes
        }
    }
}
