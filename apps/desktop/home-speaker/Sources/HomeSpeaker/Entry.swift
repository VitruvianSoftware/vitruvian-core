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
import HomeSpeakerCore

// The same binary is both the menu bar app and its command line, the
// Claude Code Stop hook included. Claude Code runs `HomeSpeaker
// --claude-stop-hook` with JSON on stdin; that path must never bring up a
// UI, so it is decided before SwiftUI starts. The command line itself is in
// Core (HomeSpeakerCommandLine), on the app's engine. (An explicit @main
// type rather than top-level code in main.swift, because Bazel's
// swift_library compiles with -parse-as-library.)
@main
enum Entry {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if HomeSpeakerCommandLine.recognizes(arguments) {
            MainActor.assumeIsolated {
                // The Stop hook and `--announce` stand aside while the
                // extension is chosen and installed, or this app is in the
                // Trash, so a stale hook never says a reply twice.
                HomeSpeakerCommandLine.run(arguments, engine: .app, parts: AppStartup.commandLineParts())
            }
        }
        HomeSpeakerApp.main()
    }
}
