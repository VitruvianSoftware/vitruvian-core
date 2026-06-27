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

// Parity guard between what the API Explorer UI OFFERS and what the server will
// SERVE. The frontend ships a per-provider endpoint catalog
// (frontend/utils/apiEndpoints.ts); the server independently owns the table
// /api/explore resolves against (server/apiEndpoints.server.ts), and after the
// SSRF hardening it FAILS CLOSED on any (provider, endpointId) not in that
// table. So a frontend-only endpoint would render a button that returns
// 400 "unknown endpoint". This test keeps the two lists honest mirrors so the
// UI can never advertise something the server refuses. (Per dev principle
// §2.19, the fail-closed change ships with the test that guards its UX.)

import * as fs from "fs";
import * as path from "path";
import { EXPLORE_ENDPOINTS } from "../apiEndpoints.server.js";

/** Extract provider -> endpoint-id list from the frontend catalog source. */
function frontendCatalog(): Record<string, string[]> {
  const src = fs.readFileSync(
    path.resolve(__dirname, "../../frontend/utils/apiEndpoints.ts"),
    "utf8",
  );
  const out: Record<string, string[]> = {};
  let provider: string | null = null;
  for (const line of src.split("\n")) {
    const providerMatch = /case "(\w+)":/.exec(line);
    if (providerMatch) {
      provider = providerMatch[1];
      out[provider] = [];
      continue;
    }
    const idMatch = /^\s*id:\s*"([^"]+)"/.exec(line);
    if (idMatch && provider) {
      out[provider].push(idMatch[1]);
    }
  }
  return out;
}

const sortedUnique = (xs: string[]): string[] => [...new Set(xs)].sort();

describe("API Explorer endpoint parity (UI catalog <-> server table)", () => {
  const frontend = frontendCatalog();
  const server: Record<string, string[]> = {};
  for (const [provider, defs] of Object.entries(
    EXPLORE_ENDPOINTS as Record<string, Record<string, unknown>>,
  )) {
    server[provider] = Object.keys(defs);
  }

  // Guard against the parser silently matching nothing (which would make every
  // assertion below vacuously pass).
  it("parses a non-empty frontend catalog", () => {
    const total = Object.values(frontend).reduce((n, ids) => n + ids.length, 0);
    expect(Object.keys(frontend).length).toBeGreaterThan(0);
    expect(total).toBeGreaterThan(0);
  });

  it("offers the same provider set on both sides", () => {
    expect(Object.keys(frontend).sort()).toEqual(Object.keys(server).sort());
  });

  const providers = sortedUnique([
    ...Object.keys(frontend),
    ...Object.keys(server),
  ]);
  for (const provider of providers) {
    it(`'${provider}' endpoints match (no UI button the server would 400)`, () => {
      expect(sortedUnique(frontend[provider] ?? [])).toEqual(
        sortedUnique(server[provider] ?? []),
      );
    });
  }
});
