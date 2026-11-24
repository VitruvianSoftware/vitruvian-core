// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI
import VitruvianCourierCore

// MARK: - Layout

/// Which part of the composer's input row a view is, for `ComposerToolRowLayout`.
enum ComposerRowRole: Hashable {
    case plus
    case row
    case field
}

struct ComposerRowRoleKey: LayoutValueKey {
    static let defaultValue: ComposerRowRole = .field
}

/// Lays out `+`, the inline tool row and the message field in one line.
///
/// The `+` (it becomes ✕) and the field keep their room first: the field never gets narrower than
/// `ComposerToolRowMetrics.fieldMinimumWidth` of text (100 pt in a very narrow pane) plus its own buttons, so Send always stays visible. The
/// tool row gets what is left, up to its natural width, and scrolls inside it. `reveal` (0 closed, 1 open) is
/// animatable, so opening slides the row out and glides the field aside in one motion.
struct ComposerToolRowLayout: Layout {
    var reveal: CGFloat
    /// The row's full width: its buttons and padding.
    var rowNatural: CGFloat
    var gap: CGFloat
    var rowHeight: CGFloat

    var animatableData: CGFloat {
        get { reveal }
        set { reveal = newValue }
    }

    private struct Parts {
        var plus: LayoutSubview?
        var row: LayoutSubview?
        var field: LayoutSubview?
    }

    private struct Plan {
        var plusSize: CGSize = .zero
        var rowGap: CGFloat = 0
        var rowWidth: CGFloat = 0
        var fieldGap: CGFloat = 0
        var fieldWidth: CGFloat = 0
        var fieldSize: CGSize = .zero
        var height: CGFloat = 0
    }

    private func parts(_ subviews: Subviews) -> Parts {
        var found = Parts()
        for subview in subviews {
            switch subview[ComposerRowRoleKey.self] {
            case .plus: found.plus = subview
            case .row: found.row = subview
            case .field: found.field = subview
            }
        }
        return found
    }

    private func plan(width requested: CGFloat?, height: CGFloat?, _ subviews: Subviews) -> Plan {
        let found = parts(subviews)
        var plan = Plan()
        plan.plusSize = found.plus?.sizeThatFits(.unspecified) ?? .zero
        let hasLeading = found.plus != nil
        let hasRow = hasLeading && found.row != nil
        plan.fieldGap = hasLeading ? gap : 0
        let fieldMinimum = found.field?.sizeThatFits(ProposedViewSize(width: 0, height: nil)).width ?? 0

        let width: CGFloat
        if let requested {
            width = requested
        } else {
            let fieldIdeal = found.field?.sizeThatFits(.unspecified).width ?? 0
            width = plan.plusSize.width + (hasRow ? (gap + rowNatural) * reveal : 0) + plan.fieldGap + fieldIdeal
        }

        if hasRow {
            let target = ComposerToolRowMetrics.rowWidth(
                natural: rowNatural,
                container: width,
                plus: plan.plusSize.width,
                fieldMinimum: fieldMinimum,
                gap: gap
            )
            plan.rowWidth = target * reveal
            plan.rowGap = target > 0 ? gap * reveal : 0
        }
        plan.fieldWidth = max(0, width - plan.plusSize.width - plan.rowGap - plan.rowWidth - plan.fieldGap)
        if let field = found.field {
            plan.fieldSize = field.sizeThatFits(ProposedViewSize(width: plan.fieldWidth, height: height))
        }
        plan.height = max(plan.plusSize.height, plan.fieldSize.height)
        return plan
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let plan = plan(width: proposal.width, height: proposal.height, subviews)
        let width = proposal.width
            ?? (plan.plusSize.width + plan.rowGap + plan.rowWidth + plan.fieldGap + plan.fieldWidth)
        return CGSize(width: width, height: plan.height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let found = parts(subviews)
        let plan = plan(width: bounds.width, height: bounds.height, subviews)
        var x = bounds.minX
        if let plus = found.plus {
            plus.place(
                at: CGPoint(x: x, y: bounds.maxY - plan.plusSize.height),
                anchor: .topLeading,
                proposal: ProposedViewSize(plan.plusSize)
            )
            x += plan.plusSize.width
        }
        if let row = found.row, found.plus != nil {
            x += plan.rowGap
            row.place(
                at: CGPoint(x: x, y: bounds.maxY - rowHeight),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: plan.rowWidth, height: rowHeight)
            )
            x += plan.rowWidth
        }
        x += plan.fieldGap
        found.field?.place(
            at: CGPoint(x: x, y: bounds.maxY - plan.fieldSize.height),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: plan.fieldWidth, height: plan.fieldSize.height)
        )
    }
}

