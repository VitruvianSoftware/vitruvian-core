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
 * Resolves the API base URL at RUNTIME instead of at `next build` time.
 *
 * tabula-deploy.yaml builds the web image ONCE and promotes that same digest,
 * unchanged, across dev/nonprod/prod. A `NEXT_PUBLIC_*` env var is inlined
 * into the client bundle by webpack/turbopack during `next build`, so it can
 * only ever hold whichever single environment's value was present at that one
 * build — which is exactly what broke production login (the bundle shipped
 * everywhere with the dev API host baked in; see docs/tabula/incidents or the
 * git history on this file for the writeup). A plain (non-`NEXT_PUBLIC_`)
 * `API_URL` env var is NOT inlined, so it can vary correctly per Cloud Run
 * revision, but that also means the CLIENT bundle can't read it directly —
 * `process.env` in browser code only ever sees the vars that were inlined at
 * build time.
 *
 * The fix: the server reads `API_URL` fresh on every request (this file's
 * server branch) and hands it to the client via an inline JSON script tag
 * rendered in app/layout.tsx; the client branch below reads that once and
 * caches it for the life of the page.
 */

declare global {
  interface Window {
    __TABULA_RUNTIME_CONFIG__?: { apiUrl?: string | null };
  }
}

export const RUNTIME_CONFIG_ELEMENT_ID = "tabula-runtime-config";
const DEFAULT_API_URL = "http://localhost:8080/api/v1";

let cachedClientApiUrl: string | null = null;

function readClientApiUrl(): string | null {
  const el = document.getElementById(RUNTIME_CONFIG_ELEMENT_ID);
  if (!el?.textContent) return null;
  try {
    const parsed = JSON.parse(el.textContent) as { apiUrl?: string | null };
    return parsed.apiUrl || null;
  } catch {
    return null;
  }
}

export function getApiUrl(): string {
  if (typeof window === "undefined") {
    // Server (RSC / route handlers / middleware): read directly. Node
    // re-evaluates process.env per process start, so this reflects THIS
    // container's own environment even though the bundle it's serving is
    // shared across environments.
    return process.env.API_URL || DEFAULT_API_URL;
  }
  if (cachedClientApiUrl) return cachedClientApiUrl;
  cachedClientApiUrl = readClientApiUrl() || DEFAULT_API_URL;
  return cachedClientApiUrl;
}

/** Test-only: clears the client-side cache so tests don't leak state across cases. */
export function __resetRuntimeConfigCacheForTests(): void {
  cachedClientApiUrl = null;
}
