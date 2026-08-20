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

/**
 * Integration test for `vitruvian:app:render` against the REAL Aspect CLI and
 * the REAL initializer engine — no mocked shell, no fixture output.
 *
 * Skipped unless ASPECT_E2E is set, because it needs `aspect` on PATH (the
 * runtime image vendors it; a laptop may not have it, and CI's Node lane
 * certainly does not). Run it locally with:
 *
 *   cd backstage/packages/backend && \
 *     ASPECT_E2E=1 pnpm exec jest src/scaffolder/appRenderE2e
 *
 * The host it renders into is a THROWAWAY temp directory built from this repo's
 * own tools/initializer tree. It never touches the checkout: the engine clears
 * `--out` before rendering, so pointing this at a working tree would delete
 * whatever is there.
 */

import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import * as path from "path";

import {
  appendCatalogTarget,
  findAspectBinary,
  renderApplication,
} from "./appRender";

const REPO_ROOT = path.resolve(__dirname, "../../../../..");

const CATALOG = `apiVersion: backstage.io/v1alpha1
kind: Location
metadata:
  name: vitruvian-core-apps
spec:
  targets:
    - ./backstage/catalog-info.yaml
    - ./tabula/catalog-info.yaml
`;

const silentLogger = () => {
  const lines: string[] = [];
  const record =
    (level: string) =>
    (message: string): void => {
      lines.push(`${level}: ${message}`);
    };
  const service: any = {
    error: record("error"),
    warn: record("warn"),
    info: record("info"),
    debug: record("debug"),
  };
  service.child = () => service;
  return { lines, service };
};

/**
 * A real stamping target: this repo's actual engine tree, plus the smallest host
 * the engine needs to resolve the gazelle contract (a go.mod to walk up to and a
 * root build file carrying `# gazelle:prefix`).
 */
const makeHost = (): string => {
  const host = mkdtempSync(path.join(tmpdir(), "app-render-e2e-"));
  cpSync(
    path.join(REPO_ROOT, "tools/initializer"),
    path.join(host, "tools/initializer"),
    { recursive: true },
  );
  writeFileSync(
    path.join(host, "MODULE.aspect"),
    'use_task("tools/initializer/tasks.axl", "render_app")\n' +
      'use_task("tools/initializer/tasks.axl", "check_metadata")\n',
  );
  writeFileSync(
    path.join(host, "go.mod"),
    "module example.com/e2e_host\n\ngo 1.26.2\n",
  );
  writeFileSync(
    path.join(host, "BUILD"),
    "# gazelle:prefix github.com/example/e2e-host\n# gazelle:build_file_name BUILD\n",
  );
  writeFileSync(path.join(host, "catalog-info.yaml"), CATALOG);
  return host;
};

const describeE2e = process.env.ASPECT_E2E ? describe : describe.skip;

describeE2e("vitruvian:app:render against the real engine", () => {
  let host: string;

  beforeAll(() => {
    if (!findAspectBinary()) {
      throw new Error(
        "ASPECT_E2E is set but `aspect` is not on PATH; install the vendored " +
          "vintage or unset ASPECT_E2E.",
      );
    }
  });

  beforeEach(() => {
    host = makeHost();
  });

  afterEach(() => {
    rmSync(host, { recursive: true, force: true });
  });

  it("renders the go starter and registers it in the root catalog", async () => {
    const log = silentLogger();
    const result = await renderApplication({
      workspacePath: host,
      name: "order_service",
      language: "go",
      logger: log.service,
    });

    expect(result.appPath).toBe("apps/order_service");
    expect(result.renderedFiles).toEqual([
      "apps/order_service/BUILD",
      "apps/order_service/README.md",
      "apps/order_service/catalog-info.yaml",
      "apps/order_service/main.go",
      "apps/order_service/main_test.go",
    ]);

    // The gazelle contract the engine derives from cwd + --out: the import path
    // comes from the HOST's `# gazelle:prefix`, and the build file is named the
    // host's way. Getting cwd wrong silently produces a different answer here.
    const build = readFileSync(
      path.join(host, "apps/order_service/BUILD"),
      "utf8",
    );
    expect(build).toContain(
      'importpath = "github.com/example/e2e-host/apps/order_service"',
    );
    expect(build).toContain('name = "order_service"');

    expect(result.catalogUpdated).toBe(true);
    expect(readFileSync(path.join(host, "catalog-info.yaml"), "utf8")).toBe(
      appendCatalogTarget(CATALOG, "apps/order_service").content,
    );
  }, 120_000);

  it("refuses to stamp over what it just rendered", async () => {
    const log = silentLogger();
    await renderApplication({
      workspacePath: host,
      name: "order_service",
      language: "go",
      logger: log.service,
    });
    const mainGo = readFileSync(
      path.join(host, "apps/order_service/main.go"),
      "utf8",
    );

    await expect(
      renderApplication({
        workspacePath: host,
        name: "order_service",
        language: "go",
        logger: log.service,
      }),
    ).rejects.toThrow(/already exists in the target repository/);

    // The engine would have cleared and re-rendered; the refusal is what keeps
    // the second run from showing up as a mass deletion in the PR.
    expect(
      readFileSync(path.join(host, "apps/order_service/main.go"), "utf8"),
    ).toBe(mainGo);
  }, 120_000);

  it("rejects a host that has not been onboarded", async () => {
    rmSync(path.join(host, "MODULE.aspect"));
    await expect(
      renderApplication({
        workspacePath: host,
        name: "order_service",
        language: "go",
        logger: silentLogger().service,
      }),
    ).rejects.toThrow(/vitruvian-core#1815/);
  });
});
