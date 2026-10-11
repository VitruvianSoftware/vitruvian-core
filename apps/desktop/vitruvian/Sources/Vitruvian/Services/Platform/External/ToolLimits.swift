// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation

/// The numbers that keep a tool that misbehaves from costing the app its
/// responsiveness. They are the ones in the design, section 7. They protect
/// the app, not the person's data: a tool is trusted like an app.
///
/// Every time here is in seconds. A test hands in its own.
package struct ToolLimits: Equatable, Sendable {
    /// How long a tool has to answer `initialize`.
    package var firstAnswer: TimeInterval = 10
    /// How long it has to answer anything after that.
    package var answer: TimeInterval = 2
    /// This many requests in a row with no answer, and the tool is stopped.
    package var unansweredInARow = 3
    /// More lines than this in one second is too many.
    package var messagesPerSecond = 200
    /// This many such seconds in a row is a flood.
    package var floodSeconds = 5
    /// This many lines that are not messages, within `junkWindow`, and the
    /// tool is stopped.
    package var junkLines = 20
    package var junkWindow: TimeInterval = 60
    /// How much of what a tool logs is kept, in bytes.
    package var logBytes = 256 * 1024
    /// After the app says goodbye and closes the tool's input: how long
    /// before the tool is asked to end.
    package var goodbyeWait: TimeInterval = 2
    /// After that: how long before it is killed.
    package var endWait: TimeInterval = 1
    /// A tool that starts on a command is stopped after this long with
    /// nothing asked of it.
    package var idleStop: TimeInterval = 120
    /// After a crash the tool is not started again for this long. The wait
    /// doubles with each crash, up to `longestRestartWait`.
    package var firstRestartWait: TimeInterval = 1
    package var longestRestartWait: TimeInterval = 300
    /// This many crashes within `crashWindow`, and the tool stays stopped.
    package var crashesBeforeGivingUp = 3
    package var crashWindow: TimeInterval = 60
    /// How many commands may wait for a tool that is still starting.
    package var commandsHeld = 16
    /// How much the app may have written that the tool has not read yet, in
    /// bytes. Past it, the tool is not reading.
    package var unreadBytes = 4 * 1_048_576
    /// How many lines of a tool's output reach the main thread in one
    /// second, at most. A tool that writes faster waits on its pipe. It is
    /// well over `messagesPerSecond`, so a flood is still seen as one.
    package var linesHandedPerSecond = 2_000
    /// The most a tool's folder may weigh when it is added, in bytes. The
    /// folder is copied whole, on the main thread, so this is what keeps
    /// picking the wrong folder, a home folder or a project with its
    /// dependencies, from stalling the app or filling the disk.
    package var folderBytes = 256 * 1_048_576
    /// The most things it may hold: files, folders and links together.
    package var folderItems = 10_000

    package init() {}

    package static let standard = ToolLimits()
}
