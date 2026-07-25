# Workona Architecture Analysis

## 1. Runtime Architecture

Workona utilizes a **Hybrid Architecture** that splits responsibilities between a Remote Web
Application and a Local Browser Extension. This differs fundamentally from Tabula's current
**Local-Only** approach.

### Workona (Hybrid)

- **UI / Controller**: Hosted at `https://workona.com`.
- **Runtime (Extension)**: A background service worker that acts as a bridge between the Web App and
  the Chrome APIs (`tabs`, `windows`, `management`).
- **Communication**: The Web App cannot access Chrome APIs directly. It likely uses
  `externally_connectable` or content scripts to message the Background Script.

### Tabula (Local)

- **UI / Controller**: Hosted locally at `chrome-extension://[id]/dashboard.html`.
- **Runtime (Extension)**: Background service worker.
- **Communication**: Direct usage of `chrome.*` APIs from the Dashboard (since it's an extension
  page) and `chrome.runtime.sendMessage` for coordination.

## 2. Multi-Window Workspace Support

Workona supports running different workspaces in different windows by treating the **Window** as a
container for a **Workspace**.

### The Mechanism

1.  **Window-to-Workspace Mapping**: Workona likely maintains a state map in the background script:

    ```typescript
    interface State {
      activeWorkspaces: {
        [windowId: number]: string; // WindowID -> WorkspaceID
      };
    }
    ```

2.  **State Persistence (The "Secret Sauce")**:
    - Workona's "Dashboard" is a tab (often pinned) in the window.
    - This tab's URL contains the Workspace ID: `https://workona.com/0/[workspaceId]/`.
    - **Crash/Restart Recovery**: When Chrome restarts, it restores the session. The "Dashboard" tab
      is restored with its specific URL.
    - **Initialization**: When the Dashboard tab loads, it parses its own URL, extracts the
      `workspaceId`, and immediately tells the Background Script: _"I am the controller for Window
      [X], and I am active on Workspace [Y]"_.
    - This allows Workona to seamlessly restore the correct workspace for each window without
      needing to persist fragile `windowId`s (which change on restart) to disk.

3.  **Behavior**:
    - **Focus Switching**: When a user focuses a window, the Extension detects the
      `window.onFocusChanged` event. It looks up the associated Workspace for that window and
      updates its "Active Workspace" state, ensuring that any new tabs created (e.g., via `Cmd+T`)
      might optionally be filed into that workspace.
    - **Exclusivity**: While Workona allows the same workspace to be open in multiple windows, it
      treats them as synchronized instances.

## 3. Comparison & Recommendations for Tabula

### Current Tabula Approach

- **Dashboard**: `chrome-extension://[id]/dashboard.html`.
- **State**: Likely determined by looking up the last active workspace in `storage`.

### Path to Multi-Window Support (Like Workona)

To support different spaces in valid browser windows, Tabula should adopt the **URL-as-State**
pattern, even while remaining a local extension.

#### Proposed Implementation:

1.  **Route-Based Dashboard**: Change the dashboard URL structure to include the Space ID.
    - Current: `.../dashboard.html`
    - Proposed: `.../dashboard.html#/space/[spaceId]` or `.../dashboard.html?spaceId=[spaceId]`

2.  **Window Hydration**: When a user wants to "Open Space in New Window":
    1.  Tabula creates a new Chrome Window.
    2.  In that window, it opens (and maybe pins) `.../dashboard.html?spaceId=TARGET_ID`.
    3.  When that Dashboard boots, it boots directly into that Space.
    4.  It registers itself with the Background Service:
        `TabService.registerWindow(currentWindowId, spaceId)`.

3.  **Persistence**: By relying on Chrome's native Session Restore to restore the Dashboard URL,
    Tabula gets robust window-to-space binding for free. If the browser crashes and reopens, the
    dashboard tab reloads with `?spaceId=xyz`, and re-registers the binding.

## 4. Strategic Comparison: Hybrid (Workona) vs. Local (Tabula)

Is there more value in Workona's approach? It depends on the optimization vector.

