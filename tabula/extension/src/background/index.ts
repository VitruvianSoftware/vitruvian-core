/**
 * Copyright (c) 2026 VitruvianSoftware
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

/**
 * Background service worker for Tabula extension
 * Handles tab management, sync, and background tasks
 */

import { StorageService } from "../services/storage";
import { TabService } from "../services/tabs";
import { SyncService } from "../services/sync";
import {
  clearWindowOwnership,
  clearAllWindowOwnership,
} from "../services/windowOwnership";
// import { WorkspaceService } from '../services/workspace';

// eslint-disable-next-line @typescript-eslint/no-explicit-any
// let autoSaveTimeout: any = null;
// const AUTO_SAVE_DELAY = 2000; // 2 seconds debounce

// Auto-save function
// const scheduleAutoSave = async () => {
//   if (autoSaveTimeout) {
//     clearTimeout(autoSaveTimeout);
//   }

//   autoSaveTimeout = setTimeout(async () => {
//     try {
//       const activeWorkspaceId = await StorageService.getActiveWorkspaceId();
//       if (activeWorkspaceId) {
//         // Check if sync is enabled or implied for active workspace
//         // For now, we auto-save to the active workspace to mimic Workona
//         await WorkspaceService.saveCurrentTabsToWorkspace(activeWorkspaceId);
//         // eslint-disable-next-line no-console
//         console.log('Auto-saved tabs to workspace:', activeWorkspaceId);
//       }
//     } catch (error) {
//       // eslint-disable-next-line no-console
//       console.error('Auto-save failed:', error);
//     }
//   }, AUTO_SAVE_DELAY);
// };

/** One-time migration: remove any access token left on disk by older builds. */
function migrateLegacyToken(): void {
  chrome.storage.local.remove("tabula_access_token").catch(() => undefined);
}

// Listen for extension installation
chrome.runtime.onInstalled.addListener((details) => {
  // Drop any legacy on-disk access token (now stored in session storage)
  migrateLegacyToken();

  if (details.reason === "install") {
    // eslint-disable-next-line no-console
    console.log("Tabula extension installed");

    // Initialize default settings
    StorageService.getSettings().then((settings) => {
      if (!settings) {
        StorageService.saveSettings({
          autoSuspend: false,
          suspendAfterMinutes: 30,
          syncEnabled: false,
          theme: "auto",
          autoSave: true, // Default to true for Workona-like experience
          tabCloseMode: "hybrid",
          onboardingCompleted: false,
        });
      }
    });

    // Open dashboard on install
    chrome.tabs.create({
      url: "dashboard.html",
      pinned: true,
      active: true,
    });
  }

  if (details.reason === "update") {
    // eslint-disable-next-line no-console
    console.log("Tabula extension updated");
  }
});

// Auto-suspend is driven by the 'autoSuspendCheck' alarm below — NOT setTimeout.
// MV3 service workers are killed after ~30s idle, so a 30-minute setTimeout
// would never fire. The alarm-based scan survives worker termination.

/**
 * Scan inactive tabs and suspend those idle longer than the configured
 * threshold. Uses chrome.tabs.lastAccessed (Chrome 121+) to measure idleness.
 */
async function runAutoSuspendScan(): Promise<void> {
  const settings = await StorageService.getSettings();
  if (!settings?.autoSuspend) return;

  const thresholdMs = (settings.suspendAfterMinutes || 30) * 60 * 1000;
  const now = Date.now();
  const tabs = await chrome.tabs.query({ active: false, pinned: false });

  await Promise.all(
    tabs.map(async (tab) => {
      if (tab.id == null || tab.discarded) return;
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const lastAccessed = (tab as any).lastAccessed as number | undefined;
      if (lastAccessed != null && now - lastAccessed < thresholdMs) return;
      try {
        await TabService.suspendTab(tab.id);
      } catch (error) {
        // Tab may have been closed
        // eslint-disable-next-line no-console
        console.error("Error suspending tab:", error);
      }
    }),
  );
}

// Listen for tab removals to update workspace data
// MOVED TO DASHBOARD
// chrome.tabs.onRemoved.addListener(async (_tabId) => {
//   scheduleAutoSave();
// });

// Listen for tab creation
// MOVED TO DASHBOARD
// chrome.tabs.onCreated.addListener(async (_tab) => {
//   scheduleAutoSave();
// });

// Listen for tab movement/attaching/detaching
// chrome.tabs.onMoved.addListener(() => scheduleAutoSave());
// chrome.tabs.onAttached.addListener(() => scheduleAutoSave());
// chrome.tabs.onDetached.addListener(() => scheduleAutoSave());

