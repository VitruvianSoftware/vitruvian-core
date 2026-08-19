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

import * as fs from "fs";
import * as path from "path";
import * as yaml from "js-yaml";
import { CLOUD_RUN_ANNOTATION, parseCloudRunRefs } from "./refs";

/**
 * Parses the annotations the repo actually ships, not a fixture.
 *
 * parseCloudRunRefs deliberately SKIPS malformed entries so one typo costs a
 * row rather than the whole card -- which means a typo is invisible at runtime:
 * the card renders, just missing an environment. This is the guard that makes
 * it visible, and it is why the assertion is `invalid` being empty rather than
 * `refs` being non-empty.
 */
const REPO = path.resolve(__dirname, "../../../../..");

describe("shipped catalog annotations", () => {
  const files = [
    "oauth-user-inspector/catalog-info.yaml",
    "tabula/catalog-info.yaml",
  ];

  it.each(files)("%s parses with no malformed entries", (rel: string) => {
    const docs = yaml.loadAll(
      fs.readFileSync(path.join(REPO, rel), "utf8"),
    ) as Array<{ metadata?: { annotations?: Record<string, string> } }>;

    let seen = 0;
    for (const doc of docs) {
      const raw = doc?.metadata?.annotations?.[CLOUD_RUN_ANNOTATION];
      if (!raw) continue;
      const { refs, invalid } = parseCloudRunRefs(raw);
      expect(invalid).toEqual([]);
      expect(refs.length).toBeGreaterThan(0);
      seen += refs.length;
    }
    expect(seen).toBeGreaterThan(0);
  });
});
