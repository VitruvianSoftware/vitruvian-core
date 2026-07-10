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
 * Test helpers for driving `window.location` under jsdom 26+.
 *
 * jest-environment-jsdom 30 bundles jsdom 26, which implements the WHATWG
 * `[LegacyUnforgeable]` semantics for `Location`: `window.location` is a
 * non-configurable accessor, and every property on the Location instance
 * (including `reload`) is non-configurable/non-writable. The jest 29-era
 * patterns — `delete window.location`, `Object.defineProperty(window,
 * "location", ...)`, assigning a `new URL(...)`, or
 * `jest.spyOn(window.location, "reload")` — now either throw
 * "TypeError: Cannot redefine property: location" or silently no-op.
 */

/* eslint-disable @typescript-eslint/no-explicit-any */

/**
 * Rewrites the document URL through the real history API, immune to tests
 * stubbing `window.history.pushState/replaceState` with `jest.fn()` (those
 * stubs shadow the instance, not `History.prototype`).
 *
 * jsdom enforces the HTML spec's "can have its URL rewritten" check: only
 * http(s) documents may rewrite their query string (for other schemes, e.g.
 * chrome-extension://, even query changes throw SecurityError). URLs passed
 * here must therefore stay on the jest default http://localhost origin.
 */
export function setWindowUrl(url: string): void {
  History.prototype.replaceState.call(
    window.history,
    window.history.state,
    "",
    url,
  );
}

/** The jsdom-internal implementation object backing `window.location`. */
function locationImpl(): { reload: () => void } {
  const impl = Object.getOwnPropertySymbols(window.location)
    .map((sym) => (window.location as any)[sym])
    .find((value) => value && typeof value.reload === "function");
  if (!impl) {
    throw new Error(
      "jsdom internals changed: could not find the Location impl behind window.location",
    );
  }
  return impl;
}

/**
 * Installs a jest mock behind the unforgeable `window.location.reload`.
 *
 * The unforgeable `Location` wrapper delegates every call to a jsdom-internal
 * impl object whose methods live on a plain, overridable prototype — so
 * shadowing `reload` on that impl intercepts `window.location.reload()`
 * without touching the locked-down wrapper (where jsdom would only log
 * "Not implemented: navigation"). Assert on the returned mock; reading
 * `window.location.reload` still yields the unforgeable wrapper function.
 *
 * Call {@link restoreLocationReload} to undo (per-file jsdom instances make
 * this optional for module-scope use).
 */
export function mockLocationReload(): jest.Mock {
  const mock = jest.fn();
  locationImpl().reload = mock;
  return mock;
}

/** Undoes {@link mockLocationReload}, re-exposing the jsdom implementation. */
export function restoreLocationReload(): void {
  delete (locationImpl() as { reload?: () => void }).reload;
}
