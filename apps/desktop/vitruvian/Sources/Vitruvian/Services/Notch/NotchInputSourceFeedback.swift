// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Combine
import Foundation
import VitruvianCore

/// The island's keyboard layout notice. It shows the source now typing when
/// the person switches, and stays quiet for the announcement at launch, a
/// repeated one of the same source, and the Command Bar's own borrowing and
/// restoring. `NotchService` owns it; tests pass a source of their own.
@MainActor
package final class NotchInputSourceFeedback {
    /// The keyboard input sources as the notice reads them. `system` is Text
    /// Input Sources and the app's layout-change notification.
    @MainActor
    package struct Source {
        package var current: () -> InputSourceSelection.Reading?
        /// Each announced change; the source is read again when it arrives.
        package var changes: () -> AnyPublisher<Void, Never>

        package init(current: @escaping () -> InputSourceSelection.Reading?,
                     changes: @escaping () -> AnyPublisher<Void, Never>) {
            self.current = current
            self.changes = changes
        }

        package static var system: Source {
            // The layout labels already refresh on every source change and
            // post when they do, including once at launch.
            Source(current: { InputSourceSelection.currentReading() },
                   changes: {
                       NotificationCenter.default.publisher(for: GlobalShortcut.keyboardLayoutDidChange)
                           .map { _ in () }
                           .eraseToAnyPublisher()
                   })
        }
    }

    private let source: Source
    /// Shows a notice, or answers false when the island cannot.
    private let show: (NotchNotice) -> Bool
    /// The source the notice last read, so a repeated announcement of the
    /// same source, and the one the system posts at launch, say nothing.
    private var inputSourceID: String?
    /// The accepted Command Bar selection awaiting its source-change reading.
    private var ownInputSourceID: String?

    package init(source: Source, show: @escaping (NotchNotice) -> Bool) {
        self.source = source
        self.show = show
    }

    /// Follows the sources from the current one, which shows nothing, for as
    /// long as the returned subscription is kept.
    package func follow() -> AnyCancellable {
        ownInputSourceID = nil
        inputSourceID = source.current()?.id
        return source.changes()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.inputSourceChanged() }
    }

    /// The Command Bar borrows a Latin layout while it is up and gives it
    /// back on close. Neither switch is news the typist asked for, so each
    /// one marks itself as the app's own.
    package func noteOwnSwitch(to sourceID: String) {
        ownInputSourceID = sourceID
    }

    /// Reads the source after a change was announced.
    package func inputSourceChanged() {
        guard let reading = source.current(), reading.id != inputSourceID else { return }
        inputSourceID = reading.id
        let isOwnSwitch = reading.id == ownInputSourceID
        ownInputSourceID = nil
        guard !isOwnSwitch else { return }
        // Like the volume reading, the code takes the value's place and the
        // source's own name stands where the meter would.
        _ = show(NotchNotice(event: .inputSource, title: reading.code, detail: reading.name, symbol: "keyboard"))
    }
}
