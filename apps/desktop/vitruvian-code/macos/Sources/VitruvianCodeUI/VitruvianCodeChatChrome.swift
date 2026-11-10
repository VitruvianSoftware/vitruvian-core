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

import AppKit
import VitruvianCodeCore
import SwiftUI

/// What differs between the apps around the same chat: what is drawn behind
/// it, and the things only the app's own window can do. The view asks for
/// nothing else of the app it is in.
@MainActor
public struct VitruvianCodeChatChrome {
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
    /// removed in step 3c (last shipped in nexus-agent-v1.19.0), always had
    /// it, and the standalone app still offers it; an app whose drawer
    /// never did passes false.
    public var offersClearAll: Bool

    public init(backdrop: AnyView = AnyView(Color.clear),
                isEmbedded: Bool = false,
                isPinned: Binding<Bool>? = nil,
                showWindow: @escaping () -> Void = {},
                dockToNotch: (() -> Void)? = nil,
                dockToNotchHelp: String = "",
                errorScheme: String = "vitruvian-code-error",
                offersClearAll: Bool = true) {
        self.backdrop = backdrop
        self.isEmbedded = isEmbedded
        self.isPinned = isPinned
        self.showWindow = showWindow
        self.dockToNotch = dockToNotch
        self.dockToNotchHelp = dockToNotchHelp
        self.errorScheme = errorScheme
        self.offersClearAll = offersClearAll
    }
}

/// The notch's look for a chat in a window of its own: the island's dark
/// glass. Vitruvian's island draws Liquid Glass with a black shade over it,
/// near-solid at the top and thinning toward the lip, so whatever is behind
/// shows through faintly. The popped-out chat draws the same.
///
/// Before macOS 26 there is no Liquid Glass, so the system's behind-window
/// blur stands in, under the same shade. Reduce Transparency turns both off
/// and leaves plain black, as the island does. The hairline of white at 12%
/// inside the edge marks the window's shape on a dark desktop.
public struct VitruvianCodeNotchBackdrop: View {
    /// The surface's colour where nothing shows through: the island's black.
    public static let fill = Color.black
    public var cornerRadius: CGFloat

    /// Stands in for the system's Reduce Transparency setting, which a test
    /// cannot set. Nil follows the system.
    var reduceTransparencyOverride: Bool?

    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var reduceTransparency: Bool { reduceTransparencyOverride ?? systemReduceTransparency }

    public init(cornerRadius: CGFloat = VitruvianCodeQuickPromptLayout.cornerRadius) {
        self.cornerRadius = cornerRadius
    }

    init(cornerRadius: CGFloat = VitruvianCodeQuickPromptLayout.cornerRadius, reduceTransparencyOverride: Bool?) {
        self.cornerRadius = cornerRadius
        self.reduceTransparencyOverride = reduceTransparencyOverride
    }

    /// How much black lies over the glass at `location` (0 at the top, 1 at
    /// the bottom): the island's shade when fully open. Increased contrast
    /// keeps it almost solid so text stays readable.
    public static func shadeOpacity(at location: Double, increasedContrast: Bool) -> Double {
        1 - (increasedContrast ? 0.10 : 0.45) * pow(min(max(location, 0), 1), 2.5)
    }

    static func shade(increasedContrast: Bool) -> [Gradient.Stop] {
        (0...32).map { index in
            let t = Double(index) / 32
            return Gradient.Stop(color: .black.opacity(shadeOpacity(at: t, increasedContrast: increasedContrast)),
                                 location: t)
        }
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        surface(in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private func surface(in shape: RoundedRectangle) -> some View {
        if reduceTransparency {
            shape.fill(Self.fill)
        } else {
            let tint = LinearGradient(stops: Self.shade(increasedContrast: contrast == .increased),
                                      startPoint: .top, endPoint: .bottom)
            glass(in: shape).overlay(tint.clipShape(shape))
        }
    }

    @ViewBuilder
    private func glass(in shape: RoundedRectangle) -> some View {
#if compiler(>=6.2)
        if #available(macOS 26, *) {
            Color.clear
                .glassEffect(.clear, in: shape)
                .environment(\.appearsActive, true)
        } else {
            VitruvianCodeBehindWindowBlur(cornerRadius: cornerRadius)
        }
#else
        VitruvianCodeBehindWindowBlur(cornerRadius: cornerRadius)
#endif
    }
}

/// The system's dark blur of what is behind the window, for systems without
/// Liquid Glass. The layer is rounded itself: SwiftUI's clip shape does not
/// clip a behind-window material, which would leave a square edge.
private struct VitruvianCodeBehindWindowBlur: NSViewRepresentable {
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        view.wantsLayer = true
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
    }
}
