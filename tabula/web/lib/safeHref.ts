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
 * Return `url` only if it is an absolute http(s) URL, else null.
 *
 * Space content is attacker-controlled: the #139 write schema deliberately
 * stores `url` as `z.string().min(1)` (NOT `.url()`) so the extension can sync
 * `about:`/`chrome:`/`data:` tabs. When the web companion renders a SHARED
 * space, a `javascript:`/`data:`/`vbscript:` URL placed by a malicious owner or
 * edit collaborator would execute in the tabula.com origin (where the JWT lives)
 * if rendered as an `<a href>` or favicon `src`. So every user-controlled URL
 * passes through here; callers render a rejected URL as inert text, never a
 * link. Mirrors the extension's allowlist (dashboard/CommandPalette).
 */
export function safeHref(url: string | null | undefined): string | null {
  if (!url) return null;
  try {
    // No base: relative paths and scheme-relative ("//evil") URLs throw and are
    // rejected. Only absolute URLs with an http(s) protocol are allowed.
    const parsed = new URL(url);
    if (parsed.protocol === "http:" || parsed.protocol === "https:") {
      return url;
    }
    return null;
  } catch {
    return null;
  }
}
