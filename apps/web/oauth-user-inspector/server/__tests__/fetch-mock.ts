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
 * CJS-friendly outbound-HTTP mock for the server's `node-fetch` calls.
 *
 * The server uses `node-fetch` (a CommonJS module) for every outbound OAuth
 * provider request. Rather than depend on msw@2 — which is ESM-only and pulls
 * in a deep tree of `.mjs` transitive deps that ts-jest/CJS cannot transform in
 * the hermetic bazel sandbox — we mock the `node-fetch` module directly with a
 * registry of URL+method handlers. This requires zero ESM transform gymnastics,
 * keeps the suite pure CJS, and still drives the real Express app via supertest.
 *
 * Each handler is matched by HTTP method + a URL matcher (exact string or
 * RegExp) and receives the request URL, method and serialized body so it can
 * branch the same way the previous msw handlers did (e.g. refresh vs. exchange).
 */

export type MockResponseInit = {
  status?: number;
  json?: unknown;
  body?: string | null;
  headers?: Record<string, string>;
};

export type FetchMockContext = {
  url: string;
  method: string;
  body: string;
};

export type FetchMockHandler = (
  ctx: FetchMockContext,
) => MockResponseInit | Promise<MockResponseInit>;

type RegisteredHandler = {
  method: string;
  match: string | RegExp;
  handler: FetchMockHandler;
};

/**
 * A minimal stand-in for a `node-fetch` Response. Implements exactly the
 * surface the server consumes: `.status`, `.ok`, `.text()`, `.json()` and a
 * `headers` object with `.get()` and `.entries()`.
 */
class MockResponse {
  readonly status: number;
  readonly ok: boolean;
  readonly headers: {
    get(name: string): string | null;
    entries(): IterableIterator<[string, string]>;
  };
  private readonly _bodyText: string;

  constructor(init: MockResponseInit) {
    this.status = init.status ?? 200;
    this.ok = this.status >= 200 && this.status < 300;

    const normalizedHeaders = new Map<string, string>();
    if (init.json !== undefined) {
      normalizedHeaders.set("content-type", "application/json");
    }
    for (const [k, v] of Object.entries(init.headers ?? {})) {
      normalizedHeaders.set(k.toLowerCase(), v);
    }

    this.headers = {
      get: (name: string) => normalizedHeaders.get(name.toLowerCase()) ?? null,
      entries: () => normalizedHeaders.entries(),
    };

    if (init.json !== undefined) {
      this._bodyText = JSON.stringify(init.json);
    } else if (typeof init.body === "string") {
      this._bodyText = init.body;
    } else {
      this._bodyText = "";
    }
  }

  async text(): Promise<string> {
    return this._bodyText;
  }

  async json(): Promise<unknown> {
    return this._bodyText ? JSON.parse(this._bodyText) : {};
  }
}

/**
 * Stateful mock fetch registry. Base handlers registered via `register()` form
 * the default behaviour; per-test overrides registered via `use()` take
 * precedence and are cleared by `reset()` (mirroring msw's
 * `server.use()` / `resetHandlers()`).
 */
export class FetchMock {
  private base: RegisteredHandler[] = [];
  private overrides: RegisteredHandler[] = [];

  register(
    method: string,
    match: string | RegExp,
    handler: FetchMockHandler,
  ): void {
    this.base.push({ method: method.toUpperCase(), match, handler });
  }

  /** Register a per-test override; cleared on reset(). Most-recent wins. */
  use(method: string, match: string | RegExp, handler: FetchMockHandler): void {
    this.overrides.unshift({ method: method.toUpperCase(), match, handler });
  }

  /** Clear per-test overrides (base handlers remain). */
  reset(): void {
    this.overrides = [];
  }

  private static matches(reg: RegisteredHandler, url: string): boolean {
    if (typeof reg.match === "string") {
      return url === reg.match || url.split("?")[0] === reg.match;
    }
    return reg.match.test(url);
  }

  /** The mock function to install as `node-fetch`'s default export. */
  fetch = async (
    input: string | { toString(): string; method?: string },
    init?: { method?: string; body?: unknown },
  ): Promise<MockResponse> => {
    const url = typeof input === "string" ? input : input.toString();
    const method = (
      init?.method ??
      (typeof input === "object" ? input.method : undefined) ??
      "GET"
    ).toUpperCase();

    let bodyText = "";
    const rawBody = init?.body;
    if (typeof rawBody === "string") {
      bodyText = rawBody;
    } else if (
      rawBody != null &&
      typeof (rawBody as any).toString === "function"
    ) {
      // URLSearchParams and similar serialize via toString()
      bodyText = (rawBody as any).toString();
    }

    const ctx: FetchMockContext = { url, method, body: bodyText };

    for (const reg of [...this.overrides, ...this.base]) {
      if (reg.method === method && FetchMock.matches(reg, url)) {
        const result = await reg.handler(ctx);
        return new MockResponse(result);
      }
    }

    throw new Error(
      `[fetch-mock] No handler registered for ${method} ${url}. ` +
        `Register one via fetchMock.register()/use().`,
    );
  };
}