| Feature Vector            | Hybrid (Workona)                                                                                                      | Local-First (Tabula)                                                            | Winner for Tabula? |
| :------------------------ | :-------------------------------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------ | :----------------- |
| **Updates & Velocity**    | **Instant**. Logic is on the server; fixes deploy in minutes over-the-wire.                                           | **Slow**. Requires Chrome Web Store review (24h-48h). Critical bugs stick.      | Hybrid             |
| **Offline Reliability**   | **Poor**. Requires internet to load the UI shell initially. Caching helps but is flaky.                               | **Perfect**. The app is on the device. Works on planes/trains with 0ms latency. | **Local**          |
| **Security & Privacy**    | **Lower Isolation**. Code runs on `workona.com`. Theoretical XSS can impact browser. Data feels "server-owned".       | **Strict Isolation**. Code runs in extension context. Data is local-encrypted.  | **Local**          |
| **Shareabilty**           | **High**. Can send `workona.com/space/xyz` to a colleague. If they have the extension, it opens. If not, signup flow. | **Low**. Cannot "link" to a `chrome-extension://` URL from Slack.               | Hybrid             |
| **3rd Party Integration** | **Easier**. OAuth callbacks (Google Drive, Slack) redirect to `workona.com`.                                          | **Harder**. OAuth requires `identity` API or popup tricks.                      | Hybrid             |
| **Latency**               | **Network**. UI load depends on ISP.                                                                                  | **Native**. UI load is disk-speed.                                              | **Local**          |

### Why Tabula should stay Local-First for now

While the Hybrid approach offers incredible distribution benefits (instant updates, shareable
links), it compromises the core **Privacy** and **Performance** promise of Tabula.

- **Privacy**: Users trust a "Local" extension more than a "Cloud Service" regarding their browsing
  history.
- **Performance**: Tab management must be instant. Waiting for a spinner to load your tab list is a
  non-starter for power users.

## 5. Implementation Strategy: The "Relay Pattern"

To achieve Workona-levels of **shareability** and **integration** without sacrificing
**local-first** benefits, we should implement the **Relay Page Pattern**.

### The Concept

We create a lightweight, public-facing web page (e.g., `https://tabula.com/s/[space-id]`) that
serves as a "Relay" or "Handshake" point. This page does not contain the complex application logic
(which stays in the extension).

### The Flow: Sharing a Space

1.  **User A** clicks "Share Space" in the Tabula Extension.
2.  Tabula generates a public link `https://tabula.com/s/xyz-123` and syncs the space configuration
    (JSON) to the backend.
3.  **User A** sends this link to **User B** on Slack.
4.  **User B** clicks the link.
5.  **The Relay Page Loads**:
    - **Scenario 1: User B has Tabula installed.**
      - The Page javascript uses
        `chrome.runtime.sendMessage(EXTENSION_ID, { type: 'IMPORT_SPACE', id: 'xyz-123' })`.
      - The Extension receives the message (via `externally_connectable`).
      - The Extension imports the space data, creates a new local entry, and opens
        `chrome-extension://.../dashboard.html?spaceId=xyz-123`.
      - **Result:** Seamless transition from Web Link -> Local App.
    - **Scenario 2: User B does NOT have Tabula.**
      - The `sendMessage` call fails (or returns undefined).
      - The Relay Page renders a "Read-Only" preview of the space (tabs list) rendered by the
        server.
      - A prominent "Install Tabula to Open" button is displayed.
      - **Result:** Viral growth loop similar to Workona/Notion.

### Can we get "All Benefits" without Drawbacks?

Mostly, yes. Here is how we bridge the gap:

| Workona Benefit        | Tabula "Local++" Solution                                                                                                                                                                          |
| :--------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Shareable URLs**     | **Relay Pages**: Use `tabula.com/s/xyz` as a trampoline into the extension.                                                                                                                        |
| **Cloud Integrations** | **Auth Proxy**: Use `tabula.com` to handle OAuth handshakes, then pass tokens to the extension via the Relay method.                                                                               |
| **Instant Updates**    | **Feature Flags**: We cannot hot-swap code (illegal in MV3), but we can fetch a "Remote Config" JSON on boot. This allows us to toggle features or update heuristic rules without a store release. |
| **Cross-Device Sync**  | **Real-Time Sync**: Use our existing SSE/Redis architecture. The "Relay Page" is just a deep-link entry point; the actual data sync happens via the standard pipeline.                             |

### Conclusion

By implementing the **Relay Pattern**, Tabula can match Workona's shareability and viral growth
loops while retaining the superior performance, offline-capability, and security profile of a true
Local-First application. We do not need to rewrite the app as a website to get shareable links.
