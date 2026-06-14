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
 * Detects when the active space is live on ANOTHER device with a different tab
 * session, so the dashboard can surface the "Changes from your other device"
 * prompt (Workona's "one primary session per space").
 *
 * This device is PASSIVE when the workspace carries a FRESH active-device lease
 * held by a different device (the server keeps the lease sticky — see
 * WorkspaceService.updateWorkspace). While passive, useTabSync's skip-gate stops
 * this device from overwriting the workspace, so the stored workspace.tabs ARE
 * the primary device's session. We compare them to the live browser tabs and,
 * when they differ, offer the primary's tabs. Re-evaluates whenever the active
 * workspace object changes (e.g. an SSE-driven reload pulls the primary's tabs).
 */
import { useState, useEffect, useRef, useCallback } from "react";
import type { Workspace, Tab } from "../../types";
import { TabService } from "../../services/tabs";
import { getDeviceId } from "../../services/deviceId";
import { ACTIVE_DEVICE_STALE_MS } from "../../hooks/useTabSync";
import type { CrossDeviceTab } from "../../components/CrossDeviceSessionPopover";

/** Order-independent URL signature of a tab list, for cheap divergence checks. */
function urlSignature(urls: string[]): string {
  return [...new Set(urls)].sort().join("\n");
}

export interface UseCrossDeviceSessionReturn {
  /** The primary device's tabs to offer, or null when there's nothing to resolve. */
  conflictTabs: CrossDeviceTab[] | null;
  /** Suppress the current divergence until the primary's session changes again. */
  dismiss: () => void;
}

export function useCrossDeviceSession(
  activeWorkspace: Workspace | null,
): UseCrossDeviceSessionReturn {
  const [conflictTabs, setConflictTabs] = useState<CrossDeviceTab[] | null>(
    null,
  );
  // Signature of a divergence the user already resolved/dismissed; cleared once
  // the primary's session changes to something new (so we don't nag on the same
  // state while a claim propagates).
  const dismissedSigRef = useRef<string | null>(null);

  useEffect(() => {
    let cancelled = false;

    (async () => {
      if (!activeWorkspace) {
        setConflictTabs(null);
        return;
      }
      const { activeDeviceId, activeDeviceSeenAt, tabs } = activeWorkspace;

      // Passive only when ANOTHER device holds a FRESH lease.
      if (!activeDeviceId || !activeDeviceSeenAt) {
        setConflictTabs(null);
        return;
      }
      const fresh =
        Date.now() - new Date(activeDeviceSeenAt).getTime() <
        ACTIVE_DEVICE_STALE_MS;
      if (!fresh) {
        setConflictTabs(null);
        return;
      }
      const myDeviceId = await getDeviceId();
      if (cancelled) return;
      if (activeDeviceId === myDeviceId) {
        setConflictTabs(null);
        return;
      }

      // Compare the primary's session (stored tabs) to the live browser tabs.
      const primaryTabs = (tabs || []).filter((t: Tab) => !!t.url);
      if (primaryTabs.length === 0) {
        setConflictTabs(null);
        return;
      }
      const liveTabs = await TabService.getCurrentTabs();
      if (cancelled) return;

      const primarySig = urlSignature(primaryTabs.map((t: Tab) => t.url));
      const liveSig = urlSignature(
        liveTabs.map((t: Tab) => t.url).filter((u): u is string => !!u),
      );

      if (primarySig === liveSig) {
        setConflictTabs(null);
        return;
      }
      if (dismissedSigRef.current === primarySig) {
        return; // already resolved/dismissed this exact divergence
      }
      setConflictTabs(
        primaryTabs.map((t: Tab) => ({
          url: t.url,
          title: t.title,
          favIconUrl: t.favIconUrl,
        })),
      );
    })();

    return () => {
      cancelled = true;
    };
  }, [activeWorkspace]);

  const dismiss = useCallback(() => {
    const primaryTabs = (activeWorkspace?.tabs || []).filter((t: Tab) => !!t.url);
    dismissedSigRef.current = urlSignature(primaryTabs.map((t: Tab) => t.url));
    setConflictTabs(null);
  }, [activeWorkspace]);

  return { conflictTabs, dismiss };
}
