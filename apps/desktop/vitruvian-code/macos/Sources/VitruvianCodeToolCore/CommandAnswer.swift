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

/// How a command from the app is answered.
///
/// The app fails a request that is not answered within two seconds, and
/// treats a tool with three unanswered requests in a row as crashed. A
/// command that only opens or changes a window cannot be refused, so it is
/// answered at once and the window opens on the main thread just after:
/// building the chat window the first time, or a main thread still busy
/// starting up, no longer holds the answer back. A command that can be
/// refused (starting or stopping the bot) still runs before it is answered,
/// so the refusal reaches the app.
public enum CommandAnswer {
    /// Commands answered before they run: each only shows a window.
    public static let answeredFirst: Set<String> = Set(
        [VitruvianCodeTool.Command.quickPrompt, VitruvianCodeTool.Command.newChat] + VitruvianCodeTool.Command.ade
    )

    /// Runs `command` for the app, from the kit's thread. `run` is called
    /// on `main`: later for a command in `answeredFirst`, at once and
    /// waited for otherwise, when what it throws is the answer.
    public static func handle(
        _ command: String,
        main: DispatchQueue = .main,
        run: @escaping @Sendable @MainActor (String) throws -> Void
    ) throws {
        if answeredFirst.contains(command) {
            main.async { MainActor.assumeIsolated { try? run(command) } }
            return
        }
        try main.sync { try MainActor.assumeIsolated { try run(command) } }
    }
}
