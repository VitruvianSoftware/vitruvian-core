// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import ApplicationServices
import VitruvianCore

/// One element of an app's menu bar, as the walk meets it. Each part is
/// asked for only when the walk gets there: reading an element is a round
/// trip to the other app.
package struct MenuItemProbe {
    /// The element's key equivalent, and whether it can be pressed.
    package let read: () -> (commandCharacter: String?, modifierMask: UInt32?, isEnabled: Bool)
    package let children: () -> [MenuItemProbe]
    /// Presses the element. False when the app refused.
    package let press: () -> Bool

    package init(read: @escaping () -> (commandCharacter: String?, modifierMask: UInt32?, isEnabled: Bool),
                 children: @escaping () -> [MenuItemProbe],
                 press: @escaping () -> Bool) {
        self.read = read
        self.children = children
        self.press = press
    }
}

/// Presses a command in the front app's own menus. The command is found by
/// its key equivalent, never by its title, which changes with the language.
/// Main thread only, like the Accessibility calls under it.
@MainActor
package final class FrontAppMenu {
    /// What the walk reaches. The app's is the workspace and Accessibility.
    /// A test passes an app and a menu bar made of values.
    package struct Environment {
        /// The process in front, or nil when there is none.
        package var frontmostApp: () -> pid_t?
        /// That process's menu bar, or nil when it gives none.
        package var menuBar: (pid_t) -> MenuItemProbe?

        package init(frontmostApp: @escaping () -> pid_t?, menuBar: @escaping (pid_t) -> MenuItemProbe?) {
            self.frontmostApp = frontmostApp
            self.menuBar = menuBar
        }

        @MainActor package static let live = Environment(
            frontmostApp: { NSWorkspace.shared.frontmostApplication?.processIdentifier },
            menuBar: { app in
                let application = AXUIElementCreateApplication(app)
                // A busy target must not hold the main thread for AX's default
                // multi-second timeout; every traversed element gets the same bound.
                AXUIElementSetMessagingTimeout(application, FrontAppMenu.elementTimeout)
                guard let menuBar: AXUIElement = FrontAppMenu.attribute(kAXMenuBarAttribute, from: application)
                else { return nil }
                return FrontAppMenu.probe(menuBar)
            })

        /// No app is ever in front. For tests of other capabilities.
        package static var inert: Environment {
            Environment(frontmostApp: { nil }, menuBar: { _ in nil })
        }
    }

    /// How long one element may take to answer, in seconds.
    nonisolated package static let elementTimeout: Float = 0.35
    /// How many elements one walk reads at most, so a pathological menu bar
    /// cannot stall a press.
    nonisolated package static let elementCap = 600
    /// Depth 3 is a direct item of a top level menu (bar, bar item, menu,
    /// item), where every app keeps its paste commands; anything deeper is
    /// out of reach on purpose.
    nonisolated package static let depthLimit = 3
    /// How many apps without the item are remembered before the list starts
    /// again.
    nonisolated package static let rememberedApps = 64

    /// An app, and what was looked for in it and not found.
    private struct Absent: Hashable {
        let app: pid_t
        let equivalents: [MenuKeyEquivalent]
    }

    private let environment: Environment
    /// Apps known to carry no such item, so their menu bar is not re-walked
    /// on every single press. An app gets another chance after a relaunch
    /// (the pid changes): menus rarely grow the item mid-run, and the
    /// caller's fallback covers it if they do.
    private var absent: Set<Absent> = []

    package init(environment: Environment) {
        self.environment = environment
    }

    /// Presses the first enabled item in the front app's menus that has one
    /// of `equivalents`. False when there is no such item, or the app
    /// refused the press.
    package func pressItem(matching equivalents: [MenuKeyEquivalent]) -> Bool {
        guard let app = environment.frontmostApp() else { return false }
        let key = Absent(app: app, equivalents: equivalents)
        if absent.contains(key) { return false }
        guard let menuBar = environment.menuBar(app) else { return false }
        var visited = 0
        guard let item = Self.find(equivalents, in: menuBar, depth: 0, visited: &visited) else {
            absent.insert(key)
            if absent.count > Self.rememberedApps { absent.removeAll() }
            return false
        }
        return item.press()
    }

    private static func find(_ equivalents: [MenuKeyEquivalent], in node: MenuItemProbe, depth: Int,
                             visited: inout Int) -> MenuItemProbe? {
        guard depth <= depthLimit, visited < elementCap else { return nil }
        visited += 1
        let item = node.read()
        let wanted = equivalents.contains {
            $0.matches(commandCharacter: item.commandCharacter, modifierMask: item.modifierMask)
        }
        if wanted, item.isEnabled { return node }

        guard depth < depthLimit else { return nil }
        for child in node.children() {
            if let match = find(equivalents, in: child, depth: depth + 1, visited: &visited) {
                return match
            }
        }
        return nil
    }

    /// An element as the walk reads it. The timeout is set when the element
    /// is read, as it always was, and its children are not looked at until
    /// the walk asks.
    nonisolated private static func probe(_ element: AXUIElement) -> MenuItemProbe {
        MenuItemProbe(
            read: {
                AXUIElementSetMessagingTimeout(element, elementTimeout)
                let command: String? = attribute(kAXMenuItemCmdCharAttribute, from: element)
                let modifiers: NSNumber? = attribute(kAXMenuItemCmdModifiersAttribute, from: element)
                let enabled: NSNumber? = attribute(kAXEnabledAttribute, from: element)
                return (command, modifiers?.uint32Value, enabled?.boolValue != false)
            },
            children: {
                let children: [AXUIElement] = attribute(kAXChildrenAttribute, from: element) ?? []
                return children.map { probe($0) }
            },
            press: { AXUIElementPerformAction(element, kAXPressAction as CFString) == .success })
    }

    nonisolated private static func attribute<T>(_ name: String, from element: AXUIElement) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value as? T
    }
}
