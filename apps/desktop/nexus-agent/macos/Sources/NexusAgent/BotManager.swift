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

import SwiftUI
import Foundation
import Combine
import NexusAgentCore

/// What the views show about the Telegram bot, and the buttons they press.
/// The work itself (starting Node, the PID file, the log) is the shared
/// engine's; this class only mirrors the engine's state for SwiftUI.
@MainActor
class BotManager: ObservableObject {
    @Published var isRunning = false
    @Published var lastLogLines: [String] = []
    @Published var pid: Int32? = nil

    /// The shared engine, also used by `ConfigManager` to read and save `.env`.
    let engine: StandaloneEngine

    /// The engine's host, which keeps this app's saved providers.
    /// `ConfigManager` writes them through it.
    let host: StandaloneHost

    private var cancellables: Set<AnyCancellable> = []

    init() {
        let host = StandaloneHost()
        let engine = StandaloneEngine(environment: .live, host: host)
        // A notification about a finished turn carries the conversation it
        // was in, so a click on it can come back to that one.
        host.openConversation = { [weak engine] in
            (engine?.session.conversationID, engine?.session.sessionTitle)
        }
        // A turn waiting for approval is announced only when the chat is
        // out of sight, which the engine knows.
        host.chatIsVisible = { [weak engine] in engine?.isChatVisible ?? false }
        self.host = host
        self.engine = engine

        // The engine changes its state on the main thread, and each of these
        // hands over the new value as it changes.
        engine.$isRunning
            .sink { [weak self] running in self?.isRunning = running }
            .store(in: &cancellables)
        engine.$pid
            .sink { [weak self] pid in self?.pid = pid }
            .store(in: &cancellables)
        // The log panel is rebuilt when either the log or the problem
        // changes. A publisher fires just before the engine's property takes
        // the new value, so the rebuild waits one turn of the main queue and
        // then reads the engine, which by then holds both.
        Publishers.CombineLatest(engine.$logLines, engine.$problem)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshLogLines() }
            .store(in: &cancellables)

        // Status and log stay live for as long as the app runs, so polling is
        // started once here and never stopped.
        engine.startPolling()
    }

    /// The engine's log lines, then why the bot could not start or the
    /// settings could not be saved, when there is such a problem: the log
    /// panel is the only place this app has to say it.
    private func refreshLogLines() {
        var lines = engine.logLines
        if let problem = engine.problemDescription {
            lines.append(problem)
        }
        if lastLogLines != lines {
            lastLogLines = lines
        }
    }

    // MARK: - Process Control

    func start() {
        engine.start()
    }

    func stop() {
        engine.stop()
    }

    func restart() {
        engine.restart()
    }

    func openLogs() {
        engine.openLog()
    }
}