// MARK: - The row: scrolls, with faded edges

/// The tool row's slot: clipped to the width the layout gives it, scrolling sideways when the buttons do not
/// fit, with the edges faded so a cut-off button reads as "more this way".
struct ComposerToolRowSlot<Content: View>: View {
    let isOpen: Bool
    let isMounted: Bool
    let natural: CGFloat
    let height: CGFloat
    let fade: Animation
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack(alignment: .leading) {
            if isMounted {
                GeometryReader { geometry in
                    let overflows = geometry.size.width > 40 && geometry.size.width < natural - 0.5
                    ScrollView(.horizontal, showsIndicators: false) {
                        content()
                            .frame(minWidth: natural, alignment: .leading)
                    }
                    .mask(EdgeFadeMask(isFaded: overflows))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: height)
        .clipped()
        .opacity(isOpen ? 1 : 0)
        .animation(fade, value: isOpen)
        .allowsHitTesting(isOpen)
        .accessibilityHidden(!isOpen)
    }
}

private struct EdgeFadeMask: View {
    let isFaded: Bool

    var body: some View {
        if isFaded {
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 10)
                Rectangle().fill(.black)
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 10)
            }
        } else {
            Rectangle().fill(.black)
        }
    }
}

// MARK: - Keyboard: tools are real key views

/// An icon button for the tool row that is a genuine AppKit key view. SwiftUI buttons only join the Tab loop
/// when "Keyboard navigation" is on in System Settings; these always do, so the tools are reachable by Tab.
/// Space or Return presses it; Escape closes the row from here.
struct ComposerToolKeyButton: NSViewRepresentable {
    let symbolName: String
    let tooltip: String
    var tooltipShortcut: String? = nil
    var tooltipDetail: String? = nil
    let accessibilityTitle: String
    let accessibilityID: String
    var isEnabled: Bool = true
    /// Why the tool can't be used yet. The button stays focusable and keeps its tooltip, and click does nothing.
    var disabledHint: String?
    let height: CGFloat
    /// True when this is the first tool and the row was just opened by keyboard, so it should take focus.
    var wantsFocus = false
    var onFocused: () -> Void = {}
    var menuProvider: (() -> NSMenu)?
    let onEscape: () -> Void
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ComposerToolNSButton {
        let button = ComposerToolNSButton(frame: NSRect(x: 0, y: 0, width: 28, height: height))
        button.target = context.coordinator
        button.action = #selector(Coordinator.pressed)
        return button
    }

    func updateNSView(_ button: ComposerToolNSButton, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        button.isEnabled = isEnabled || disabledHint != nil
        button.alphaValue = isEnabled ? 1 : 0.42
        button.toolTip = nil
        button.reduceMotion = accessibilityReduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        button.updateTooltip(
            CourierTooltipContent(
                title: tooltip,
                shortcut: tooltipShortcut,
                detail: tooltipDetail ?? disabledHint,
                edge: .top
            )
        )
        button.setAccessibilityLabel(accessibilityTitle)
        button.setAccessibilityIdentifier(accessibilityID)
        button.setAccessibilityHelp(disabledHint)
        button.onEscape = onEscape
        if wantsFocus {
            DispatchQueue.main.async { [weak button, onFocused] in
                guard let button, let window = button.window else { return }
                window.makeFirstResponder(button)
                onFocused()
            }
        }
    }

    func sizeThatFits(_: ProposedViewSize, nsView _: ComposerToolNSButton, context _: Context) -> CGSize? {
        CGSize(width: ComposerToolRowMetrics.toolButtonWidth, height: height)
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: ComposerToolKeyButton?

        @objc func pressed(_ sender: NSButton) {
            guard let parent else { return }
            guard parent.isEnabled else { return }
            if let menuProvider = parent.menuProvider {
                menuProvider().popUp(
                    positioning: nil,
                    at: NSPoint(x: 0, y: sender.isFlipped ? sender.bounds.maxY : 0),
                    in: sender
                )
            } else {
                parent.action()
            }
        }
    }
}

