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

// Passthrough so the ACTION'S OWN schema can be read without loading the
// scaffolder runtime — see "the action contract" below.
jest.mock("@backstage/plugin-scaffolder-node", () => ({
  executeShellCommand: jest.fn(),
  createTemplateAction: (options: unknown) => options,
}));

import { readFileSync } from "fs";
import { resolve } from "path";

import { load } from "js-yaml";

import { APP_RENDER_ACTION_ID, createAppRenderAction } from "./appRender";

// The drift guard between three things that are edited independently and only
// disagree in production:
//
//   1. template.yaml, which names actions and passes them inputs,
//   2. the action's own zod input schema, which decides what those inputs mean,
//   3. src/index.ts, which decides which actions exist at all.
//
// A template naming an action nobody registered fails at RUN time, on the
// user's task, with "Template action with ID '...' is not registered" — long
// after review. A template passing an input the action does not declare is
// worse: v2 schemas strip unknown keys, so it silently does nothing.

const REPO_ROOT = resolve(__dirname, "../../../../..");
const TEMPLATE_PATH = resolve(
  REPO_ROOT,
  "backstage/templates/stamp-application/template.yaml",
);
const ROOT_CATALOG = resolve(REPO_ROOT, "catalog-info.yaml");
const BACKEND_INDEX = resolve(__dirname, "../index.ts");

/**
 * Actions this backend registers, each tied to the line in src/index.ts that
 * registers it. Verified against the installed packages:
 *   fetch:plain                  — @backstage/plugin-scaffolder-backend@4.0.2,
 *                                  dist/scaffolder/actions/builtin/fetch/plain.cjs.js
 *   publish:github:pull-request  — @backstage/plugin-scaffolder-backend-module-github@0.9.12,
 *                                  dist/actions/githubPullRequest.cjs.js
 */
const REGISTERED_ACTIONS: Record<string, string> = {
  "fetch:plain": '@backstage/plugin-scaffolder-backend"',
  "publish:github:pull-request":
    '@backstage/plugin-scaffolder-backend-module-github"',
  [APP_RENDER_ACTION_ID]: "scaffolderModuleAppRender",
};

const template = load(readFileSync(TEMPLATE_PATH, "utf8")) as any;
const backendIndex = readFileSync(BACKEND_INDEX, "utf8");

const steps = (): any[] => template.spec.steps;
const stepFor = (action: string): any =>
  steps().find((step) => step.action === action);

