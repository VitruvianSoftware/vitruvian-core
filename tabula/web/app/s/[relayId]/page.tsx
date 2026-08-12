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

"use client";

import { useEffect, useState, type ReactNode } from "react";
import { useParams, useRouter } from "next/navigation";
import { SharingService, ApiError, type RelayInfo } from "@/lib/sharing";
import { AuthService } from "@/lib/auth";
import { Button } from "@vitruviansoftware/design-system";

// The installed extension's id + store listing. Until the extension publishes,
// the id is empty and detection simply fails closed (→ the not-installed
// states), which is the correct graceful fallback for non-Chrome browsers too.
// Read via a function (not a module constant) so it is resolvable in tests; Next
// inlines the NEXT_PUBLIC_ var at build time regardless of where it is read.
function extensionId(): string {
  return process.env.NEXT_PUBLIC_TABULA_EXTENSION_ID ?? "";
}
const CHROME_STORE_URL =
  "https://chromewebstore.google.com/detail/tabula-tab-manager";
const DETECT_TIMEOUT_MS = 400;

type Phase = "loading" | "invalid" | "opening" | "preview";

/**
 * Relay landing for tabula.com/s/<relayId> (#140). The page always lands on a
 * PUBLIC preview (no token in the URL — relayId is an opaque handle resolved
 * server-side) and the recipient chooses how to open it; nothing is redeemed or
 * deep-linked without an explicit click. The primary CTA depends on detection:
 *  - extension installed → "Open in Tabula" (deep-links on click → "Opening…")
 *  - not installed       → "Install Tabula" (Chrome Web Store)
 * Below it, the additive in-browser path: logged out → "Log in"; logged in →
 * "View in browser" / "Edit in browser" by grant role.
 */
export default function RelayLandingPage() {
  const params = useParams<{ relayId: string }>();
  const router = useRouter();
  const relayId = typeof params?.relayId === "string" ? params.relayId : "";

  const [phase, setPhase] = useState<Phase>("loading");
  const [info, setInfo] = useState<RelayInfo | null>(null);
  const [loggedIn, setLoggedIn] = useState(false);
  const [extensionInstalled, setExtensionInstalled] = useState(false);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    let active = true;
    setLoggedIn(Boolean(AuthService.getToken()));
    SharingService.getRelayInfo(relayId)
      .then(async (i) => {
        if (!active) return;
        setInfo(i);
        // Detection only chooses which CTA to show — it must NOT auto-deep-link.
        // Opening the extension kicks off a grant redeem, so it requires an
        // explicit click; merely visiting /s/<id> must never silently join you
        // to a (possibly attacker-controlled) space. The page always lands on
        // the preview and lets the recipient choose.
        const installed = await detectExtension();
        if (!active) return;
        setExtensionInstalled(installed);
        setPhase("preview");
      })
      .catch(() => {
        if (active) setPhase("invalid");
      });
    return () => {
      active = false;
    };
  }, [relayId]);

  function openInTabula() {
    if (!info) return;
    openInExtension(relayId, info.workspaceId);
    setPhase("opening");
  }

  async function openInBrowser() {
    setBusy(true);
    try {
      const result = await SharingService.acceptRelay(relayId);
      router.push(`/workspaces/${result.workspaceId}`);
    } catch (e) {
      // Lost/absent session → prompt login, then let the user click again.
      if (e instanceof ApiError && e.status === 401) {
        await AuthService.login().catch(() => undefined);
        setLoggedIn(Boolean(AuthService.getToken()));
      }
      setBusy(false);
    }
  }

  async function logIn() {
    await AuthService.login().catch(() => undefined);
    setLoggedIn(Boolean(AuthService.getToken()));
  }

  if (phase === "loading") return <Centered>Opening shared space…</Centered>;
  if (phase === "invalid")
    return <Centered>This link is invalid, revoked, or expired.</Centered>;
  if (phase === "opening") return <Centered>Opening in Tabula…</Centered>;

  const canEdit = info?.role === "edit";
  return (
    <div className="mx-auto max-w-lg px-6 py-16">
      {info ? <RelayPreviewCard info={info} /> : null}
      <div className="mt-8 flex flex-col gap-3">
        {extensionInstalled ? (
          <Button
            type="button"
            onClick={openInTabula}
          >
            Open in Tabula
          </Button>
        ) : (
          <a
            href={CHROME_STORE_URL}
            className="bg-blue-600 px-4 py-2.5 text-center text-sm font-semibold text-white hover:bg-blue-700"
          >
            Install Tabula
          </a>
        )}
        {loggedIn ? (
          <Button
            type="button"
            variant="ghost"
            onClick={openInBrowser}
            disabled={busy}
          >
            {busy
              ? "Opening…"
              : canEdit
                ? "Edit in browser"
                : "View in browser"}
          </Button>
        ) : (
          <Button
            type="button"
            variant="ghost"
            onClick={logIn}
          >
            Log in to open in browser
          </Button>
        )}
      </div>
    </div>
  );
}

function RelayPreviewCard({ info }: { info: RelayInfo }) {
  return (
    <div className="border border-hairline p-6 text-center">
      <p className="text-sm text-paper-dim">
        {info.ownerName} shared a space with you
      </p>
      <h1 className="mt-2 text-2xl font-semibold text-paper">
        {info.workspaceName}
      </h1>
      <p className="mt-1 text-xs uppercase tracking-wide text-paper-dim">
        {info.role === "edit" ? "Can edit" : "View only"}
      </p>
    </div>
  );
}

function Centered({ children }: { children: ReactNode }) {
  return (
    <div className="flex min-h-[60vh] items-center justify-center px-4 text-center text-sm text-paper-dim">
      {children}
    </div>
  );
}

interface ChromeRuntime {
  runtime?: {
    lastError?: unknown;
    sendMessage?: (
      id: string,
      message: unknown,
      callback?: (response: unknown) => void,
    ) => void;
  };
}

function getChrome(): ChromeRuntime | undefined {
  return (globalThis as unknown as { chrome?: ChromeRuntime }).chrome;
}

/**
 * Resolve true if the Tabula extension answers a ping. ANY response (even an
 * "unknown message" error) proves it is installed and reachable via
 * externally_connectable; no response / lastError / no chrome → not installed.
 */
function detectExtension(): Promise<boolean> {
  return new Promise((resolve) => {
    const id = extensionId();
    const chrome = getChrome();
    if (!id || !chrome?.runtime?.sendMessage) {
      resolve(false);
      return;
    }
    let settled = false;
    const finish = (v: boolean) => {
      if (!settled) {
        settled = true;
        resolve(v);
      }
    };
    setTimeout(() => finish(false), DETECT_TIMEOUT_MS);
    try {
      chrome.runtime.sendMessage(id, { type: "PING" }, (resp) => {
        finish(!chrome.runtime?.lastError && Boolean(resp));
      });
    } catch {
      finish(false);
    }
  });
}

function openInExtension(relayId: string, workspaceId: string) {
  const chrome = getChrome();
  try {
    chrome?.runtime?.sendMessage?.(extensionId(), {
      type: "IMPORT_SPACE",
      spaceId: workspaceId,
      relayId,
    });
  } catch {
    // best-effort deep link
  }
}
