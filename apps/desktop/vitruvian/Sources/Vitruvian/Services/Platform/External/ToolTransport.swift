// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation

/// What carries bytes between the app and one run of a tool's program. The
/// link above it knows the protocol; this knows a process and its pipes. A
/// test puts a stand-in here and no process is started.
///
/// Nothing here waits. Bytes the tool writes are read where they arrive and
/// handed to the main actor already taken apart; bytes for the tool are
/// queued and written elsewhere.
@MainActor
package protocol ToolTransport: AnyObject {
    /// Starts the program. False when it could not be started; nothing is
    /// delivered then, and `onExit` is never called.
    ///
    /// `onItems` hears what the tool wrote on its standard output, in order.
    /// `onErrorOutput` hears its standard error. `onExit` is called once,
    /// with the program's exit status, after which nothing more arrives.
    func start(onItems: @escaping @MainActor ([ToolInbound]) -> Void,
               onErrorOutput: @escaping @MainActor (Data) -> Void,
               onExit: @escaping @MainActor (Int32) -> Void) -> Bool

    /// Queues one line for the tool's standard input. False when the tool
    /// is not reading: too much is already waiting, or its input is closed.
    func send(_ line: Data) -> Bool

    /// Closes the tool's standard input, once what is queued is written.
    func closeInput()

    /// Asks the program to end.
    func terminate()

    /// Ends the program.
    func kill()

    /// True from a start that worked until the program is gone. Asked of
    /// the system at that moment: at quit nothing is delivered any more.
    var isRunning: Bool { get }
}
