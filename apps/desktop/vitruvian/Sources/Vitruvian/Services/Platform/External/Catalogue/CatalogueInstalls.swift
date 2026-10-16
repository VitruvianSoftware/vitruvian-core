// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore

/// The one install or update from the catalog that is under way, and its
/// result until the Extensions page takes it. It lives here, not in the
/// page, so that a person who leaves the page while a tool downloads finds,
/// on coming back, the download still going or the agreement sheet it led
/// to: nothing is dropped because the page that asked is gone.
///
/// One at a time, as the catalog's sheet allowed: a second Install or
/// Update while one is fetched, or while its result waits, is refused.
@preconcurrency @MainActor
package final class CatalogueInstalls: ObservableObject {
    /// What a fetch came to, waiting for the page.
    package enum Outcome: Equatable {
        /// The agreement sheet is to be shown for this offer.
        case ready(ToolOffer)
        /// The entry could not be offered, and why.
        case refused(CatalogueRefusal, entry: CatalogueEntry)
    }

    package static let shared = CatalogueInstalls(installer: .shared)

    /// The tool being fetched; nil when none is.
    @Published package private(set) var fetching: ToolID?
    /// What the last fetch came to, until the page takes it.
    @Published package private(set) var waiting: Outcome?

    private let installer: CatalogueInstaller

    package init(installer: CatalogueInstaller) {
        self.installer = installer
    }

    /// True while a tool is fetched or its result waits.
    package var isBusy: Bool { fetching != nil || waiting != nil }

    /// Fetches an entry and keeps what it comes to. False, and nothing is
    /// fetched, while another is under way or waits.
    @discardableResult
    package func start(_ entry: CatalogueEntry) -> Bool {
        guard !isBusy else { return false }
        fetching = entry.id
        installer.prepare(entry) { [weak self] result in
            guard let self else { return }
            self.fetching = nil
            switch result {
            case .success(let offer): self.waiting = .ready(offer)
            case .failure(let refused): self.waiting = .refused(refused, entry: entry)
            }
        }
        return true
    }

    /// The result that waits, given once: the page shows it, and the next
    /// install may start.
    package func take() -> Outcome? {
        defer { waiting = nil }
        return waiting
    }
}
