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
 * Router utilities for URL-based workspace state management.
 * Enables Multi-Window support by encoding the active spaceId in the URL.
 */

/**
 * Gets the spaceId from the current URL query parameters.
 * @returns The spaceId if present, or null.
 */
export function getSpaceIdFromUrl(): string | null {
  const params = new URLSearchParams(window.location.search);
  return params.get("spaceId");
}

/**
 * Updates the URL to include the given spaceId without reloading the page.
 * Uses history.pushState for clean browser history.
 * @param spaceId - The workspace ID to set in the URL.
 */
export function setSpaceIdInUrl(spaceId: string): void {
  const url = new URL(window.location.href);
  url.searchParams.set("spaceId", spaceId);
  window.history.pushState({ spaceId }, "", url.toString());
}

/**
 * Removes the spaceId from the current URL without reloading.
 */
export function clearSpaceIdFromUrl(): void {
  const url = new URL(window.location.href);
  url.searchParams.delete("spaceId");
  window.history.pushState({}, "", url.toString());
}

/**
 * Generates a full Dashboard URL with a specific spaceId.
 * Useful for opening new windows with a specific workspace.
 * @param spaceId - The workspace ID to include.
 * @returns The full dashboard URL with spaceId parameter.
 */
export function getDashboardUrlWithSpace(spaceId: string): string {
  // chrome.runtime.getURL is available in extension contexts
  const baseUrl = chrome.runtime.getURL("dashboard.html");
  const url = new URL(baseUrl);
  url.searchParams.set("spaceId", spaceId);
  return url.toString();
}
