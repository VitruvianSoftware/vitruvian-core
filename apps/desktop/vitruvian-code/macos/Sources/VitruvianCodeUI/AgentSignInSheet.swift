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
//
// Shared by the standalone Vitruvian Code app and the Code feature of the
// Vitruvian desktop app. Written for Vitruvian and released under MIT by its
// copyright holder.

import SwiftUI
import VitruvianCodeCore

/// What the sign-in sheet says about a run, apart from the view so tests can read it.
public enum AgentSignInSheetLogic {
    /// The line under the output: what is happening, or how the run ended.
    public static func statusText(_ state: ACPSignInRun.State, strings: VitruvianCodeChatStrings) -> String? {
        switch state {
        case .ready, .succeeded: return nil
        case .running: return strings.signInRunning
        case .failed(let status): return AgentBannerLogic.format(strings.signInFailedFormat, String(status))
        case .couldNotStart: return strings.signInCouldNotStart
        case .cancelled: return strings.signInCancelled
        }
    }
}

/// The sheet a terminal sign-in runs in: the command first, then Run; what it prints as it
/// prints it; a field that sends the user's own reply; Cancel ends its process group.
public struct AgentSignInSheetView: View {
    @ObservedObject public var run: ACPSignInRun
    public let strings: VitruvianCodeChatStrings
    public let onClose: () -> Void
    @State private var reply = ""

    public init(run: ACPSignInRun, strings: VitruvianCodeChatStrings, onClose: @escaping () -> Void) {
        self.run = run
        self.strings = strings
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AgentBannerLogic.format(strings.signInSheetTitleFormat, run.method.name))
                .font(.headline)

            Text(strings.signInCommandCaption)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            AgentBannerLogic.verbatimText(run.command.displayLine)
                .font(.system(size: 11.5, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))

            if !run.command.methodVariableNames.isEmpty {
                AgentBannerLogic.verbatimText(strings.signInVariablesPrefix + run.command.methodVariableNames.joined(separator: ", "))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            if !run.command.refusedVariableNames.isEmpty {
                AgentBannerLogic.verbatimText(strings.signInRefusedPrefix + run.command.refusedVariableNames.joined(separator: ", "))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange)
            }

            if run.state != .ready {
                ScrollViewReader { proxy in
                    ScrollView {
                        AgentBannerLogic.verbatimText(run.output)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .id("end")
                    }
                    .frame(minHeight: 140, maxHeight: 260)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.25)))
                    .onChange(of: run.output) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
                }
            }

            if run.state == .running {
                TextField(strings.signInReplyPlaceholder, text: $reply)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11.5, design: .monospaced))
                    .onSubmit {
                        run.send(reply)
                        reply = ""
                    }
            }

            if let status = AgentSignInSheetLogic.statusText(run.state, strings: strings) {
                Text(status)
                    .font(.system(size: 11))
                    .foregroundStyle(run.state == .running ? Color.secondary : Color.orange)
            }

            HStack {
                Spacer()
                switch run.state {
                case .ready:
                    Button(strings.signInCancel) { onClose() }
                        .keyboardShortcut(.cancelAction)
                    Button(strings.signInRun) { run.start() }
                        .keyboardShortcut(.defaultAction)
                case .running:
                    Button(strings.signInCancel) {
                        Task { await run.cancel() }
                    }
                    .keyboardShortcut(.cancelAction)
                case .succeeded, .failed, .couldNotStart, .cancelled:
                    Button(strings.signInClose) { onClose() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(16)
        .frame(width: 460)
    }
}
