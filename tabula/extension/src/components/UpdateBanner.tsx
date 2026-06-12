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
 * UpdateBanner — channel-aware nudge for the offered update (commit or version,
 * per channel) (issue #45, M2).
 *
 * Polls UpdateCheckService on mount and every 15 minutes. When an update is
 * available the copy adapts: alpha shows the short commit SHA, beta shows the
 * release version number. The user runs `tabcli ext update` first so the
 * on-disk files are already the new build, then reloads via
 * chrome.runtime.reload(). Failures stay silent; the fixed interval is the
 * backoff. Dismiss hides the banner for that deployed commit or version.
 */

import React, { useEffect, useState } from "react";
import { UpdateCheckService } from "../services/updateCheck";
import type { UpdateCheckResult } from "../services/updateCheck";

const POLL_INTERVAL_MS = 15 * 60 * 1000;

export const UpdateBanner: React.FC = () => {
  const [offer, setOffer] = useState<UpdateCheckResult | null>(null);
  const [dismissedLatest, setDismissedLatest] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    const check = async () => {
      const result = await UpdateCheckService.checkForUpdate();
      if (cancelled) return;
      // null = ineligible or no reliable answer — keep the current banner
      // state rather than flickering it off on a transient failure.
      if (result === null) return;
      setOffer(result.updateAvailable ? result : null);
    };
    check();
    const id = setInterval(check, POLL_INTERVAL_MS);
    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, []);

  if (!offer || offer.latest === dismissedLatest) return null;

  return (
    <div className="update-banner" role="status">
      <span>
        {offer.channel === "beta"
          ? `New release v${offer.latest} available`
          : `New build deployed (${offer.latest.slice(0, 7)})`}{" "}
        — run <code>tabcli ext update</code>, then reload.
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
        onClick={() => setDismissedLatest(offer.latest)}
      >
        Dismiss
      </button>
    </div>
  );
};
