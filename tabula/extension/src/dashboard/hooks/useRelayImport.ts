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
 * Relay import (#140).
 *
 * Completes the cross-component share funnel inside the extension. When a user
 * opens a relay link (tabula.com/s/<relayId>) and the extension is installed,
 * the relay landing sends an IMPORT_SPACE message; the background opens the
 * dashboard at `dashboard.html?relayId=<id>`. This hook is the dashboard end of
 * that handoff: it redeems the relay (materializing the caller's grant), pulls
 * the now-accessible shared space into the local workspace list, and pins THIS
 * window to it.
 *
 * Runs at most once per dashboard load. It is a deliberate no-op when:
 *  - there is no relayId in the URL (the common case), or
 *  - the user is not signed in — redeeming requires auth, so we leave the
 *    dashboard in its normal signed-out state rather than erroring.
 * On any failure (invalid / revoked / expired relay, transient error) it fails
 * silently back to the normal dashboard. The relayId is stripped from the URL
 * regardless, so a reload never retries against a dead, possibly single-use link.
 */

import { useEffect, useRef } from "react";
import { AuthService } from "../../services/auth";
import { ApiService } from "../../services/api";
import { getRelayIdFromUrl, clearRelayIdFromUrl } from "../../utils/router";

export interface UseRelayImportProps {
  /** Reloads workspaces from the store (pulls + merges remote into local). */
  loadWorkspaces: () => Promise<void>;
  /**
   * Called once the shared space has been redeemed + pulled into local state,
   * with its workspace id. The dashboard pins THIS window to it — but must do
   * so WITHOUT letting the ownership-claim effect capture this window's tabs
   * into the shared space (that would overwrite the owner's tab list, and for
   * an edit collaborator PUT the clobber to everyone). See the relay-import
   * guard in Dashboard's sync effect.
   */
  onImported: (workspaceId: string) => void;
}

export function useRelayImport({
  loadWorkspaces,
  onImported,
}: UseRelayImportProps): void {
  // Guard against React 18 StrictMode's double-invoke and any re-render churn:
  // redeeming is a network side effect that must run exactly once.
  const ranRef = useRef(false);

  useEffect(() => {
    if (ranRef.current) return;
    const relayId = getRelayIdFromUrl();
    if (!relayId) return;
    ranRef.current = true;

    void (async () => {
      // Redeeming requires the signed-in user. If they aren't signed in, leave
      // the relayId in the URL: the dashboard's post-login reload remounts this
      // hook, which then redeems (the link is NOT consumed server-side because
      // acceptRelay never ran). Clearing it here would strip the invite and dead-
      // end the user on an empty dashboard.
      if (!(await AuthService.hasSession())) return;
      try {
        const { workspaceId } = await ApiService.acceptRelay(relayId);
        // The grant now exists server-side, so the shared space is returned by
        // GET /workspaces — a reload merges it into local state.
        await loadWorkspaces();
        onImported(workspaceId);
        // Consumed: drop the handle so a reload doesn't redeem again.
        clearRelayIdFromUrl();
      } catch {
        // Invalid / revoked / expired relay, or a transient error: silently
        // fall back to the normal dashboard, and drop the dead handle so a
        // reload doesn't retry it.
        clearRelayIdFromUrl();
      }
    })();
  }, [loadWorkspaces, onImported]);
}
