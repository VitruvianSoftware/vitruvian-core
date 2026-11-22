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
import VitruvianToolKit
import VitruvianToolProtocol

/// How a panel the app opens, sends events to, or closes is answered.
///
/// The app fails a request not answered within two seconds (three in a row
/// and the tool is treated as crashed). A panel's page is made on the main
/// thread, and the main thread can be busy for longer than that: building
/// the chat window the first time, which a Quick Prompt just before does,
/// takes over two seconds on a loaded Mac (#4813, #5357). So the main thread
/// gets `waitSeconds` to answer an open (falling back to the last page it
/// showed) or an event (falling back to `.keep`), and the page the main
/// thread then makes is sent after it, unprompted. With no page yet to fall
/// back on, an open waits as long as it takes. A close notice never waits
/// on the main thread, so it cannot block the next request behind it.
///
/// Only the kit's thread calls `open`, `event`, and `close`; any thread
/// may call `remember`.
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
        let attempt = Attempt<UITree>()
        main.async {
            let tree = MainActor.assumeIsolated { make() }
            self.remember(tree, for: panel)
            if !attempt.finish(tree) { render(tree) }
        }
        if attempt.done.wait(timeout: .now() + wait) == .success, let tree = attempt.value { return tree }
        if let fallback = page(for: panel), attempt.giveUp() { return fallback }
        // Nothing to fall back on, or the page came as it was given up on.
        attempt.done.wait()
        return attempt.value!
    }

    /// Answers a panel event from the kit's thread. `handle` runs on `main`,
    /// once; if `main` does not finish within `wait`, answers `.keep` and
    /// sends any resulting `.page` later via `render`.
    public func event(
        _ panel: String,
        main: DispatchQueue = .main,
        wait: Double = PanelOpen.waitSeconds,
        handle: @escaping @Sendable @MainActor () -> PanelAnswer,
        render: @escaping @Sendable (UITree) -> Void
    ) -> PanelAnswer {
        let attempt = Attempt<PanelAnswer>()
        main.async {
            let answer = MainActor.assumeIsolated { handle() }
            if case .page(let tree) = answer { self.remember(tree, for: panel) }
            if !attempt.finish(answer), case .page(let tree) = answer { render(tree) }
        }
        if attempt.done.wait(timeout: .now() + wait) == .success, let answer = attempt.value { return answer }
        if attempt.giveUp() { return .keep }
        // The answer arrived just as we tried to give up.
        attempt.done.wait()
        return attempt.value!
    }

    /// Runs a panel close notice on `main` without blocking the kit's thread.
    public func close(
        main: DispatchQueue = .main,
        run: @escaping @Sendable @MainActor () -> Void
    ) {
        main.async { MainActor.assumeIsolated { run() } }
    }

    /// One main-thread round-trip: the result, if the main thread made it in time.
    private final class Attempt<Value: Sendable>: @unchecked Sendable {
        let done = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var made: Value?
        private var late = false

        var value: Value? {
            lock.lock()
            defer { lock.unlock() }
            return made
        }

        /// The main thread's result. False when the request was already answered
        /// without it, so any follow-up page must be sent unprompted.
        func finish(_ value: Value) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !late else { return false }
            made = value
            done.signal()
            return true
        }

        /// The kit's thread stops waiting. False when the result came in the
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
