// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation

/// A menu item's key equivalent, as Accessibility reports it: the character,
/// and a mask of the modifiers that go with Command. In the mask 1 is Shift,
/// 2 is Option and 4 is Control; 0 is Command alone.
///
/// It is a plain value, so a tool can tell the host which items it would
/// press without the host knowing the tool.
package struct MenuKeyEquivalent: Hashable, Sendable {
    package let character: String
    package let modifierMask: UInt32

    package init(character: String, modifierMask: UInt32) {
        self.character = character
        self.modifierMask = modifierMask
    }

    /// Whether a menu item that reports this character and this mask has
    /// this key equivalent. The character is compared without case. The
    /// mask must match exactly: an item with one modifier more is another
    /// command.
    package func matches(commandCharacter: String?, modifierMask: UInt32?) -> Bool {
        commandCharacter?.uppercased() == character.uppercased() && modifierMask == self.modifierMask
    }
}
