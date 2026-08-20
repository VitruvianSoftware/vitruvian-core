// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import { readFileSync, readdirSync } from "fs";
import { resolve, join } from "path";
import { loadAll } from "js-yaml";

/**
 * Every grafana/dashboard-selector must resolve to a tag on a dashboard we
 * actually ship.
 *
 * The selector is matched as a TAG when it is a single word (/^[\w-]+$/), and
 * tag matching is CASE-SENSITIVE. A selector that matches nothing does not
 * error -- the card renders empty, which looks like "no dashboards yet" rather
 * than a typo. Nothing else in CI compares the two sides.
 *
 * Deliberately checks only git-managed dashboards: a selector satisfied solely
 * by a dashboard someone made in the UI would break the moment Grafana is
 * rebuilt from git.
 */
const REPO_ROOT = resolve(__dirname, "../../../../..");
const DASH_DIR = resolve(
  REPO_ROOT,
  "gitops/argocd/platform/grafana-dashboards",
);

const shippedTags = (): Map<string, string[]> => {
  const byTag = new Map<string, string[]>();
  for (const f of readdirSync(DASH_DIR).filter((f) => f.endsWith(".json"))) {
    const d = JSON.parse(readFileSync(join(DASH_DIR, f), "utf8"));
    for (const t of d.tags ?? []) {
      byTag.set(t, [...(byTag.get(t) ?? []), f]);
    }
  }
  return byTag;
};

const selectors = (): Array<{
  entity: string;
  selector: string;
  file: string;
}> => {
  const out: Array<{ entity: string; selector: string; file: string }> = [];
  const walk = (dir: string, depth = 0) => {
    if (depth > 3) return;
    for (const e of readdirSync(dir, { withFileTypes: true })) {
      if (e.name === "node_modules" || e.name.startsWith(".")) continue;
      const p = join(dir, e.name);
      if (e.isDirectory()) walk(p, depth + 1);
      else if (e.name === "catalog-info.yaml") {
        for (const doc of loadAll(readFileSync(p, "utf8")) as any[]) {
          const sel =
            doc?.metadata?.annotations?.["grafana/dashboard-selector"];
          if (sel)
            out.push({ entity: doc.metadata.name, selector: sel, file: p });
        }
      }
    }
  };
  walk(REPO_ROOT);
  return out;
};

describe("grafana/dashboard-selector annotations", () => {
  const tags = shippedTags();
  const all = selectors();

  it("finds the selectors that are actually in the repo", () => {
    expect(all.length).toBeGreaterThan(0);
  });

  it.each(all.map((s) => [s.entity, s.selector]))(
    "%s -> tag %s exists on a git-managed dashboard",
    (_entity, selector) => {
      // Only single-word selectors are tag-matched; anything else is a query.
      if (!/^[\w-]+$/.test(String(selector))) return;
      const hit = tags.get(String(selector));
      if (!hit) {
        // Fail with the available tags in the message: the usual cause is a
        // case mismatch, and seeing the real list makes that obvious.
        throw new Error(
          `no shipped dashboard carries the tag "${selector}". ` +
            `Tag matching is CASE-SENSITIVE. Available tags: ` +
            [...tags.keys()].sort().join(", "),
        );
      }
      expect(hit.length).toBeGreaterThan(0);
    },
  );
});
