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

import Foundation
import UserNotifications

// MARK: - Background Completion Notifications

/// Manages macOS system notifications for background generation completions.
/// When the user dismisses the Quick Prompt window while a generation is running,
/// this sends a notification with a preview of the result so they know it's done.
class BackgroundNotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = BackgroundNotificationManager()
    
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }
    
    /// Request notification permission. Call once on app launch.
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }
    
    /// Send a notification about a turn with a title the caller worded.
    /// The shared chat's host uses this, so that the title it posts is the
    /// one the shared, tested rule gave it. A click on it comes back to the
    /// session, as for any other.
    func notify(title: String, body: String, sessionUUID: String? = nil, sessionTitle: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = String(body.prefix(200))
        content.sound = .default
        content.categoryIdentifier = "GENERATION_COMPLETE"
        // Embed session info so click-to-reopen lands on the right session
        var info: [String: String] = [:]
        if let uuid = sessionUUID { info["sessionUUID"] = uuid }
        if let title = sessionTitle { info["sessionTitle"] = title }
        content.userInfo = info
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil  // deliver immediately
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    /// Called when the user clicks a notification — reopen the Quick Prompt window.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.notification.request.content.categoryIdentifier == "GENERATION_COMPLETE" {
            let userInfo = response.notification.request.content.userInfo
            let uuid = userInfo["sessionUUID"] as? String
            
            DispatchQueue.main.async {
                if let uuid = uuid {
                    // Back to the conversation the turn was in: the one the
                    // chat still holds, or resumed from the list.
                    QuickPromptWindowController.shared.resumeSession(uuid: uuid)
                } else {
                    // A turn with no conversation to name (a provider's own
                    // command): the chat still holds it. With nothing in
                    // the chat, the recent sessions open instead.
                    QuickPromptWindowController.shared.show(startExpanded: true)
                }
            }
        }
        completionHandler()
    }
    
    /// Show notifications even when app is in foreground (user might be in the menu bar view).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}
