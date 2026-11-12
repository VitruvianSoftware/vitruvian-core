// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

/// Whether the island's window takes the mouse. The island asks; Mission
/// Control and a hide that is settling each hold the window click-through for
/// a while, and the island's latest ask is kept for when they end.
/// `NotchWindowHost` applies what each step returns to its panel.
package struct NotchWindowInputPolicy: Equatable {
    /// Mission Control hides the island.
    package private(set) var concealed = false
    /// What the island last asked for while concealed, for when Mission Control ends.
    package private(set) var askedWhileConcealed = false
    /// The island is on its way out and already releases the menu bar below it.
    package private(set) var hidesWhenSettled = false
    /// What the island last asked for before its hide began, for the next reveal.
    package private(set) var askedBeforeHide: Bool?
    /// The island fades back in after Mission Control.
    package private(set) var restoring = false

    package init() {}

    /// The island asks to ignore the mouse, or to take it. Returns whether the
    /// panel ignores it.
    package mutating func ask(ignored: Bool) -> Bool {
        // Capture controls can change their click-through policy while the
        // island is concealed or on its way out. Keep that policy for restore.
        if concealed { askedWhileConcealed = ignored }
        if askedBeforeHide != nil { askedBeforeHide = ignored }
        return ignored || concealed || hidesWhenSettled
    }

    /// The island presents, hiding as it settles or not, from a panel that
    /// ignores the mouse as given. Returns whether the panel ignores it.
    package mutating func present(hidingWhenSettled hiding: Bool, panelIgnores: Bool) -> Bool {
        hidesWhenSettled = hiding
        var ignores = panelIgnores
        if hiding {
            if askedBeforeHide == nil { askedBeforeHide = concealed ? askedWhileConcealed : panelIgnores }
            // The departing surface must already release the menu bar below it.
            ignores = true
        } else if let previous = askedBeforeHide {
            ignores = previous
            askedBeforeHide = nil
        }
        return ignores || concealed
    }

    /// Mission Control hides the island, whose panel ignores the mouse as
    /// given. Returns whether the panel ignores it: it always does.
    package mutating func conceal(panelIgnores: Bool) -> Bool {
        if !concealed {
            askedWhileConcealed = askedBeforeHide ?? panelIgnores
            concealed = true
        }
        return true
    }

    /// Mission Control ends. A visible island fades back in until
    /// `finishRestore()`. Returns whether the panel ignores the mouse.
    package mutating func restore(panelVisible: Bool) -> Bool {
        concealed = false
        if panelVisible { restoring = true }
        return hidesWhenSettled ? true : askedWhileConcealed
    }

    /// The fade back in has finished.
    package mutating func finishRestore() {
        restoring = false
    }
}
