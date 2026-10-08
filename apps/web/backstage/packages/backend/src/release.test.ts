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

import { readFileSync } from "fs";
import { resolve } from "path";

// Backstage's packages are built and tested upstream as one set per release.
// A tree that mixes releases can install and pass unit tests and still fail to
// start: on 2026-10-07 a single bumped package needed a newer
// backend-plugin-api than the rest and the backend crashed at boot (#2865).
// So every @backstage/* dependency must be the version the recorded release
// ships. To move to another release, run apps/web/backstage/bump-release.sh;
// do not bump one package on its own.

const backstageRoot = resolve(__dirname, "../../..");
const readJson = (path: string) =>
  JSON.parse(readFileSync(resolve(backstageRoot, path), "utf8"));

const manifest: { releaseVersion: string; packages: Record<string, string> } =
  readJson("release-manifest.json");

describe("Backstage release coherence", () => {
  it("records the same release in backstage.json and the manifest", () => {
    expect(readJson("backstage.json").version).toBe(manifest.releaseVersion);
  });

  it.each(["packages/backend/package.json", "packages/app/package.json"])(
    "%s uses the release's version of every @backstage package",
    (file) => {
      const pkg = readJson(file);
      const deps: Record<string, string> = {
        ...pkg.dependencies,
        ...pkg.devDependencies,
      };
      const offRelease = Object.entries(deps)
        .filter(([name]) => name.startsWith("@backstage/"))
        .filter(([name]) => manifest.packages[name] !== undefined)
        .filter(
          ([name, range]) =>
            range.replace(/^[~^]/, "") !== manifest.packages[name],
        )
        .map(
          ([name, range]) =>
            `${name} is ${range}, release ${manifest.releaseVersion} ships ${manifest.packages[name]}`,
        );
      expect(offRelease).toEqual([]);
    },
  );

  it("covers the packages the backend cannot start without", () => {
    for (const name of [
      "@backstage/backend-defaults",
      "@backstage/backend-plugin-api",
    ]) {
      expect(manifest.packages[name]).toBeDefined();
    }
  });
});
