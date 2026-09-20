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
 * Regression guard for the vulnerability-scanner fast-reject hook that
 * buildApp registers first (src/lib/scannerReject.ts).
 *
 * Internet-facing Cloud Run services get a steady drip of automated probes
 * for /.env, /.git/config, /wp-login.php, /phpmyadmin, /xmlrpc.php and so on.
 * Each one used to run the whole request pipeline (rate-limit Redis round
 * trip, logging, 404 handler) and keep an instance warm. The hook answers
 * 404 before any of that.
 *
 * Tested against a bare Fastify instance: app.ts builds AND starts the real
 * server at module scope, so it must not be imported in jest.
 */
import Fastify from "fastify";
import {
  isScannerProbePath,
  registerScannerFastReject,
} from "../../src/lib/scannerReject";

const build = () => {
  const app = Fastify({ logger: false });
  registerScannerFastReject(app);
  // Stands in for the plugin work (rate limit, auth) that must be skipped
  const downstreamHook = jest.fn(async () => undefined);
  app.addHook("onRequest", downstreamHook);
  app.get("/api/v1/things", async () => ({ ok: true }));
  app.get("/health", async () => ({ status: "ok" }));
  return { app, downstreamHook };
};

describe("isScannerProbePath", () => {
  it.each([
    "/.env",
    "/.env.local",
    "/.env.production",
    "/.git/config",
    "/.git/HEAD",
    "/wp-admin/",
    "/wp-login.php",
    "/wp-content/plugins/x",
    "/phpmyadmin",
    "/phpmyadmin/index.php",
    "/xmlrpc.php",
    "/WP-ADMIN/",
    "/PhpMyAdmin/",
    "/.ENV",
  ])("flags %s as a scanner probe", (path) => {
    expect(isScannerProbePath(path)).toBe(true);
  });

  it.each([
    "/",
    "/health",
    "/api/v1/workspaces",
    "/api/v1/auth/login",
    "/api/v1/sync/stream",
    "/api/v1/share-links/abc",
    "/environment",
    "/gitlab-hook",
    "/wpx",
  ])("lets %s through", (path) => {
    expect(isScannerProbePath(path)).toBe(false);
  });
});

describe("scanner fast-reject hook", () => {
  it.each(["/.env", "/.git/config", "/wp-login.php", "/phpmyadmin/", "/xmlrpc.php"])(
    "answers %s with 404 before any downstream hook runs",
    async (path) => {
      const { app, downstreamHook } = build();
      const res = await app.inject({ method: "GET", url: path });

      expect(res.statusCode).toBe(404);
      expect(res.json()).toEqual({
        statusCode: 404,
        error: "Not Found",
        message: "Not Found",
      });
      expect(downstreamHook).not.toHaveBeenCalled();
      await app.close();
    },
  );

  it("rejects probes with a query string too", async () => {
    const { app, downstreamHook } = build();
    const res = await app.inject({ method: "GET", url: "/.env?x=1" });
    expect(res.statusCode).toBe(404);
    expect(downstreamHook).not.toHaveBeenCalled();
    await app.close();
  });

  it("rejects probes on any method", async () => {
    const { app, downstreamHook } = build();
    const res = await app.inject({ method: "POST", url: "/xmlrpc.php" });
    expect(res.statusCode).toBe(404);
    expect(downstreamHook).not.toHaveBeenCalled();
    await app.close();
  });

  it("does not touch legitimate API routes", async () => {
    const { app, downstreamHook } = build();
    const res = await app.inject({ method: "GET", url: "/api/v1/things" });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ ok: true });
    expect(downstreamHook).toHaveBeenCalledTimes(1);
    await app.close();
  });

  it("leaves unknown-but-legitimate paths to fastify's own 404 (downstream still runs)", async () => {
    const { app, downstreamHook } = build();
    const res = await app.inject({ method: "GET", url: "/api/v1/nope" });
    expect(res.statusCode).toBe(404);
    expect(downstreamHook).toHaveBeenCalledTimes(1);
    await app.close();
  });
});
