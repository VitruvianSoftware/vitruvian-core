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
 * UpdateBanner — dev-channel "new build available" nudge (issue #45, M1).
 *
 * Polls UpdateCheckService on mount and every 15 minutes. When the deployed
 * commit differs from this build's commit, offers Reload
 * (chrome.runtime.reload()) — the user runs `tabcli ext update` first so the
 * on-disk files are already the new build. Failures stay silent; the fixed
 * interval is the backoff. Dismiss hides the banner for that deployed commit.
 */

import React, { useEffect, useState } from "react";
import { UpdateCheckService } from "../services/updateCheck";

const POLL_INTERVAL_MS = 15 * 60 * 1000;

export const UpdateBanner: React.FC = () => {
  const [deployedCommit, setDeployedCommit] = useState<string | null>(null);
  const [dismissedCommit, setDismissedCommit] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    const check = async () => {
      const result = await UpdateCheckService.checkForUpdate();
      if (cancelled) return;
      // null = ineligible or no reliable answer — keep the current banner
      // state rather than flickering it off on a transient failure.
      if (result === null) return;
      setDeployedCommit(result.updateAvailable ? result.deployedCommit : null);
    };
    check();
    const id = setInterval(check, POLL_INTERVAL_MS);
    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, []);

  if (!deployedCommit || deployedCommit === dismissedCommit) return null;

  return (
    <div className="update-banner" role="status">
      <span>
        New build deployed ({deployedCommit.slice(0, 7)}) — run{" "}
        <code>tabcli ext update</code>, then reload.
      </span>
      <button
        type="button"
        className="update-banner-reload"
        onClick={() => chrome.runtime.reload()}
      >
        Reload
      </button>
      <button
        type="button"
        className="update-banner-dismiss"
        onClick={() => setDismissedCommit(deployedCommit)}
      >
        Dismiss
      </button>
    </div>
  );
};
