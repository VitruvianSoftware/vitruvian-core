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

import Foundation
import VitruvianToolProtocol

/// How a panel the app opens is answered.
///
/// The app fails a request not answered within two seconds (three in a row
/// and the tool is treated as crashed). A panel's page is made on the main
/// thread, and the main thread can be busy for longer than that: building
/// the chat window the first time, which a Quick Prompt just before does,
/// takes over two seconds on a loaded Mac (#4813). So the main thread gets
/// `waitSeconds` to make the page; past that, the panel is answered with the last
/// page it showed, and the page the main thread then makes is sent after it,
/// unprompted. With no page yet to fall back on, it waits as long as it takes.
///
/// Only the kit's thread calls `open`; any thread may call `remember`.
public final class PanelOpen: @unchecked Sendable {
    /// How long the main thread gets to make the page before the last one
    /// is sent instead: well inside the app's two seconds.
    public static let waitSeconds = 0.75

    private let lock = NSLock()
    private var pages: [String: UITree] = [:]

    public init() {}

    /// The page `panel` shows now, kept for an open the main thread is too
    /// busy to answer in time.
    public func remember(_ tree: UITree, for panel: String) {
        lock.lock()
        pages[panel] = tree
        lock.unlock()
    }

    /// The last page remembered for `panel`.
    public func page(for panel: String) -> UITree? {
        lock.lock()
        defer { lock.unlock() }
        return pages[panel]
    }

    /// Answers the app's open of `panel`, from the kit's thread. `make` runs
    /// on `main`, once, as it did before; when it finishes too late for the
    /// answer, its page goes to `render`, which sends it to the app.
    public func open(
        _ panel: String,
        main: DispatchQueue = .main,
        wait: Double = PanelOpen.waitSeconds,
        make: @escaping @Sendable @MainActor () -> UITree,
        render: @escaping @Sendable (UITree) -> Void
    ) -> UITree {
        let attempt = Attempt()
        main.async {
            let tree = MainActor.assumeIsolated { make() }
            self.remember(tree, for: panel)
            if !attempt.finish(tree) { render(tree) }
        }
        if attempt.done.wait(timeout: .now() + wait) == .success, let tree = attempt.tree { return tree }
        if let fallback = page(for: panel), attempt.giveUp() { return fallback }
        // Nothing to fall back on, or the page came as it was given up on.
        attempt.done.wait()
        return attempt.tree!
    }

    /// One open: the page, if the main thread made it in time.
    private final class Attempt: @unchecked Sendable {
        let done = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var made: UITree?
        private var late = false

        var tree: UITree? {
            lock.lock()
            defer { lock.unlock() }
            return made
        }

        /// The main thread's page. False when the open was already answered
        /// without it, and the page must be sent unprompted.
        func finish(_ tree: UITree) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !late else { return false }
            made = tree
            done.signal()
            return true
        }

        /// The kit's thread stops waiting. False when the page came in the
        /// meantime, and is the answer after all.
        func giveUp() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard made == nil else { return false }
            late = true
            return true
        }
    }
}
