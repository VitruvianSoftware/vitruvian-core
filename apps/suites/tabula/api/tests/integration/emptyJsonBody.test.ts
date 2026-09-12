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
 * Regression guard for the fastify-5 empty-JSON-body compat shim that
 * buildApp registers (src/lib/emptyJsonBody.ts).
 *
 * Deployed extension builds send `Content-Type: application/json` on every
 * request, including body-less DELETEs. fastify 5 parses bodies whenever a
 * content-type is present (v4 exempted DELETE) and rejects an empty JSON body
 * with 400 (FST_ERR_CTP_EMPTY_JSON_BODY) at the parsing step. Without the
 * shim, every extension already in the field breaks on revoke/sign-out flows.
 *
 * Tested against a bare Fastify instance: app.ts builds AND starts the real
 * server at module scope, so it must not be imported in jest.
 */
import Fastify from "fastify";
import { registerEmptyJsonBodyTolerance } from "../../src/lib/emptyJsonBody";

const build = () => {
  const app = Fastify({ logger: false });
  registerEmptyJsonBodyTolerance(app);
  app.delete("/thing/:id", async (_request, reply) => {
    return reply.status(204).send();
  });
  app.post("/echo", async (request) => ({ got: request.body }));
  return app;
};

describe("empty JSON body tolerance (fastify 5 compat shim)", () => {
  it("accepts a body-less DELETE that claims application/json", async () => {
    const app = build();
    const res = await app.inject({
      method: "DELETE",
      url: "/thing/t1",
      headers: { "content-type": "application/json" },
    });
    // Without the shim, fastify 5 rejects at the parsing step with 400
    // FST_ERR_CTP_EMPTY_JSON_BODY before the handler runs.
    expect(res.statusCode).toBe(204);
    await app.close();
  });

  it("still parses a real JSON body", async () => {
    const app = build();
    const res = await app.inject({
      method: "POST",
      url: "/echo",
      headers: { "content-type": "application/json" },
      payload: { a: 1 },
    });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ got: { a: 1 } });
    await app.close();
  });

  it("still rejects malformed JSON with 400", async () => {
    const app = build();
    const res = await app.inject({
      method: "POST",
      url: "/echo",
      headers: { "content-type": "application/json" },
      payload: "{not json",
    });
    expect(res.statusCode).toBe(400);
    await app.close();
  });

  it("still blocks __proto__ poisoning (secure parser preserved)", async () => {
    const app = build();
    const res = await app.inject({
      method: "POST",
      url: "/echo",
      headers: { "content-type": "application/json" },
      payload: '{"__proto__": {"polluted": true}}',
    });
    // fastify's default secure parser errors on proto poisoning ("error"
    // mode); the request must not succeed with the poisoned body.
    expect(res.statusCode).toBe(400);
    await app.close();
  });
});
