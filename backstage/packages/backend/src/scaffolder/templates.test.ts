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

import { load } from "js-yaml";

import { APP_NAME_PATTERN, APP_RENDER_ACTION_ID } from "./appRender";

// ---------------------------------------------------------------------------
// Drift guard for the non-stamp scaffolder templates.
//
// stamp-application has its own, deeper drift guard; these three templates
// were added later and shipped with kebab-case name patterns, missing
// sourcePath, and unreferenced parameters.  This test prevents regression.
// ---------------------------------------------------------------------------

const REPO_ROOT = resolve(__dirname, "../../../../..");
const ROOT_CATALOG = resolve(REPO_ROOT, "catalog-info.yaml");

/** Every template that is NOT stamp-application — add new ones here. */
const TEMPLATES = [
  "backstage/templates/cloud-run-service/template.yaml",
  "backstage/templates/mcp-server/template.yaml",
  "backstage/templates/k8s-canary-microservice/template.yaml",
] as const;

function loadTemplate(relPath: string): any {
  return load(readFileSync(resolve(REPO_ROOT, relPath), "utf8"));
}

describe.each(TEMPLATES)("Scaffolder drift guard for %s", (relPath) => {
  const template = loadTemplate(relPath);
  const steps = (): any[] => template.spec.steps;
  const stepFor = (action: string): any =>
    steps().find((s: any) => s.action === action);

  it("is a valid v1beta3 Template", () => {
    expect(template.apiVersion).toBe("scaffolder.backstage.io/v1beta3");
    expect(template.kind).toBe("Template");
    expect(template.metadata?.name).toBeDefined();
    expect(template.metadata?.title).toBeDefined();
    expect(template.metadata?.description).toBeDefined();
    expect(template.spec?.owner).toBe("group:default/platform-team");
    expect(template.spec?.type).toBe("service");
    expect(Array.isArray(template.spec?.parameters)).toBe(true);
    expect(Array.isArray(template.spec?.steps)).toBe(true);
  });

  it("runs fetch → render → pull request, in that order", () => {
    expect(steps().map((s: any) => s.action)).toEqual([
      "fetch:plain",
      APP_RENDER_ACTION_ID,
      "publish:github:pull-request",
    ]);
  });

  it("fetches vitruvian-core itself", () => {
    expect(stepFor("fetch:plain").input.url).toBe(
      "https://github.com/VitruvianSoftware/vitruvian-core",
    );
  });

  it("uses a name pattern compatible with vitruvian:app:render", () => {
    // The action validates against APP_NAME_PATTERN (snake_case). The form's
    // pattern must be equal or stricter — never looser — or the form accepts
    // values the action rejects at run time. An mcp_ prefix is fine as long
    // as the rest is also snake_case.
    const pages: any[] = template.spec.parameters;
    const nameProp = pages
      .flatMap((p: any) => Object.entries(p.properties ?? {}))
      .find(([key]: [string, any]) => key === "name")?.[1] as any;
    expect(nameProp).toBeDefined();
    expect(nameProp.pattern).toBeDefined();

    const formPattern = new RegExp(nameProp.pattern);
    // Must reject kebab-case (the original bug)
    expect(formPattern.test("my-service")).toBe(false);
    expect(formPattern.test("mcp-jira")).toBe(false);
    // Must reject double underscores
    expect(formPattern.test("a__b")).toBe(false);

    // The pattern must be a subset of APP_NAME_PATTERN: anything it accepts
    // must also be accepted by the action. Generate a valid name from the
    // placeholder and verify both patterns agree.
    const placeholder = nameProp["ui:placeholder"] as string;
    expect(formPattern.test(placeholder)).toBe(true);
    expect(APP_NAME_PATTERN.test(placeholder)).toBe(true);
  });

  it("publishes ONLY the staged subtree, not the whole checkout", () => {
    // Without sourcePath the publish action serialises the entire workspace —
    // a full vitruvian-core checkout — and creates one blob per file,
    // sequentially, against GitHub's 500/hour content-creation limit.
    const pr = stepFor("publish:github:pull-request").input;
    expect(pr.sourcePath).toBe("${{ steps.render.output.stagePath }}");
  });

  it("opens a DRAFT pull request against vitruvian-core", () => {
    const pr = stepFor("publish:github:pull-request").input;
    expect(pr.repoUrl).toBe(
      "github.com?owner=VitruvianSoftware&repo=vitruvian-core",
    );
    expect(pr.draft).toBe(true);
  });

  it("does not collect parameters it never uses", () => {
    // A field that is collected and then quietly dropped is worse than no
    // field, because it looks like a decision the user got to make.
    const declared: string[] = template.spec.parameters.flatMap((page: any) =>
      Object.keys(page.properties ?? {}),
    );
    const body = JSON.stringify({
      steps: template.spec.steps,
      output: template.spec.output,
    });
    const referenced = [
      ...new Set(
        [...body.matchAll(/parameters\.([A-Za-z0-9_]+)/g)].map((m) => m[1]),
      ),
    ];

    // Every declared parameter must appear somewhere in steps or output.
    expect(declared.filter((p) => !referenced.includes(p))).toEqual([]);
    // Every referenced parameter must be declared in the form.
    expect(referenced.filter((p) => !declared.includes(p))).toEqual([]);
  });

  it("is registered in the root catalog templates Location", () => {
    const catalog = readFileSync(ROOT_CATALOG, "utf8");
    expect(catalog).toContain(`- ./${relPath}`);
    const locations = catalog
      .split("---")
      .filter((doc) => doc.includes("kind: Location"));
    const templatesLocation = locations.find((doc) =>
      doc.includes("name: vitruvian-core-templates"),
    );
    expect(templatesLocation).toBeDefined();
    expect(templatesLocation).toContain(relPath);
  });
});
