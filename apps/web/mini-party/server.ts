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

import express from "express";
import { existsSync } from "fs";
import path from "path";
import { createServer } from "http";
import { fileURLToPath } from "url";
import { attachGameServer, parseOrigins } from "./server/gameServer.ts";

const here = path.dirname(fileURLToPath(import.meta.url));
const PORT = Number(process.env.PORT ?? 3000);

async function startServer() {
  const app = express();
  app.disable("x-powered-by");
  const httpServer = createServer(app);
  // ALLOWED_ORIGINS lets the GitHub Pages game connect from its own site.
  attachGameServer(httpServer, {
    allowedOrigins: parseOrigins(process.env.ALLOWED_ORIGINS),
  });

  app.get("/healthz", (_req, res) => {
    res.type("text/plain").send("ok");
  });

  const distPath = path.join(here, "dist");
  if (process.env.NODE_ENV !== "production") {
    // Dev: Vite serves the client with hot reload from the same port.
    const { createServer: createViteServer } = await import("vite");
    const vite = await createViteServer({
      root: here,
      server: { middlewareMode: true, hmr: { server: httpServer } },
      appType: "spa",
    });
    app.use(vite.middlewares);
  } else if (existsSync(distPath)) {
    // Production with a built client: serve what `vite build` wrote to dist/.
    app.use(express.static(distPath));
    app.get("/{*splat}", (_req, res) => {
      res.sendFile(path.join(distPath, "index.html"));
    });
  }
  // Otherwise this is the rooms-only server (the container image): just the
  // socket.io relay and /healthz.

  httpServer.listen(PORT, "0.0.0.0", () => {
    console.log(`Mini Party running on http://localhost:${PORT}`);
  });
}

startServer().catch((err) => {
  console.error("Failed to start server:", err);
  process.exit(1);
});
