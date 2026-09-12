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
 * Resolve a usable favicon URL for a tab.
 *
 * Prefers the tab's own favIconUrl, then falls back to Google's s2 favicon
 * service (works in MV3 with no extra permission — loaded via <img>, covered
 * by host_permissions). The removed chrome://favicon/ API must NOT be used.
 */
export function getFaviconSrc(
  tab: { favIconUrl?: string | null; url?: string | null },
  size = 32,
): string {
  if (tab.favIconUrl) return tab.favIconUrl;
  const domain = tab.url ? encodeURIComponent(tab.url) : "";
  return `https://www.google.com/s2/favicons?domain=${domain}&sz=${size}`;
}
