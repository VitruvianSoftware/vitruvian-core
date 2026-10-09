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

/// What differs between the apps around the same chat: what is drawn behind
/// it, and the things only the app's own window can do. The view asks for
/// nothing else of the app it is in.
@MainActor
public struct NexusAgentChatChrome {
    /// Drawn behind the floating chat. Vitruvian passes its own backdrop.
    public var backdrop: AnyView
    /// True inside Vitruvian's notch: no backdrop, the drawer always open.
    public var isEmbedded: Bool
    /// The pin button's state; nil hides the button.
    public var isPinned: Binding<Bool>?
    /// Brings the chat window forward again (after the folder picker closes).
    public var showWindow: () -> Void
    /// The dock-into-notch button's action and its tooltip; nil hides the button.
    public var dockToNotch: (() -> Void)?
    public var dockToNotchHelp: String
    /// The URL scheme the diagram web view uses to report an error.
    public var errorScheme: String
    /// Whether the sessions drawer has the button that deletes every
    /// conversation of the working folder. The standalone app's own chat,
    /// removed in step 3c (last shipped in nexus-agent 1.19.0), always had
    /// it, and the standalone app still offers it; an app whose drawer
    /// never did passes false.
    public var offersClearAll: Bool
    /// What the top field says while the session list is open under it.
    /// What is typed there is a prompt, and Return sends it; the list has
    /// a filter field of its own. False, the default, shows the filter's
    /// words there all the same, which is what Vitruvian has always shown.
    /// True keeps the prompt's own placeholder.
    public var keepsPromptPlaceholderOverSessions: Bool

    public init(backdrop: AnyView = AnyView(Color.clear),
                isEmbedded: Bool = false,
                isPinned: Binding<Bool>? = nil,
                showWindow: @escaping () -> Void = {},
                dockToNotch: (() -> Void)? = nil,
                dockToNotchHelp: String = "",
                errorScheme: String = "nexus-agent-error",
                offersClearAll: Bool = true,
                keepsPromptPlaceholderOverSessions: Bool = false) {
        self.backdrop = backdrop
        self.isEmbedded = isEmbedded
        self.isPinned = isPinned
        self.showWindow = showWindow
        self.dockToNotch = dockToNotch
        self.dockToNotchHelp = dockToNotchHelp
        self.errorScheme = errorScheme
        self.offersClearAll = offersClearAll
        self.keepsPromptPlaceholderOverSessions = keepsPromptPlaceholderOverSessions
    }
}