describe("the stamp-application template", () => {
  it("is a v1beta3 Template", () => {
    expect(template.apiVersion).toBe("scaffolder.backstage.io/v1beta3");
    expect(template.kind).toBe("Template");
    expect(template.metadata.name).toBe("stamp-application");
    expect(template.spec.owner).toBe("group:default/platform-team");
  });

  it("declares the P1 form", () => {
    const [page1, advanced] = template.spec.parameters;
    expect(Object.keys(page1.properties)).toEqual([
      "name",
      "description",
      "owner",
      "language",
    ]);
    expect(page1.required).toEqual([
      "name",
      "description",
      "owner",
      "language",
    ]);

    // The name reaches gazelle as a directory and a target name; the action
    // rejects anything else, and the form should not let it get that far.
    expect(page1.properties.name.pattern).toBe("^[a-z][a-z0-9_]*$");
    expect(page1.properties.name.maxLength).toBe(30);

    expect(page1.properties.owner["ui:field"]).toBe("OwnerPicker");

    // An enum with one member: P2 adds languages without re-shaping the form.
    expect(page1.properties.language.enum).toEqual(["go"]);
    expect(page1.properties.language.default).toBe("go");

    expect(advanced.title).toBe("Advanced");
    expect(Object.keys(advanced.properties)).toEqual(["targetPath"]);
    // NOT a `default:`. Parameters are a plain JSON Schema — `${{ }}` is only
    // substituted in `steps` — so a default of `apps/${{ parameters.name }}`
    // would land in the field literally and the action would reject it. The
    // default lives in the action; the placeholder documents it.
    expect(advanced.properties.targetPath.default).toBeUndefined();
    expect(advanced.properties.targetPath["ui:placeholder"]).toBe(
      "apps/<name>",
    );
  });

  it("names only actions this backend registers", () => {
    expect(steps().length).toBeGreaterThan(0);
    for (const step of steps()) {
      expect(typeof step.id).toBe("string");
      expect(typeof step.name).toBe("string");
      expect(Object.keys(REGISTERED_ACTIONS)).toContain(step.action);
      // Registered where, exactly: a template naming an action no longer added
      // in index.ts fails at run time on a user's task.
      expect(backendIndex).toContain(REGISTERED_ACTIONS[step.action]);
    }
  });

  it("runs fetch → render → pull request, in that order", () => {
    expect(steps().map((step) => step.action)).toEqual([
      "fetch:plain",
      APP_RENDER_ACTION_ID,
      "publish:github:pull-request",
    ]);
  });

  describe("the action contract", () => {
    // The action's OWN schema, imported rather than mirrored — a mirror is a
    // second copy that drifts, which is the thing this test exists to catch.
    const action = createAppRenderAction() as any;
    const declared = Object.keys(action.schema.input);

    it("passes the render step only inputs the action declares", () => {
      const passed = Object.keys(stepFor(APP_RENDER_ACTION_ID).input);
      expect(declared).toEqual(expect.arrayContaining(passed));
      // v2 schemas STRIP unknown keys rather than erroring, so an input the
      // action does not declare would silently do nothing.
      expect(passed.filter((key) => !declared.includes(key))).toEqual([]);
    });

    it("passes the inputs the action requires", () => {
      const passed = Object.keys(stepFor(APP_RENDER_ACTION_ID).input);
      expect(passed).toEqual(expect.arrayContaining(["name", "language"]));
    });

    it("consumes the outputs the action promises", () => {
      const rendered = JSON.stringify(template.spec.output);
      for (const key of Object.keys(action.schema.output)) {
        expect(rendered).toContain(`steps.render.output.${key}`);
      }
    });
  });

  it("references only parameters the form declares", () => {
    const declared = new Set(
      template.spec.parameters.flatMap((page: any) =>
        Object.keys(page.properties ?? {}),
      ),
    );
    const body = JSON.stringify({
      steps: template.spec.steps,
      output: template.spec.output,
    });
    const referenced = [...body.matchAll(/parameters\.([A-Za-z0-9_]+)/g)].map(
      (match) => match[1],
    );

    expect(referenced.length).toBeGreaterThan(0);
    expect([...new Set(referenced)].filter((p) => !declared.has(p))).toEqual(
      [],
    );
  });

  it("opens a DRAFT pull request against vitruvian-core", () => {
    const pr = stepFor("publish:github:pull-request").input;
    expect(pr.repoUrl).toBe(
      "github.com?owner=VitruvianSoftware&repo=vitruvian-core",
    );
    expect(pr.branchName).toBe("stamp/${{ parameters.name }}");
    expect(pr.title).toBe(
      "feat(${{ parameters.name }}): stamp application via initializer",
    );
    // P1 ships no auto-merge (that is P3); nothing lands unread.
    expect(pr.draft).toBe(true);
  });

  it("discloses both surprises in the pull request body", () => {
    const body = stepFor("publish:github:pull-request").input.description;
    // ADR-019 disclose-and-include: the action edits a file nobody named.
    expect(body).toContain("catalog-info.yaml");
    expect(body).toContain("vitruvian-core-apps");
    // The known P1 gap, so the reviewer is not surprised by a red gate.
    expect(body).toContain("license headers");
    expect(body).toContain("//tools/license:add");
  });

  it("fetches vitruvian-core itself, never aspect-workflows-template", () => {
    // ADR-026: the engine that renders is the TARGET repository's own.
    expect(stepFor("fetch:plain").input.url).toBe(
      "https://github.com/VitruvianSoftware/vitruvian-core",
    );
    expect(JSON.stringify(template)).not.toContain(
      "aspect-workflows-template/",
    );
  });

  it("is registered in the root catalog, or Backstage never serves it", () => {
    // The template existing on disk does nothing; the catalog has to point at
    // it. This is the same drift the githubOrg provider test guards.
    const catalog = readFileSync(ROOT_CATALOG, "utf8");
    expect(catalog).toContain(
      "- ./backstage/templates/stamp-application/template.yaml",
    );
    const locations = (
      readFileSync(ROOT_CATALOG, "utf8").split("---") as string[]
    ).filter((doc) => doc.includes("kind: Location"));
    const templatesLocation = locations.find((doc) =>
      doc.includes("name: vitruvian-core-templates"),
    );
    expect(templatesLocation).toBeDefined();
    // Deliberately NOT in vitruvian-core-apps: that list is per-app component
    // metadata and the render action appends to it automatically.
    const appsLocation = locations.find((doc) =>
      doc.includes("name: vitruvian-core-apps"),
    );
    expect(appsLocation).not.toContain("templates/stamp-application");
  });

  it("needs no app-config change — Template is already an allowed kind", () => {
    // Both the repo config and the DEPLOYED chart values, because the container
    // runs the ConfigMap the values render, not backstage/app-config.yaml.
    for (const file of [
      "backstage/app-config.yaml",
      "gitops/argocd/platform/backstage/values.yaml",
    ]) {
      expect(readFileSync(resolve(REPO_ROOT, file), "utf8")).toMatch(
        /allow:.*Template/,
      );
    }
  });
});
