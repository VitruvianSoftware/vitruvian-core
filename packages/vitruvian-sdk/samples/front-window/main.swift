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

// A tool that reads the title of the window in front by asking macOS
// itself, through Accessibility. It does not ask the app for it, and the
// protocol has no message for it. It shows that a tool is an ordinary
// program with every permission of whoever started it: started by
// Vitruvian, it reads the title with no prompt of its own once Vitruvian
// has Accessibility. Started from a terminal that lacks Accessibility, it
// says so and reads nothing.
//
// Public API only. It never asks macOS to show a permission prompt.

import ApplicationServices
import VitruvianToolKit

/// One attribute of an Accessibility element; nil when macOS gave none.
func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

/// The value as an element; nil when it is something else.
func element(_ value: CFTypeRef?) -> AXUIElement? {
    guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    // The cast cannot fail once the type is known to be this one.
    return (value as! AXUIElement)
}

/// The app in front, as an Accessibility element.
func frontApp() -> AXUIElement? {
    let system = AXUIElementCreateSystemWide()
    // An app that does not answer costs one second, not the command's two.
    AXUIElementSetMessagingTimeout(system, 1)
    if let app = element(attribute(system, kAXFocusedApplicationAttribute)) { return app }
    // macOS does not always answer that. The list of windows says whose
    // window is in front, and that much of it needs no permission.
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
    let front = (windows as? [[String: Any]] ?? []).first { $0[kCGWindowLayer as String] as? Int == 0 }
    guard let pid = front?[kCGWindowOwnerPID as String] as? pid_t else { return nil }
    return AXUIElementCreateApplication(pid)
}

/// Why the title could not be read. Without Accessibility, that is why.
func refused(_ why: String) -> CommandRefused {
    CommandRefused(AXIsProcessTrusted() ? why : "Accessibility is not granted to the program that started this tool")
}

func frontWindowTitle() throws -> String {
    guard let front = frontApp() else { throw refused("no app is in front") }
    AXUIElementSetMessagingTimeout(front, 1)
    guard let window = element(attribute(front, kAXFocusedWindowAttribute)),
          let title = attribute(window, kAXTitleAttribute) as? String
    else { throw refused("the app in front has no window with a title") }
    return title
}

let tool = Tool(version: "0.1.0")

tool.command("showTitle") { app in
    let title = try frontWindowTitle()
    try app.showMessage(title.isEmpty ? "The window in front has no title" : title, icon: "macwindow")
}

tool.run()
