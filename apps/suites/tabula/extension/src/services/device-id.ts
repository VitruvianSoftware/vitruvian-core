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
 * Stable per-profile device identity.
 *
 * Each browser profile (= one extension installation) gets one persistent
 * device ID, generated once and stored in chrome.storage.local. The server
 * uses it to suppress SSE echo of a device's own changes and to maintain the
 * advisory "active device" lease for tab sync.
 */

const DEVICE_ID_KEY = "tabula_device_id";
const DEVICE_ID_LOCK = "tabula_device_id_lock";

let cachedDeviceId: string | null = null;

function generateDeviceId(): string {
  const uuid =
    typeof globalThis.crypto !== "undefined" &&
    typeof globalThis.crypto.randomUUID === "function"
      ? globalThis.crypto.randomUUID()
      : `${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
  return `device_${uuid}`;
}

async function readOrCreate(): Promise<string> {
  const result = await chrome.storage.local.get(DEVICE_ID_KEY);
  const existing = result[DEVICE_ID_KEY] as string | undefined;
  if (existing) return existing;
  const fresh = generateDeviceId();
  await chrome.storage.local.set({ [DEVICE_ID_KEY]: fresh });
  return fresh;
}

export async function getDeviceId(): Promise<string> {
  if (cachedDeviceId) return cachedDeviceId;

  // Serialize generation across contexts (two dashboard windows opening at
  // once must not mint two different IDs for the same profile).
  if (typeof navigator !== "undefined" && "locks" in navigator) {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    cachedDeviceId = await (navigator as any).locks.request(
      DEVICE_ID_LOCK,
      readOrCreate,
    );
  } else {
    cachedDeviceId = await readOrCreate();
  }
  return cachedDeviceId!;
}

/** Test-only: reset the in-memory cache */
export function resetDeviceIdCacheForTests(): void {
  cachedDeviceId = null;
}
