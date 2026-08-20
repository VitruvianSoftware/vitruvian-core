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

// The real package pulls in isomorphic-git, winston and most of the scaffolder;
// none of it is exercised here and loading it would make this suite slow and
// flaky. createTemplateAction is a passthrough so the action definition itself
// stays inspectable.
jest.mock("@backstage/plugin-scaffolder-node", () => ({
  executeShellCommand: jest.fn(),
  createTemplateAction: (options: unknown) => options,
}));

import {
  chmodSync,
  mkdtempSync,
  mkdirSync,
  readFileSync,
  realpathSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "fs";
import { tmpdir } from "os";
import * as path from "path";

import { executeShellCommand } from "@backstage/plugin-scaffolder-node";

import {
  APP_RENDER_ACTION_ID,
  appendCatalogTarget,
  assertPathMatchesName,
  assertStampingTarget,
  assertValidAppName,
  catalogTargetOf,
  createAppRenderAction,
  findAspectBinary,
  normaliseTargetPath,
  registersRenderApp,
  renderApplication,
  resolveContainedOutput,
  type ShellRunner,
} from "./appRender";

const logger = () => {
  const lines: string[] = [];
  const record =
    (level: string) =>
    (message: string): void => {
      lines.push(`${level}: ${message}`);
    };
  return {
    lines,
    service: {
      error: record("error"),
      warn: record("warn"),
      info: record("info"),
      debug: record("debug"),
      child: () => logger().service,
    } as any,
  };
};

const MODULE_ASPECT = `# AXL dependencies
use_task("tools/initializer/tasks.axl", "render_app")
use_task("tools/initializer/tasks.axl", "check_metadata")
`;

const CATALOG = `apiVersion: backstage.io/v1alpha1
kind: System
metadata:
  name: vitruvian-core
spec:
  owner: platform-team
---
apiVersion: backstage.io/v1alpha1
kind: Location
metadata:
  name: vitruvian-core-apps
  description: Per-app component metadata
spec:
  targets:
    - ./backstage/catalog-info.yaml
    - ./devx/catalog-info.yaml
    - ./tabula/catalog-info.yaml
    # Platform infrastructure we operate (not applications we build)
    - ./gitops/catalog-info.yaml
---
apiVersion: backstage.io/v1alpha1
kind: Location
metadata:
  name: vitruvian-external-repos
spec:
  type: url
  targets:
    - https://github.com/VitruvianSoftware/backstage-go/blob/main/catalog-info.yaml
`;

/** The five files the go starter renders, per tools/initializer/app/go. */
const STARTER_FILES = [
  "BUILD",
  "README.md",
  "catalog-info.yaml",
  "main.go",
  "main_test.go",
];

let workspaces: string[] = [];

/** A minimal but REAL stamping target: the predicate files and nothing else. */
const makeWorkspace = (
  opts: {
    config?: boolean;
    moduleAspect?: string | false;
    catalog?: string | false;
  } = {},
): string => {
  const ws = mkdtempSync(path.join(tmpdir(), "app-render-"));
  workspaces.push(ws);
  if (opts.config !== false) {
    mkdirSync(path.join(ws, "tools/initializer"), { recursive: true });
    writeFileSync(
      path.join(ws, "tools/initializer/config.json"),
      JSON.stringify({ languages: { go: {} } }),
    );
  }
  if (opts.moduleAspect !== false) {
    writeFileSync(
      path.join(ws, "MODULE.aspect"),
      opts.moduleAspect ?? MODULE_ASPECT,
    );
  }
  if (opts.catalog !== false) {
    writeFileSync(path.join(ws, "catalog-info.yaml"), opts.catalog ?? CATALOG);
  }
  writeFileSync(path.join(ws, "go.mod"), "module example.com/host\n");
  return ws;
};

/** Stands in for the engine: writes the files a real render would write. */
const renderStub = async ({ args }: { args: string[] }): Promise<void> => {
  const out = args[args.indexOf("--out") + 1];
  mkdirSync(out, { recursive: true });
  for (const file of STARTER_FILES) {
    writeFileSync(path.join(out, file), `// ${file}\n`);
  }
};

const fakeEngine = (): jest.MockedFunction<ShellRunner> =>
  jest.fn(renderStub) as unknown as jest.MockedFunction<ShellRunner>;

beforeEach(() => {
  // The default `exec` is the (mocked) package export; give it the same
  // behaviour so the action-definition tests exercise the real default path.
  (executeShellCommand as unknown as jest.Mock).mockImplementation(renderStub);
});

afterEach(() => {
  for (const ws of workspaces) rmSync(ws, { recursive: true, force: true });
  workspaces = [];
  jest.clearAllMocks();
});

describe("input validation", () => {
  it.each([
    ["Order_Service", "capitalised"],
    ["order-service", "kebab-case"],
    ["orderService", "camelCase"],
    ["order__service", "doubled underscore"],
    ["_order", "leading underscore"],
    ["order_", "trailing underscore"],
    ["2fast", "leading digit"],
    ["", "empty"],
  ])("rejects %s (%s) with a form-shaped message", (name) => {
    expect(() => assertValidAppName(name)).toThrow(/is not snake_case/);
  });

  it.each(["order_service", "api", "a1", "order_service_v2"])(
    "accepts %s",
    (name) => {
      expect(() => assertValidAppName(name)).not.toThrow();
    },
  );

  it("defaults targetPath to apps/<name>", () => {
    expect(normaliseTargetPath("order_service")).toBe("apps/order_service");
  });

  it("normalises a caller-supplied path", () => {
    expect(normaliseTargetPath("api", "./services/api/")).toBe("services/api");
  });

  it.each(["../escape/api", "services/../../api", "/abs/api", ".", ""])(
    "refuses %s",
    (given) => {
      // The empty string falls back to the default, so assert on the shape
      // rather than on a throw for that one.
      if (given === "") {
        expect(normaliseTargetPath("api", given)).toBe("apps/api");
        return;
      }
      expect(() => normaliseTargetPath("api", given)).toThrow();
    },
  );

  it("fails early when the directory name does not match the app name", () => {
    expect(() => assertPathMatchesName("order_service", "apps/orders")).toThrow(
      /ends in "orders" but the application is "order_service".*Use apps\/order_service/s,
    );
  });
});

describe("containment against a symlink committed in the fetched repo", () => {
  // The lexical guards all pass for `link/order_service` when the repo ships
  // `link -> /somewhere/else`: nothing in the STRING escapes the workspace.
  // The engine's unconditional remove_dir_all(--out) would then run outside the
  // repository, in the pod's filesystem.

  it("resolves a plain path to a real path inside the workspace", async () => {
    const ws = makeWorkspace();
    await expect(
      resolveContainedOutput(ws, "apps/order_service"),
    ).resolves.toBe(path.join(realpathSync(ws), "apps/order_service"));
  });

  it("refuses a path that leaves the workspace through a symlink", async () => {
    const ws = makeWorkspace();
    const outside = mkdtempSync(path.join(tmpdir(), "app-render-outside-"));
    workspaces.push(outside);
    symlinkSync(outside, path.join(ws, "link"));

    await expect(
      resolveContainedOutput(ws, "link/order_service"),
    ).rejects.toThrow(
      /escapes the target repository[\s\S]*really resolves to[\s\S]*would delete files outside the repository/,
    );
  });

  it("refuses the render, without running the engine", async () => {
    const ws = makeWorkspace();
    const outside = mkdtempSync(path.join(tmpdir(), "app-render-outside-"));
    workspaces.push(outside);
    writeFileSync(path.join(outside, "precious.txt"), "not yours\n");
    symlinkSync(outside, path.join(ws, "link"));
    const exec = fakeEngine();

    await expect(
      renderApplication({
        workspacePath: ws,
        name: "order_service",
        language: "go",
        targetPath: "link/order_service",
        logger: logger().service,
        exec,
      }),
    ).rejects.toThrow(/escapes the target repository/);

    expect(exec).not.toHaveBeenCalled();
    expect(readFileSync(path.join(outside, "precious.txt"), "utf8")).toBe(
      "not yours\n",
    );
  });

  it("refuses a symlink pointing deeper into a directory outside the workspace", async () => {
    // Distinct from the case above only in that the link names a SUBdirectory
    // of the outside tree; that destination is created here, so this is not a
    // dangling-link test (see the next one, which is).
    const ws = makeWorkspace();
    const outside = mkdtempSync(path.join(tmpdir(), "app-render-outside-"));
    workspaces.push(outside);
    mkdirSync(path.join(outside, "nested"));
    symlinkSync(path.join(outside, "nested"), path.join(ws, "link"));

    await expect(
      resolveContainedOutput(ws, "link/order_service"),
    ).rejects.toThrow(/escapes the target repository/);
  });

  it("refuses a DANGLING symlink instead of letting the engine hit ENOENT", async () => {
    // `stat` follows symlinks, so a broken link reads as "not there yet": the
    // walk-up would step straight over it and re-join a path that lands back
    // under the workspace and passes containment. Not an escape — the engine's
    // mkdir refuses — but the operator would get a raw ENOENT out of a
    // subprocess instead of a sentence. The walk uses `lstat` for this reason.
    const ws = makeWorkspace();
    symlinkSync("/nonexistent-destination-xyz", path.join(ws, "link"));

    await expect(
      resolveContainedOutput(ws, "link/order_service"),
    ).rejects.toThrow(
      /runs through a broken symlink[\s\S]*does not resolve to anything/,
    );
  });

  it("refuses the render on a dangling symlink, without running the engine", async () => {
    const ws = makeWorkspace();
    symlinkSync("/nonexistent-destination-xyz", path.join(ws, "link"));
    const exec = fakeEngine();

    await expect(
      renderApplication({
        workspacePath: ws,
        name: "order_service",
        language: "go",
        targetPath: "link/order_service",
        logger: logger().service,
        exec,
      }),
    ).rejects.toThrow(/runs through a broken symlink/);
    expect(exec).not.toHaveBeenCalled();
  });
});

describe("the stamping-target predicate", () => {
  it("names the onboarding pattern when tools/initializer is absent", async () => {
    const ws = makeWorkspace({ config: false });
    await expect(assertStampingTarget(ws)).rejects.toThrow(
      /tools\/initializer\/config\.json is missing[\s\S]*vitruvian-core#1815/,
    );
  });

  it("names the onboarding pattern when MODULE.aspect is absent", async () => {
    const ws = makeWorkspace({ moduleAspect: false });
    await expect(assertStampingTarget(ws)).rejects.toThrow(
      /has no MODULE\.aspect[\s\S]*vitruvian-core#1815/,
    );
  });

  it("rejects a MODULE.aspect that never registers render_app", async () => {
    const ws = makeWorkspace({
      moduleAspect:
        'use_task("tools/initializer/tasks.axl", "check_metadata")\n',
    });
    await expect(assertStampingTarget(ws)).rejects.toThrow(
      /does not register the initializer's render_app task/,
    );
  });

  it("does not count a commented-out registration", () => {
    expect(
      registersRenderApp(
        '  # use_task("tools/initializer/tasks.axl", "render_app")',
      ),
    ).toBe(false);
    expect(registersRenderApp(MODULE_ASPECT)).toBe(true);
  });

  it("accepts the real vitruvian-core MODULE.aspect", async () => {
    // Guards against the predicate drifting away from the file it describes:
    // this is the repo PR #1815 onboarded, read from disk.
    const repoRoot = path.resolve(__dirname, "../../../../..");
    expect(
      registersRenderApp(
        readFileSync(path.join(repoRoot, "MODULE.aspect"), "utf8"),
      ),
    ).toBe(true);
    await expect(assertStampingTarget(repoRoot)).resolves.toBeUndefined();
  });
});

describe("the root catalog Location", () => {
  it("inserts the target exactly once, in sorted position", () => {
    const first = appendCatalogTarget(CATALOG, "apps/order_service");
    expect(first.changed).toBe(true);
    expect(first.content).toContain(
      "\n    - ./apps/order_service/catalog-info.yaml\n",
    );
    // Sorted among the uncommented run; the commented platform group keeps its
    // comment and stays last.
    expect(first.content).toContain(
      "    # Platform infrastructure we operate (not applications we build)\n" +
        "    - ./gitops/catalog-info.yaml\n",
    );
    const targets = first.content
      .split("\n")
      .filter((l) => l.startsWith("    - ./"));
    expect(targets).toEqual([
      "    - ./apps/order_service/catalog-info.yaml",
      "    - ./backstage/catalog-info.yaml",
      "    - ./devx/catalog-info.yaml",
      "    - ./tabula/catalog-info.yaml",
      "    - ./gitops/catalog-info.yaml",
    ]);
  });

  it("is idempotent — a second append is a no-op", () => {
    const first = appendCatalogTarget(CATALOG, "apps/order_service");
    const second = appendCatalogTarget(first.content, "apps/order_service");
    expect(second.changed).toBe(false);
    expect(second.content).toBe(first.content);
  });

  it.each([
    ["hand-written without ./", "    - apps/order_service/catalog-info.yaml"],
    ["two-space indent", "  - ./apps/order_service/catalog-info.yaml"],
    ["two-space and no ./", "  - apps/order_service/catalog-info.yaml"],
    [
      "extra spacing after the dash",
      "    -   ./apps/order_service/catalog-info.yaml",
    ],
  ])(
    "treats a %s entry as already present rather than duplicating it",
    (_label, variant) => {
      const existing = CATALOG.replace(
        "    - ./backstage/catalog-info.yaml",
        `${variant}\n    - ./backstage/catalog-info.yaml`,
      );
      const result = appendCatalogTarget(existing, "apps/order_service");
      expect(result.changed).toBe(false);
      expect(result.content).toBe(existing);
      expect(
        result.content.split("\n").filter((l) => l.includes("order_service"))
          .length,
      ).toBe(1);
    },
  );

  it("normalises a list line to its target", () => {
    expect(catalogTargetOf("    - ./apps/x/catalog-info.yaml")).toBe(
      "apps/x/catalog-info.yaml",
    );
    expect(catalogTargetOf("  -   apps/x/catalog-info.yaml  ")).toBe(
      "apps/x/catalog-info.yaml",
    );
    expect(catalogTargetOf("  targets:")).toBeUndefined();
    expect(catalogTargetOf("    # a comment")).toBeUndefined();
  });

  it("matches the list's own indentation when it is not four spaces", () => {
    const twoSpace = CATALOG.replace(/^ {4}- /gm, "  - ");
    const { content, changed } = appendCatalogTarget(
      twoSpace,
      "apps/order_service",
    );
    expect(changed).toBe(true);
    // A four-space item inside a two-space list would parse as a NESTED
    // sequence — valid YAML meaning something else entirely.
    expect(content).toContain("\n  - ./apps/order_service/catalog-info.yaml\n");
    expect(content).not.toContain("    - ./apps/order_service");
  });

  it("does not touch the external-repos Location", () => {
    const { content } = appendCatalogTarget(CATALOG, "apps/order_service");
    expect(content).toContain(
      "    - https://github.com/VitruvianSoftware/backstage-go/blob/main/catalog-info.yaml",
    );
    expect(
      content
        .split("vitruvian-external-repos")[1]
        .split("\n")
        .filter((l) => l.includes("order_service")),
    ).toEqual([]);
  });

  it("refuses a catalog with no per-app Location rather than guessing", () => {
    expect(() =>
      appendCatalogTarget("kind: System\nmetadata:\n  name: x\n", "apps/api"),
    ).toThrow(/no Location named vitruvian-core-apps/);
  });
});

describe("renderApplication", () => {
  it("runs the engine from the workspace root and registers the app", async () => {
    const ws = makeWorkspace();
    const exec = fakeEngine();
    const log = logger();

    const result = await renderApplication({
      workspacePath: ws,
      name: "order_service",
      language: "go",
      logger: log.service,
      exec,
    });

    expect(exec).toHaveBeenCalledTimes(1);
    const call = exec.mock.calls[0][0];
    // The RESOLVED binary, so what runs is what the log line named.
    expect(call.command).toBe(findAspectBinary());
    expect(path.basename(call.command)).toBe("aspect");
    expect(log.lines.join("\n")).toContain(
      `engine: ${call.command} render-app`,
    );
    expect(call.args).toEqual([
      "render-app",
      "--language",
      "go",
      "--name",
      "order_service",
      "--out",
      // The REAL path — resolveContainedOutput hands the engine the destination
      // it actually verified, not the one the string implied.
      path.join(realpathSync(ws), "apps/order_service"),
    ]);
    // cwd is load-bearing: the engine probes current_dir() for its own mount
    // point and would render the wrong tree (or none) from anywhere else.
    expect(call.options?.cwd).toBe(ws);
    // Streamed, so the UI does not think the step has stalled.
    expect(call.logger).toBe(log.service);

    expect(result.appPath).toBe("apps/order_service");
    expect(result.catalogInfoPath).toBe("apps/order_service/catalog-info.yaml");
    expect(result.renderedFiles).toEqual(
      STARTER_FILES.map((f) => path.join("apps/order_service", f)).sort(),
    );
    expect(result.catalogUpdated).toBe(true);

    expect(readFileSync(path.join(ws, "catalog-info.yaml"), "utf8")).toContain(
      "\n    - ./apps/order_service/catalog-info.yaml\n",
    );
    // Disclose-and-include: the operator must be told a file they did not name
    // was edited.
    expect(log.lines.join("\n")).toContain(
      'edited catalog-info.yaml — added "./apps/order_service/catalog-info.yaml"',
    );
    expect(log.lines.join("\n")).toContain("rendered 5 file(s)");
  });

  it("appends the Location target only once across repeated renders", async () => {
    const ws = makeWorkspace();
    const log = logger();

    await renderApplication({
      workspacePath: ws,
      name: "order_service",
      language: "go",
      logger: log.service,
      exec: fakeEngine(),
    });
    const after = readFileSync(path.join(ws, "catalog-info.yaml"), "utf8");

    // Second run against a workspace that already has the app: the refusal
    // fires, so re-running cannot duplicate the line either.
    await expect(
      renderApplication({
        workspacePath: ws,
        name: "order_service",
        language: "go",
        logger: log.service,
        exec: fakeEngine(),
      }),
    ).rejects.toThrow(/already exists in the target repository/);

    expect(readFileSync(path.join(ws, "catalog-info.yaml"), "utf8")).toBe(
      after,
    );
    expect(
      after.split("\n").filter((l) => l.includes("order_service")).length,
    ).toBe(1);
  });

  it("refuses to stamp over an existing directory", async () => {
    const ws = makeWorkspace();
    mkdirSync(path.join(ws, "apps/order_service"), { recursive: true });
    writeFileSync(
      path.join(ws, "apps/order_service/main.go"),
      "package main\n",
    );
    const exec = fakeEngine();

    await expect(
      renderApplication({
        workspacePath: ws,
        name: "order_service",
        language: "go",
        logger: logger().service,
        exec,
      }),
    ).rejects.toThrow(
      "apps/order_service already exists in the target repository; stamping " +
        "over an existing application is not supported.",
    );

    // The engine clears --out, so the whole point is that it never ran.
    expect(exec).not.toHaveBeenCalled();
    expect(
      readFileSync(path.join(ws, "apps/order_service/main.go"), "utf8"),
    ).toBe("package main\n");
  });

  it("fails on a bad name before touching the workspace", async () => {
    const exec = fakeEngine();
    await expect(
      renderApplication({
        workspacePath: "/nonexistent",
        name: "OrderService",
        language: "go",
        logger: logger().service,
        exec,
      }),
    ).rejects.toThrow(/is not snake_case/);
    expect(exec).not.toHaveBeenCalled();
  });

  it("fails on a path/name mismatch before touching the workspace", async () => {
    const exec = fakeEngine();
    await expect(
      renderApplication({
        workspacePath: "/nonexistent",
        name: "order_service",
        language: "go",
        targetPath: "apps/orders",
        logger: logger().service,
        exec,
      }),
    ).rejects.toThrow(/must end in a directory named after the application/);
    expect(exec).not.toHaveBeenCalled();
  });

  it("names the image requirement when the aspect binary is missing", async () => {
    const ws = makeWorkspace();
    const originalPath = process.env.PATH;
    process.env.PATH = path.join(ws, "no-binaries-here");
    try {
      expect(findAspectBinary()).toBeUndefined();
      await expect(
        renderApplication({
          workspacePath: ws,
          name: "order_service",
          language: "go",
          logger: logger().service,
          exec: fakeEngine(),
        }),
      ).rejects.toThrow(
        /`aspect` CLI is not on PATH[\s\S]*aspect 2026\.26\.25, see backstage\/Dockerfile/,
      );
    } finally {
      process.env.PATH = originalPath;
    }
  });

  it("still renders and registers on a dry run", async () => {
    const ws = makeWorkspace();
    const log = logger();
    const result = await renderApplication({
      workspacePath: ws,
      name: "order_service",
      language: "go",
      logger: log.service,
      dryRun: true,
      exec: fakeEngine(),
    });
    expect(result.renderedFiles).toHaveLength(5);
    expect(result.catalogUpdated).toBe(true);
    expect(log.lines.join("\n")).toContain("[dry run]");
  });

  it("rejects a malformed root catalog BEFORE running the engine", async () => {
    const ws = makeWorkspace({
      catalog: "kind: System\nmetadata:\n  name: vitruvian-core\n",
    });
    const exec = fakeEngine();

    await expect(
      renderApplication({
        workspacePath: ws,
        name: "order_service",
        language: "go",
        logger: logger().service,
        exec,
      }),
    ).rejects.toThrow(/no Location named vitruvian-core-apps/);

    // Fail-early is the point: a shape problem must not cost a whole render.
    expect(exec).not.toHaveBeenCalled();
  });

  it("is actionable when the engine exits 0 but writes nothing", async () => {
    const ws = makeWorkspace();
    // A zero exit with no output — the shape of an engine/image mismatch.
    const exec = jest.fn(async () => {}) as unknown as jest.MockedFunction<
      typeof renderStub
    >;

    await expect(
      renderApplication({
        workspacePath: ws,
        name: "order_service",
        language: "go",
        logger: logger().service,
        exec: exec as unknown as ShellRunner,
      }),
    ).rejects.toThrow(
      /reported success but produced no files at apps\/order_service[\s\S]*may not be compatible/,
    );
  });

  it("does not mislabel a real filesystem fault as an engine mismatch", async () => {
    // Only ENOENT means "the engine produced nothing". An EACCES reported as an
    // engine/image mismatch would send the operator to the wrong place entirely.
    const ws = makeWorkspace();
    const exec = jest.fn(async ({ args }: { args: string[] }) => {
      const out = args[args.indexOf("--out") + 1];
      mkdirSync(out, { recursive: true });
      chmodSync(out, 0o000);
    }) as unknown as ShellRunner;

    const attempt = renderApplication({
      workspacePath: ws,
      name: "order_service",
      language: "go",
      logger: logger().service,
      exec,
    });
    await expect(attempt).rejects.toThrow();
    await expect(attempt).rejects.not.toThrow(/reported success but produced/);
    await attempt.catch((error: NodeJS.ErrnoException) => {
      expect(error.code).toBe("EACCES");
    });
    chmodSync(path.join(ws, "apps/order_service"), 0o755);
  });

  it("is actionable when the starter renders no catalog-info.yaml", async () => {
    const ws = makeWorkspace();
    const exec = jest.fn(async ({ args }: { args: string[] }) => {
      const out = args[args.indexOf("--out") + 1];
      mkdirSync(out, { recursive: true });
      writeFileSync(path.join(out, "main.go"), "package main\n");
    }) as unknown as ShellRunner;

    await expect(
      renderApplication({
        workspacePath: ws,
        name: "order_service",
        language: "go",
        logger: logger().service,
        exec,
      }),
    ).rejects.toThrow(
      // catalogInfoPath is a promise made to the template's catalog:register
      // step; without the file that step fails far from the cause.
      /rendered 1 file\(s\) into apps\/order_service but no catalog-info\.yaml/,
    );
  });

  it("warns rather than fails when the repo has no root catalog", async () => {
    const ws = makeWorkspace({ catalog: false });
    const log = logger();
    const result = await renderApplication({
      workspacePath: ws,
      name: "order_service",
      language: "go",
      logger: log.service,
      exec: fakeEngine(),
    });
    expect(result.catalogUpdated).toBe(false);
    expect(log.lines.join("\n")).toContain("warn: ");
    expect(log.lines.join("\n")).toContain("has no catalog-info.yaml");
  });
});

describe("the action definition", () => {
  const action = createAppRenderAction() as any;

  it("is registered under the documented id and supports dry runs", () => {
    expect(action.id).toBe(APP_RENDER_ACTION_ID);
    expect(APP_RENDER_ACTION_ID).toBe("vitruvian:app:render");
    expect(action.supportsDryRun).toBe(true);
  });

  it("declares the documented inputs and outputs", () => {
    expect(Object.keys(action.schema.input).sort()).toEqual([
      "language",
      "name",
      "targetPath",
    ]);
    expect(Object.keys(action.schema.output).sort()).toEqual([
      "appPath",
      "catalogInfoPath",
    ]);
  });

  it("passes ctx.isDryRun through and emits both outputs", async () => {
    const ws = makeWorkspace();
    const outputs: Record<string, unknown> = {};
    const log = logger();
    await action.handler({
      workspacePath: ws,
      input: { name: "order_service", language: "go" },
      logger: log.service,
      isDryRun: true,
      output: (key: string, value: unknown) => {
        outputs[key] = value;
      },
    });
    expect(outputs).toEqual({
      appPath: "apps/order_service",
      catalogInfoPath: "apps/order_service/catalog-info.yaml",
    });
    expect(log.lines.join("\n")).toContain("[dry run]");
  });
});
