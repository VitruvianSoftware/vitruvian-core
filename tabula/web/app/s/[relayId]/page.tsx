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

// The installed extension's id + store listing. Until the extension publishes,
// EXTENSION_ID is empty and detection simply fails closed (→ the not-installed
// states), which is the correct graceful fallback for non-Chrome browsers too.
const EXTENSION_ID = process.env.NEXT_PUBLIC_TABULA_EXTENSION_ID ?? "";
const CHROME_STORE_URL =
  "https://chromewebstore.google.com/detail/tabula-tab-manager";
const DETECT_TIMEOUT_MS = 400;

type Phase = "loading" | "invalid" | "opening" | "preview";

/**
 * Relay landing for tabula.com/s/<relayId> (#140). Four states:
 *  0. extension installed     → deep-link into it ("Opening in Tabula…")
 *  1. stranger (logged out)   → preview + Install + Log in
 *  2. logged in, view grant   → preview + Install + "View in browser"
 *  3. logged in, edit grant   → preview + Install + "Edit in browser"
 * The extension stays the primary surface, so Install is always primary; opening
 * in the browser is the additive escape hatch. The preview is PUBLIC (no token
 * in the URL — the relayId is an opaque handle resolved server-side).
 */
export default function RelayLandingPage() {
  const params = useParams<{ relayId: string }>();
  const router = useRouter();
  const relayId = typeof params?.relayId === "string" ? params.relayId : "";

  const [phase, setPhase] = useState<Phase>("loading");
  const [info, setInfo] = useState<RelayInfo | null>(null);
  const [loggedIn, setLoggedIn] = useState(false);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    let active = true;
    setLoggedIn(Boolean(AuthService.getToken()));
    SharingService.getRelayInfo(relayId)
      .then(async (i) => {
        if (!active) return;
        setInfo(i);
        const installed = await detectExtension();
        if (!active) return;
        if (installed) {
          openInExtension(relayId, i.workspaceId);
          setPhase("opening");
        } else {
          setPhase("preview");
        }
      })
      .catch(() => {
        if (active) setPhase("invalid");
      });
    return () => {
      active = false;
    };
  }, [relayId]);

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
        <a
          href={CHROME_STORE_URL}
          className="rounded-lg bg-blue-600 px-4 py-2.5 text-center text-sm font-semibold text-white hover:bg-blue-700"
        >
          Install Tabula
        </a>
        {loggedIn ? (
          <button
            type="button"
            onClick={openInBrowser}
            disabled={busy}
            className="rounded-lg border border-gray-200 px-4 py-2.5 text-sm font-medium text-gray-700 hover:bg-gray-50 disabled:opacity-50 dark:border-gray-700 dark:text-gray-200"
          >
            {busy
              ? "Opening…"
              : canEdit
                ? "Edit in browser"
                : "View in browser"}
          </button>
        ) : (
          <button
            type="button"
            onClick={logIn}
            className="rounded-lg border border-gray-200 px-4 py-2.5 text-sm font-medium text-gray-700 hover:bg-gray-50 dark:border-gray-700 dark:text-gray-200"
          >
            Log in to open in browser
          </button>
        )}
      </div>
    </div>
  );
}

function RelayPreviewCard({ info }: { info: RelayInfo }) {
  return (
    <div className="rounded-2xl border border-gray-200 p-6 text-center dark:border-gray-700">
      <p className="text-sm text-gray-500">
        {info.ownerName} shared a space with you
      </p>
      <h1 className="mt-2 text-2xl font-semibold text-gray-900 dark:text-gray-100">
        {info.workspaceName}
      </h1>
      <p className="mt-1 text-xs uppercase tracking-wide text-gray-400">
        {info.role === "edit" ? "Can edit" : "View only"}
      </p>
    </div>
  );
}

function Centered({ children }: { children: ReactNode }) {
  return (
    <div className="flex min-h-[60vh] items-center justify-center px-4 text-center text-sm text-gray-500">
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
    const chrome = getChrome();
    if (!EXTENSION_ID || !chrome?.runtime?.sendMessage) {
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
      chrome.runtime.sendMessage(EXTENSION_ID, { type: "PING" }, (resp) => {
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
    chrome?.runtime?.sendMessage?.(EXTENSION_ID, {
      type: "IMPORT_SPACE",
      spaceId: workspaceId,
      relayId,
    });
  } catch {
    // best-effort deep link
  }
}
