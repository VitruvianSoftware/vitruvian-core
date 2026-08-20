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
import { createRequire } from "module";
import { dirname, resolve } from "path";

import { load } from "js-yaml";
import { createPublishGithubPullRequestAction } from "@backstage/plugin-scaffolder-backend-module-github";

// The drift guard for the two steps this repo does NOT own.
//
// stampApplicationTemplate.test.ts checks our own action's schema; these are
// upstream, they change on every Backstage bump, and a renamed or removed input
// is invisible until a user's task fails. v2 schemas STRIP unknown keys rather
// than erroring, so `sourcePath` quietly disappearing would not fail loudly --
// it would publish the entire 4,000-file workspace and 403 on GitHub's rate
// limit instead.
//
// Built with stub deps: only the SCHEMA is read, no handler ever runs.

const REPO_ROOT = resolve(__dirname, "../../../../..");
const template = load(
  readFileSync(
    resolve(REPO_ROOT, "backstage/templates/stamp-application/template.yaml"),
    "utf8",
  ),
) as any;

const stepFor = (action: string): any =>
  template.spec.steps.find((step: any) => step.action === action);

/** Input names an action accepts, from its generated JSON Schema. */
const inputsOf = (action: any): string[] =>
  Object.keys(action.schema?.input?.properties ?? {});

/** Output names an action promises. */
const outputsOf = (action: any): string[] =>
  Object.keys(action.schema?.output?.properties ?? {});

/**
 * `publish:github:pull-request` is CONSTRUCTED, with stub deps -- only the
 * schema is read, no handler ever runs. This is the action that matters most
 * here: `sourcePath` is what keeps the publish from uploading the whole
 * workspace.
 */
const publishAction = () =>
  createPublishGithubPullRequestAction({
    integrations: {} as any,
    config: {} as any,
  });

/**
 * `fetch:plain` is READ FROM ITS DIST SOURCE rather than constructed.
 *
 * Constructing it means importing @backstage/plugin-scaffolder-backend, which
 * (a) pulls in isolated-vm, a native addon with no prebuild for this Node, and
 * (b) then fails inside backend-plugin-api's paths.cjs.js, which resolves
 * '@backstage/plugin-scaffolder-backend/package.json' from its OWN store
 * directory -- unreachable under this repo's deliberate hoist=false. Neither is
 * a real defect: production runs the bundled dist, not this layout. Stubbing
 * both would be a pile of mocks guarding a one-key step, so this reads the
 * declared input names straight out of the shipped file instead. Narrow, but
 * hermetic and honest about what it is.
 */
const fetchPlainInputs = (): string[] => {
  const req = createRequire(__filename);
  const pkg = req.resolve("@backstage/plugin-scaffolder-backend/package.json");
  const source = readFileSync(
    resolve(dirname(pkg), "dist/scaffolder/actions/builtin/fetch/plain.cjs.js"),
    "utf8",
  );
  const inputBlock = source.slice(
    source.indexOf("input: {"),
    source.indexOf("async handler"),
  );
  return [...inputBlock.matchAll(/^\s{8}([a-zA-Z][a-zA-Z0-9]*): \(z\)/gm)].map(
    (m) => m[1],
  );
};

describe("the upstream actions the template drives", () => {
  it("registers the id the template names", () => {
    expect(publishAction().id).toBe("publish:github:pull-request");
  });

  it("accepts every input the fetch step passes", () => {
    const declared = fetchPlainInputs();
    // Guard the guard: an empty list would make the assertion below vacuous.
    expect(declared).toContain("url");
    const passed = Object.keys(stepFor("fetch:plain").input);
    expect(passed.filter((key) => !declared.includes(key))).toEqual([]);
  });

  it("accepts every input the publish step passes", () => {
    const declared = inputsOf(publishAction());
    const passed = Object.keys(stepFor("publish:github:pull-request").input);
    expect(passed.filter((key) => !declared.includes(key))).toEqual([]);
  });

  it("still supports sourcePath, which the publish step depends on", () => {
    // If a Backstage bump ever removes or renames this, the template would
    // silently fall back to serialising the whole workspace.
    expect(inputsOf(publishAction())).toContain("sourcePath");
  });

  it("still emits remoteUrl, which the template links to", () => {
    expect(outputsOf(publishAction())).toContain("remoteUrl");
    expect(JSON.stringify(template.spec.output)).toContain(
      "steps.pr.output.remoteUrl",
    );
  });
});
