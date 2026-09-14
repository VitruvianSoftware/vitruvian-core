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
 * Integration tests for app endpoints (health, root)
 */
import Fastify, { FastifyInstance } from "fastify";
import cors from "@fastify/cors";

describe("App Endpoints", () => {
  let app: FastifyInstance;

  beforeAll(async () => {
    app = Fastify();

    // Register CORS like in app.ts
    await app.register(cors, {
      origin: "http://localhost:3000",
    });

    // Health check endpoint
    app.get("/health", async () => ({
      status: "ok",
      timestamp: new Date().toISOString(),
      redis: "disabled",
    }));

    // Root endpoint
    app.get("/", async () => ({
      name: "Tabula API",
      // eslint-disable-next-line @typescript-eslint/no-var-requires, global-require
      version: (require("../../package.json") as { version: string }).version,
      commit: "unknown",
      environment: "test",
    }));
  });

  afterAll(async () => {
    await app.close();
  });

  describe("GET /health", () => {
    it("should return health status", async () => {
      const response = await app.inject({
        method: "GET",
        url: "/health",
      });

      expect(response.statusCode).toBe(200);
      const body = JSON.parse(response.body);
      expect(body.status).toBe("ok");
      expect(body.timestamp).toBeDefined();
      expect(body.redis).toBe("disabled");
    });
  });

  describe("GET /", () => {
    it("should return API information", async () => {
      const response = await app.inject({
        method: "GET",
        url: "/",
      });

      expect(response.statusCode).toBe(200);
      const body = JSON.parse(response.body);
      expect(body.name).toBe("Tabula API");
      // eslint-disable-next-line @typescript-eslint/no-var-requires, global-require
      expect(body.version).toBe(
        (require("../../package.json") as { version: string }).version,
      );
      expect(body.commit).toBe("unknown");
      expect(body.environment).toBe("test");
    });
  });
});