// Window-ownership lifecycle: free a closed window's workspaces immediately,
// and wipe all records on browser startup — window IDs from a previous
// session are dead and may be recycled, which would cause false conflicts.
chrome.windows.onRemoved.addListener((windowId) => {
  clearWindowOwnership(windowId).catch((error) => {
    // eslint-disable-next-line no-console
    console.error("[Background] Failed to clear window ownership:", error);
  });
});

chrome.runtime.onStartup.addListener(() => {
  migrateLegacyToken();
  clearAllWindowOwnership().catch((error) => {
    // eslint-disable-next-line no-console
    console.error("[Background] Failed to reset window ownership:", error);
  });
  // Push anything left in the queue from the previous session
  SyncService.processQueue().catch((error) => {
    // eslint-disable-next-line no-console
    console.error("[Background] Startup queue flush failed:", error);
  });
});

// Flush the cloud-sync queue even when no dashboard page is open. The
// cross-context process lock makes this safe alongside an open dashboard.
chrome.alarms.create("syncQueueFlush", { periodInMinutes: 5 });

// Periodic auto-suspend scan (alarm-driven so it survives worker termination)
chrome.alarms.create("autoSuspendCheck", { periodInMinutes: 1 });

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === "syncQueueFlush") {
    SyncService.processQueue().catch((error) => {
      // eslint-disable-next-line no-console
      console.error("[Background] Periodic queue flush failed:", error);
    });
  }

  if (alarm.name === "autoSuspendCheck") {
    runAutoSuspendScan().catch((error) => {
      // eslint-disable-next-line no-console
      console.error("[Background] Auto-suspend scan failed:", error);
    });
  }
});

// Handle messages from popup or content scripts
chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  // Handle different message types
  switch (message.type) {
    case "GET_STATS":
      TabService.getMemoryStats().then(sendResponse);
      return true; // Indicates async response

    case "SUSPEND_INACTIVE":
      TabService.suspendInactiveTabs().then(() => {
        sendResponse({ success: true });
      });
      return true;

    default:
      // Don't complain about unknown messages, intended for other listeners
      return false;
  }
});

// Handle extension icon click
chrome.action.onClicked.addListener(() => {
  // Default behavior is to open popup
  // This listener is here for potential future customization
});

/**
 * Handle messages from external websites (Relay Pattern).
 * Allows approved domains (tabula.com, staging, localhost) to trigger actions in the extension.
 * @see externally_connectable in manifest.json
 */
chrome.runtime.onMessageExternal.addListener(
  (message, sender, sendResponse) => {
    // Log incoming external message for debugging (optional, remove in prod if noisy)
    // eslint-disable-next-line no-console
    console.log(
      "[Tabula] External message received:",
      message,
      "from:",
      sender.origin,
    );

    switch (message.type) {
      case "PING":
        // Simple health check to confirm extension is installed
        sendResponse({
          success: true,
          installed: true,
          version: chrome.runtime.getManifest().version,
        });
        return true;

      case "IMPORT_SPACE": {
        // Handle space import from the relay landing (tabula.com/s/<relayId>).
        // Payload: { type: 'IMPORT_SPACE', relayId: string, spaceId?: string }
        //
        // We open the dashboard pointed at the relay handle and let it redeem
        // the grant + pull the shared space (useRelayImport): redeeming needs
        // the signed-in user's token + transparent refresh, which live in the
        // dashboard's auth/sync context, so the import is driven there rather
        // than in the service worker. spaceId (the resolved workspace id) is
        // only a legacy fallback for a direct deep-link carrying no relay handle.
        const relayId =
          typeof message.relayId === "string" ? message.relayId.trim() : "";
        const spaceId =
          typeof message.spaceId === "string" ? message.spaceId.trim() : "";
        if (!relayId && !spaceId) {
          sendResponse({ success: false, error: "Missing relayId" });
          return true;
        }

        const params = new URLSearchParams();
        if (relayId) params.set("relayId", relayId);
        else params.set("spaceId", spaceId);
        const dashboardUrl = chrome.runtime.getURL(
          `dashboard.html?${params.toString()}`,
        );
        chrome.tabs
          .create({ url: dashboardUrl, active: true })
          .then(() => {
            sendResponse({ success: true, action: "opened_dashboard" });
          })
          .catch((err) => {
            sendResponse({ success: false, error: String(err) });
          });
        return true; // Indicates async response
      }

      default:
        sendResponse({ success: false, error: "Unknown message type" });
        return true;
    }
  },
);

export {};