final class ComposerToolNSButton: NSButton {
    var onEscape: (() -> Void)?
    var reduceMotion = false
    private let tooltipID = UUID().uuidString
    private var tooltipContent: CourierTooltipContent?
    private var isPointerInside = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        bezelStyle = .regularSquare
        contentTintColor = .secondaryLabelColor
        focusRingType = .exterior
        setButtonType(.momentaryChange)
        wantsLayer = true
        layer?.cornerRadius = 6
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError("init(coder:) is not used") }

    func updateTooltip(_ content: CourierTooltipContent) {
        tooltipContent = content
        if isPointerInside {
            CourierTooltipController.shared.updateContentIfActive(
                id: tooltipID,
                content: content,
                anchorView: self,
                reduceMotion: reduceMotion
            )
        }
    }

    override var acceptsFirstResponder: Bool { isEnabled }
    override var canBecomeKeyView: Bool { isEnabled && !isHiddenOrHasHiddenAncestor && window != nil }
    override var focusRingMaskBounds: NSRect { bounds.insetBy(dx: 0, dy: max(0, (bounds.height - 28) / 2)) }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: focusRingMaskBounds, xRadius: 6, yRadius: 6).fill()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onEscape?()
        case 36, 49, 76: performClick(nil)
        default: super.keyDown(with: event)
        }
    }

    override func cancelOperation(_: Any?) { onEscape?() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(
            NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                           owner: self, userInfo: nil))
    }

    override func mouseDown(with event: NSEvent) {
        CourierTooltipController.shared.dismiss(preserveWarmup: false)
        super.mouseDown(with: event)
    }

    override func mouseEntered(with _: NSEvent) {
        isPointerInside = true
        setHovering(true)
        if let tooltipContent {
            CourierTooltipController.shared.hoverEntered(
                id: tooltipID,
                content: tooltipContent,
                anchorView: self,
                reduceMotion: reduceMotion
            )
        }
    }

    override func mouseExited(with _: NSEvent) {
        isPointerInside = false
        setHovering(false)
        CourierTooltipController.shared.hoverExited(id: tooltipID, reduceMotion: reduceMotion)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, isPointerInside {
            isPointerInside = false
            setHovering(false)
            CourierTooltipController.shared.hoverExited(id: tooltipID, reduceMotion: reduceMotion)
        }
        super.viewWillMove(toWindow: newWindow)
    }

    private func setHovering(_ hovering: Bool) {
        let fill = hovering && isEnabled ? NSColor.labelColor.withAlphaComponent(0.08) : .clear
        let duration = HoverFillMotion.animationDuration(
            reduceMotion: reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        effectiveAppearance.performAsCurrentDrawingAppearance {
            guard let layer else { return }
            let targetColor = fill.cgColor
            if duration > 0 {
                let animation = CABasicAnimation(keyPath: "backgroundColor")
                animation.fromValue = layer.presentation()?.backgroundColor ?? layer.backgroundColor ?? NSColor.clear.cgColor
                animation.toValue = targetColor
                animation.duration = duration
                animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                layer.add(animation, forKey: "hoverFill")
            } else {
                layer.removeAnimation(forKey: "hoverFill")
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.backgroundColor = targetColor
            CATransaction.commit()
        }
    }
}

/// Puts the SwiftUI `+` button in the Tab loop: an invisible AppKit key view behind it that takes focus, draws
/// the focus ring, and answers Space or Return (open or close) and Escape. The mouse still goes to the button.
struct ComposerKeyProxy: NSViewRepresentable {
    let accessibilityID: String
    let isCircle: Bool
    let onActivate: () -> Void
    let onEscape: () -> Void

    func makeNSView(context _: Context) -> ComposerKeyProxyButton {
        ComposerKeyProxyButton(frame: .zero)
    }

    func updateNSView(_ proxy: ComposerKeyProxyButton, context _: Context) {
        proxy.onActivate = onActivate
        proxy.onEscape = onEscape
        proxy.isCircle = isCircle
        proxy.setAccessibilityIdentifier(accessibilityID + ".key")
    }
}

final class ComposerKeyProxyButton: NSButton {
    var onActivate: (() -> Void)?
    var onEscape: (() -> Void)?
    var isCircle = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        title = ""
        focusRingType = .exterior
        setAccessibilityElement(false)
        target = self
        action = #selector(activate)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func activate() { onActivate?() }

    override func hitTest(_: NSPoint) -> NSView? { nil }
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { !isHiddenOrHasHiddenAncestor && window != nil }
    override var focusRingMaskBounds: NSRect { bounds }

    override func drawFocusRingMask() {
        if isCircle {
            NSBezierPath(ovalIn: bounds).fill()
        } else {
            NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: max(0, (bounds.height - 28) / 2)),
                         xRadius: 6, yRadius: 6).fill()
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onEscape?()
        case 36, 49, 76: onActivate?()
        default: super.keyDown(with: event)
        }
    }

    override func cancelOperation(_: Any?) { onEscape?() }
}

/// An `NSMenuItem` that runs a closure.
final class ComposerClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func fire() { handler() }
}

/// With glass, the open tool row sits in its own glass pill; without, it is bare.
struct ToolRowSurface: ViewModifier {
    let isFloating: Bool
    let isMounted: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isFloating, isMounted {
            content.courierSurface(.composerToolRow)
        } else {
            content
        }
    }
}
