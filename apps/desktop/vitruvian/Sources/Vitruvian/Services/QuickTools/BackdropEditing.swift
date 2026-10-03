// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import VitruvianCore

/// What the shared background picker needs from whichever editor is showing
/// it. Both editors keep the same BackdropStyle and the same saved list, so a
/// look built in one is a look the other already understands.
protocol BackdropEditing: ObservableObject {
    var backdropStyle: ScreenshotSupport.BackdropStyle { get set }
    var backdropPresets: [ScreenshotSupport.BackdropStyle] { get }
    var showsBackdrop: Bool { get }
    func saveCurrentBackdropAsPreset()
    func removeBackdropPreset(at index: Int)
}
