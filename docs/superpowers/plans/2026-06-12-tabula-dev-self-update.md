# Tabula Dev Self-Update (M1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give load-unpacked dev installs a self-update loop: CI publishes a rolling `dev-latest` bundle per `main` commit, `tabcli ext update` swaps it into a fixed directory, and the extension shows a reload banner when the deployed commit differs from its own.

**Architecture:** Identity lives in `build_info.json` (placeholder `{"commit":"dev"}` in the bundle; CI overwrites it inside the built zip post-Bazel, keeping the build hermetic). The extension reads its own commit at startup and polls the deployed dev API's `GET /` provenance endpoint (#32); a mismatch shows a dashboard banner with a `chrome.runtime.reload()` button. `tabcli ext update` downloads via the `gh` CLI and atomically swaps the load-unpacked directory.

**Tech Stack:** Bazel (aspect rules_js/ts/jest), webpack 5 + CopyPlugin, React 18, commander, jest + @swc/jest, GitHub Actions + `gh` CLI.

**Spec:** `docs/superpowers/specs/2026-06-12-tabula-dev-self-update-design.md`

**Branch:** `feat/tabula-dev-self-update` (already created; spec committed on it).

**Conventions for every task:**

- Every new file starts with the repo's MIT header (copy the exact 21-line comment block from the top of `tabula/cli/src/index.ts` for TS files, `tabula/extension/webpack.config.js` style for JS, or `#`-prefixed like `.github/workflows/tabula-release.yml` for YAML).
- Run `npx --no-install prettier --write <changed ts/tsx/js files>` before each commit.
- All bazel/test commands run from the repo root.

---

## File map

| File                                                    | Action             | Responsibility                                              |
| ------------------------------------------------------- | ------------------ | ----------------------------------------------------------- |
| `tabula/cli/package.json`                               | modify             | add jest devDeps                                            |
| `pnpm-lock.yaml`                                        | modify (generated) | lockfile for the above                                      |
| `tabula/cli/jest.config.js`                             | create             | CLI jest config (node env, swc transform)                   |
| `tabula/cli/tsconfig.test.json`                         | create             | type-gate config incl. jest types                           |
| `tabula/cli/BUILD`                                      | modify             | exclude tests from `:lib`; add `:tests_lib` + `:unit_tests` |
| `tabula/cli/src/utils/extension.ts`                     | create             | paths, bundle validation, atomic install                    |
| `tabula/cli/src/utils/extension.test.ts`                | create             | tests for the above (real temp dirs)                        |
| `tabula/cli/src/commands/ext.ts`                        | create             | `tabcli ext update` / `tabcli ext path`                     |
| `tabula/cli/src/commands/ext.test.ts`                   | create             | command wiring + gh-missing error                           |
| `tabula/cli/src/index.ts`                               | modify             | register `extCommand`                                       |
| `tabula/extension/src/build_info.json`                  | create             | placeholder identity `{"commit":"dev"}`                     |
| `tabula/extension/webpack.config.js`                    | modify             | copy `build_info.json` into the bundle                      |
| `tabula/extension/src/services/updateCheck.ts`          | create             | eligibility + deployed-commit check                         |
| `tabula/extension/src/services/updateCheck.test.ts`     | create             | service tests                                               |
| `tabula/extension/src/components/UpdateBanner.tsx`      | create             | banner UI (reload / dismiss)                                |
| `tabula/extension/src/components/UpdateBanner.test.tsx` | create             | banner tests                                                |
| `tabula/extension/src/dashboard/Dashboard.tsx`          | modify             | mount `<UpdateBanner />`                                    |
| `tabula/extension/src/styles/components.css`            | modify             | `.update-banner` styles                                     |
| `.github/workflows/tabula-dev-latest.yaml`              | create             | rolling dev-latest publish                                  |
| `tabula/extension/docs/DEV_UPDATES.md`                  | create             | tester how-to                                               |
| `tabula/cli/README.md`                                  | modify             | document `tabcli ext`                                       |

---

### Task 1: CLI jest harness

The CLI has no tests at all. Mirror the extension's jest setup (swc transform, Bazel `jest_test`), but with a node environment.

**Files:**

- Modify: `tabula/cli/package.json`
- Create: `tabula/cli/jest.config.js`
- Create: `tabula/cli/tsconfig.test.json`
- Modify: `tabula/cli/BUILD`
- Create: `tabula/cli/src/utils/extension.test.ts` (placeholder smoke test, replaced in Task 2)

- [ ] **Step 1: Add jest devDependencies**

In `tabula/cli/package.json`, replace the `devDependencies` block with:

```json
  "devDependencies": {
    "@swc/core": "^1.13.0",
    "@swc/jest": "^0.2.39",
    "@types/inquirer": "^8.2.10",
    "@types/jest": "^29.5.12",
    "@types/node": "^20.11.17",
    "jest": "^29.7.0",
    "jest-cli": "^29.7.0"
  }
```

- [ ] **Step 2: Update the pnpm lockfile**

Run from repo root: `pnpm install --lockfile-only`
Expected: `pnpm-lock.yaml` modified; `git status --short` shows only `pnpm-lock.yaml` and `tabula/cli/package.json`. (If `pnpm` is missing: `corepack enable` first.)

- [ ] **Step 3: Create `tabula/cli/jest.config.js`**

(MIT header, then:)

```js
/**
 * Tests run on the original TypeScript through @swc/jest (same rationale as
 * tabula/extension/jest.config.js). Type-checking is enforced separately by
 * the :tests_lib ts_project.
 */
module.exports = {
  testEnvironment: "node",
  testMatch: ["**/?(*.)+(test).ts"],
  testPathIgnorePatterns: ["/node_modules/", "/dist/"],
  transform: {
    "^.+\\.(t|j)s$": [
      "@swc/jest",
      {
        jsc: {
          parser: { syntax: "typescript" },
          target: "es2022",
        },
        module: { type: "commonjs" },
      },
    ],
  },
};
```

- [ ] **Step 4: Create `tabula/cli/tsconfig.test.json`**

```json
{
  "extends": "./tsconfig.json",
  "compilerOptions": {
    "types": ["node", "jest"],
    "declaration": false,
    "declarationMap": false,
    "noUnusedLocals": false,
    "noUnusedParameters": false
  },
  "include": ["src/**/*"]
}
```

- [ ] **Step 5: Create a temporary smoke test**

`tabula/cli/src/utils/extension.test.ts` (MIT header, then:)

```ts
describe("cli jest harness", () => {
  it("runs", () => {
    expect(1 + 1).toBe(2);
  });
});
```

- [ ] **Step 6: Wire Bazel**

In `tabula/cli/BUILD`:

a) Change the load line `load("@aspect_rules_ts//ts:defs.bzl", "ts_project")` — no change needed; add below it:

```python
load("@aspect_rules_jest//jest:defs.bzl", "jest_test")
```

b) In the `ts_project(name = "lib", ...)` target, change `srcs = glob(["src/**/*.ts"])` to:

```python
    srcs = glob(
        ["src/**/*.ts"],
        exclude = ["src/**/*.test.ts"],
    ),
```

c) Append at the end of the file (copy the `deps` list from `:lib` and add `@types/jest`):

```python
# Type gate for tests: jest runs swc-transpiled TS without type-checking, so
# tests are compiled (not emitted) here, mirroring //tabula/extension:tests_lib.
ts_project(
    name = "tests_lib",
    testonly = True,
    srcs = glob(["src/**/*.ts"]),
    declaration = False,
    extends = "tsconfig.json",
    source_map = True,
    transpiler = "tsc",
    tsconfig = "tsconfig.test.json",
    deps = [
        # same list as :lib deps, plus:
        ":node_modules/@types/jest",
    ],
)

jest_test(
    name = "unit_tests",
    size = "medium",
    config = "jest.config.js",
    data = glob(["src/**/*.ts"]) + [
        ":node_modules/@swc/core",
        ":node_modules/@swc/jest",
        ":node_modules/chalk",
        ":node_modules/commander",
    ],
    node_modules = ":node_modules",
    node_options = ["--no-experimental-require-module"],
)
```

(When copying `:lib`'s deps into `tests_lib`, read the current BUILD — keep them identical, just add `@types/jest`.)

- [ ] **Step 7: Run the smoke test**

Run: `bazel test //tabula/cli:unit_tests --test_output=all`
Expected: PASS, `Tests: 1 passed`.
Also run: `bazel build //tabula/cli:lib //tabula/cli:tests_lib`
Expected: both build (the type gate compiles).

- [ ] **Step 8: Commit**

```bash
git add tabula/cli/package.json pnpm-lock.yaml tabula/cli/jest.config.js tabula/cli/tsconfig.test.json tabula/cli/BUILD tabula/cli/src/utils/extension.test.ts
git commit -m "test(tabula): add a jest harness to tabcli (none existed)"
```

---

### Task 2: Atomic install utils (`tabcli`)

Pure filesystem logic, tested against real temp dirs — no mocks.

**Files:**

- Create: `tabula/cli/src/utils/extension.ts`
- Modify: `tabula/cli/src/utils/extension.test.ts` (replace the smoke test)

- [ ] **Step 1: Write the failing tests**

Replace the body of `tabula/cli/src/utils/extension.test.ts` (keep the MIT header) with:

```ts
import fs from "fs";
import os from "os";
import path from "path";
import {
  atomicInstall,
  defaultExtensionDir,
  readBundleInfo,
  validateBundleDir,
} from "./extension";

const mkTmp = (): string =>
  fs.mkdtempSync(path.join(os.tmpdir(), "tabula-ext-test-"));

const writeBundle = (dir: string, commit = "abc1234"): void => {
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(
    path.join(dir, "manifest.json"),
    JSON.stringify({ name: "Tabula" }),
  );
  fs.writeFileSync(
    path.join(dir, "build_info.json"),
    JSON.stringify({ commit }),
  );
};

describe("defaultExtensionDir", () => {
  it("is ~/.tabula/extension", () => {
    expect(defaultExtensionDir()).toBe(
      path.join(os.homedir(), ".tabula", "extension"),
    );
  });
});

describe("readBundleInfo", () => {
  it("reads commit from build_info.json", () => {
    const dir = mkTmp();
    writeBundle(dir, "deadbee");
    expect(readBundleInfo(dir)).toEqual({ commit: "deadbee" });
  });

  it("returns null when the file is missing or invalid", () => {
    const dir = mkTmp();
    expect(readBundleInfo(dir)).toBeNull();
    fs.writeFileSync(path.join(dir, "build_info.json"), "not json");
    expect(readBundleInfo(dir)).toBeNull();
  });
});

describe("validateBundleDir", () => {
  it("throws when manifest.json is missing", () => {
    const dir = mkTmp();
    expect(() => validateBundleDir(dir)).toThrow(/manifest\.json/);
  });
});

describe("atomicInstall", () => {
  it("installs a fresh bundle when no previous install exists", () => {
    const root = mkTmp();
    const staging = path.join(root, "staging");
    const target = path.join(root, "extension");
    writeBundle(staging);

    atomicInstall(staging, target);

    expect(fs.existsSync(path.join(target, "manifest.json"))).toBe(true);
    expect(fs.existsSync(staging)).toBe(false); // staging was moved, not copied
  });

  it("replaces a previous install and leaves no leftovers", () => {
    const root = mkTmp();
    const staging = path.join(root, "staging");
    const target = path.join(root, "extension");
    writeBundle(target, "oldcommit");
    writeBundle(staging, "newcommit");

    atomicInstall(staging, target);

    expect(readBundleInfo(target)).toEqual({ commit: "newcommit" });
    // no .old-* / staging dirs left behind
    expect(fs.readdirSync(root)).toEqual(["extension"]);
  });

  it("leaves the existing install untouched when the staging bundle is invalid", () => {
    const root = mkTmp();
    const staging = path.join(root, "staging");
    const target = path.join(root, "extension");
    writeBundle(target, "oldcommit");
    fs.mkdirSync(staging, { recursive: true }); // no manifest.json -> invalid

    expect(() => atomicInstall(staging, target)).toThrow(/manifest\.json/);
    expect(readBundleInfo(target)).toEqual({ commit: "oldcommit" });
  });

  it("rolls the previous install back when the final swap fails", () => {
    const root = mkTmp();
    const staging = path.join(root, "staging");
    const target = path.join(root, "extension");
    writeBundle(target, "oldcommit");
    writeBundle(staging, "newcommit");

    // Force the staging -> target rename to fail after the old dir was moved:
    // 1st call (target -> old) real, 2nd (staging -> target) throws, then real
    // again so the rollback rename succeeds.
    const realRename = jest.requireActual("fs")
      .renameSync as typeof fs.renameSync;
    const renameSpy = jest
      .spyOn(fs, "renameSync")
      .mockImplementationOnce((a, b) => realRename(a, b))
      .mockImplementationOnce(() => {
        throw new Error("simulated rename failure");
      })
      .mockImplementation((a, b) => realRename(a, b));

    expect(() => atomicInstall(staging, target)).toThrow(
      /simulated rename failure/,
    );
    renameSpy.mockRestore();

    expect(readBundleInfo(target)).toEqual({ commit: "oldcommit" });
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bazel test //tabula/cli:unit_tests --test_output=all`
Expected: FAIL — `Cannot find module './extension'`.

- [ ] **Step 3: Implement `tabula/cli/src/utils/extension.ts`**

(MIT header, then:)

```ts
import fs from "fs";
import os from "os";
import path from "path";

/** Fixed tag of the rolling dev prerelease published per main commit. */
export const DEV_LATEST_TAG = "tabula-extension-dev-latest";

/** Default GitHub repository hosting the dev-latest release. */
export const DEFAULT_REPO = "VitruvianSoftware/vitruvian-core";

/** Default load-unpacked install directory. */
export function defaultExtensionDir(): string {
  return path.join(os.homedir(), ".tabula", "extension");
}

export interface BundleInfo {
  commit?: string;
  builtAt?: string;
  version?: string;
}

/** Read the bundle's build identity; null when absent/unreadable. */
export function readBundleInfo(dir: string): BundleInfo | null {
  try {
    return JSON.parse(
      fs.readFileSync(path.join(dir, "build_info.json"), "utf-8"),
    ) as BundleInfo;
  } catch {
    return null;
  }
}

/** A bundle dir must at least carry the extension manifest. */
export function validateBundleDir(dir: string): void {
  if (!fs.existsSync(path.join(dir, "manifest.json"))) {
    throw new Error(
      `Downloaded bundle is missing manifest.json (looked in ${dir})`,
    );
  }
}

/**
 * Atomically replace targetDir with stagingDir.
 *
 * Both directories must live on the same filesystem (rename, not copy). On
 * any failure the previous install is left in place: validation happens
 * before anything moves, and a failed final swap renames the old dir back.
 */
export function atomicInstall(stagingDir: string, targetDir: string): void {
  validateBundleDir(stagingDir);
  fs.mkdirSync(path.dirname(targetDir), { recursive: true });

  const oldDir = `${targetDir}.old-${process.pid}`;
  const hadPrevious = fs.existsSync(targetDir);
  if (hadPrevious) fs.renameSync(targetDir, oldDir);
  try {
    fs.renameSync(stagingDir, targetDir);
  } catch (err) {
    if (hadPrevious) fs.renameSync(oldDir, targetDir); // roll back
    throw err;
  }
  if (hadPrevious) fs.rmSync(oldDir, { recursive: true, force: true });
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bazel test //tabula/cli:unit_tests --test_output=all`
Expected: PASS — all `extension.test.ts` tests green.

- [ ] **Step 5: Commit**

```bash
npx --no-install prettier --write tabula/cli/src/utils/extension.ts tabula/cli/src/utils/extension.test.ts
git add tabula/cli/src/utils/extension.ts tabula/cli/src/utils/extension.test.ts
git commit -m "feat(tabula): tabcli atomic extension-install utils"
```

---

### Task 3: `tabcli ext` command

**Files:**

- Create: `tabula/cli/src/commands/ext.ts`
- Create: `tabula/cli/src/commands/ext.test.ts`
- Modify: `tabula/cli/src/index.ts`

- [ ] **Step 1: Write the failing tests**

`tabula/cli/src/commands/ext.test.ts` (MIT header, then:)

```ts
import os from "os";
import path from "path";

jest.mock("child_process", () => ({
  spawnSync: jest.fn(),
}));
// eslint-disable-next-line import/first
import { spawnSync } from "child_process";
// eslint-disable-next-line import/first
import { extCommand, runTool } from "./ext";

describe("extCommand wiring", () => {
  it("exposes update and path subcommands", () => {
    const names = extCommand.commands.map((c) => c.name());
    expect(names).toContain("update");
    expect(names).toContain("path");
  });

  it("path defaults to ~/.tabula/extension", () => {
    const pathCmd = extCommand.commands.find((c) => c.name() === "path")!;
    const dirOpt = pathCmd.options.find((o) => o.long === "--dir")!;
    expect(dirOpt.defaultValue).toBe(
      path.join(os.homedir(), ".tabula", "extension"),
    );
  });
});

describe("runTool", () => {
  it("explains when the tool is not installed", () => {
    (spawnSync as jest.Mock).mockReturnValue({
      error: Object.assign(new Error("spawn gh ENOENT"), { code: "ENOENT" }),
      status: null,
    });
    expect(() => runTool("gh", ["release", "download"])).toThrow(
      /'gh' not found on PATH/,
    );
  });

  it("surfaces non-zero exits with the command line", () => {
    (spawnSync as jest.Mock).mockReturnValue({ error: undefined, status: 1 });
    expect(() => runTool("unzip", ["-o"])).toThrow(
      /unzip -o failed \(exit 1\)/,
    );
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bazel test //tabula/cli:unit_tests --test_output=all`
Expected: FAIL — `Cannot find module './ext'`.

- [ ] **Step 3: Implement `tabula/cli/src/commands/ext.ts`**

(MIT header, then:)

```ts
import { Command } from "commander";
import chalk from "chalk";
import { spawnSync } from "child_process";
import fs from "fs";
import os from "os";
import path from "path";
import {
  DEFAULT_REPO,
  DEV_LATEST_TAG,
  atomicInstall,
  defaultExtensionDir,
  readBundleInfo,
} from "../utils/extension";

/** Run an external tool, inheriting stdout/stderr; throw helpful errors. */
export function runTool(cmd: string, args: string[]): void {
  const res = spawnSync(cmd, args, { stdio: ["ignore", "inherit", "inherit"] });
  if (res.error && (res.error as NodeJS.ErrnoException).code === "ENOENT") {
    throw new Error(
      `'${cmd}' not found on PATH — install it first (${
        cmd === "gh" ? "https://cli.github.com + 'gh auth login'" : cmd
      }).`,
    );
  }
  if (res.error) throw res.error;
  if (res.status !== 0) {
    throw new Error(`${cmd} ${args.join(" ")} failed (exit ${res.status})`);
  }
}

export const extCommand = new Command("ext").description(
  "Manage the local load-unpacked dev extension install",
);

extCommand
  .command("path")
  .description("Print the load-unpacked extension directory")
  .option("--dir <path>", "extension directory", defaultExtensionDir())
  .action((opts: { dir: string }) => {
    console.log(path.resolve(opts.dir));
  });

extCommand
  .command("update")
  .description(
    "Download the latest dev build (rolling dev-latest release) into the load-unpacked directory",
  )
  .option("--dir <path>", "extension directory", defaultExtensionDir())
  .option("--repo <owner/repo>", "GitHub repository", DEFAULT_REPO)
  .action((opts: { dir: string; repo: string }) => {
    const target = path.resolve(opts.dir);
    const downloadDir = fs.mkdtempSync(path.join(os.tmpdir(), "tabula-ext-"));
    // Staging must share a filesystem with the target for an atomic rename.
    const staging = `${target}.staging-${process.pid}`;
    try {
      console.log(`Fetching ${DEV_LATEST_TAG} from ${opts.repo}…`);
      runTool("gh", [
        "release",
        "download",
        DEV_LATEST_TAG,
        "--repo",
        opts.repo,
        "--pattern",
        "tabula-extension-chrome.zip",
        "--dir",
        downloadDir,
        "--clobber",
      ]);
      fs.mkdirSync(staging, { recursive: true });
      runTool("unzip", [
        "-o",
        "-q",
        path.join(downloadDir, "tabula-extension-chrome.zip"),
        "-d",
        staging,
      ]);
      atomicInstall(staging, target);

      const commit = readBundleInfo(target)?.commit;
      console.log(
        chalk.green(
          `✓ Installed dev build ${commit ? commit.slice(0, 7) : "(unknown commit)"} → ${target}`,
        ),
      );
      console.log(
        "  Reload the extension to load it (banner button, or chrome://extensions → ↻).",
      );
      console.log(
        `  First time? chrome://extensions → Developer mode → "Load unpacked" → ${target}`,
      );
    } finally {
      fs.rmSync(downloadDir, { recursive: true, force: true });
      fs.rmSync(staging, { recursive: true, force: true });
    }
  });
```

- [ ] **Step 4: Register the command**

In `tabula/cli/src/index.ts`: add `import { extCommand } from "./commands/ext";` after the `workosCommand` import, and `program.addCommand(extCommand);` after `program.addCommand(workosCommand);`. Also add an example line to the help text block:

```
  $ tabcli ext update              # Pull the latest dev extension build
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bazel test //tabula/cli:unit_tests --test_output=all`
Expected: PASS (utils + ext tests).

- [ ] **Step 6: Type-gate + binary still build**

Run: `bazel build //tabula/cli/...`
Expected: success.

- [ ] **Step 7: Commit**

```bash
npx --no-install prettier --write tabula/cli/src/commands/ext.ts tabula/cli/src/commands/ext.test.ts tabula/cli/src/index.ts
git add tabula/cli/src/commands/ext.ts tabula/cli/src/commands/ext.test.ts tabula/cli/src/index.ts
git commit -m "feat(tabula): tabcli ext update/path — pull dev-latest into the load-unpacked dir"
```

---

### Task 4: Bundle ships a `build_info.json` placeholder

**Files:**

- Create: `tabula/extension/src/build_info.json`
- Modify: `tabula/extension/webpack.config.js`

- [ ] **Step 1: Create the placeholder**

`tabula/extension/src/build_info.json` (JSON — no license header):

```json
{
  "commit": "dev"
}
```

- [ ] **Step 2: Copy it into the bundle**

In `tabula/extension/webpack.config.js`, inside the `CopyPlugin` `patterns` array, after the icons entry add:

```js
        // Build identity. The source placeholder is {"commit": "dev"} (update
        // checker disabled). The dev-latest CI workflow overwrites this entry
        // INSIDE the built zip with the real {commit, builtAt, version} —
        // post-Bazel, so the webpack action stays hermetic/cacheable (the
        // same constraint that keeps the SHA out of manifest.version above).
        { from: "src/build_info.json", to: "build_info.json" },
```

- [ ] **Step 3: Verify the bundle contains it**

Run: `bazel build //tabula/extension:dist && cat bazel-bin/tabula/extension/dist/build_info.json`
Expected: `{ "commit": "dev" }` (file present in the bundle).

- [ ] **Step 4: Extension unit tests still pass**

Run: `bazel test //tabula/extension:unit_tests --test_summary=terse`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tabula/extension/src/build_info.json tabula/extension/webpack.config.js
git commit -m "feat(tabula): ship a build_info.json identity placeholder in the extension bundle"
```

---

### Task 5: Update-check service (extension)

**Files:**

- Create: `tabula/extension/src/services/updateCheck.ts`
- Create: `tabula/extension/src/services/updateCheck.test.ts`

- [ ] **Step 1: Write the failing tests**

`tabula/extension/src/services/updateCheck.test.ts` (MIT header, then:)

```ts
import { UpdateCheckService } from "./updateCheck";

// process.env.API_URL is statically replaced by webpack DefinePlugin in real
// builds; under jest it is plain process.env (set in beforeEach).

const mockChrome = {
  runtime: {
    getURL: jest.fn((p: string) => `chrome-extension://abc/${p}`),
  },
  management: {
    getSelf: jest.fn(),
  },
};
// eslint-disable-next-line @typescript-eslint/no-explicit-any
(globalThis as any).chrome = mockChrome;

const mockFetch = jest.fn();
// eslint-disable-next-line @typescript-eslint/no-explicit-any
(globalThis as any).fetch = mockFetch;

const jsonResponse = (body: unknown, ok = true) =>
  Promise.resolve({ ok, json: () => Promise.resolve(body) });

describe("UpdateCheckService", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    process.env.API_URL = "https://api.example.com/api/v1";
    mockChrome.management.getSelf.mockResolvedValue({
      installType: "development",
    });
  });

  const stubOwnBuild = (commit: string) => {
    mockFetch.mockImplementation((url: string) =>
      url.startsWith("chrome-extension://")
        ? jsonResponse({ commit })
        : jsonResponse({ commit: "serversha" }),
    );
  };

  describe("eligibility", () => {
    it("is eligible for a development install with a CI-built bundle", async () => {
      stubOwnBuild("abc1234");
      await expect(UpdateCheckService.isEligible()).resolves.toEqual({
        eligible: true,
        ownCommit: "abc1234",
      });
    });

    it('is NOT eligible when the bundle commit is "dev" (local build)', async () => {
      stubOwnBuild("dev");
      await expect(UpdateCheckService.isEligible()).resolves.toEqual({
        eligible: false,
        ownCommit: "dev",
      });
    });

    it("is NOT eligible when build_info.json cannot be read", async () => {
      mockFetch.mockResolvedValue({ ok: false });
      const result = await UpdateCheckService.isEligible();
      expect(result.eligible).toBe(false);
    });

    it("is NOT eligible for non-development installs (Web Store)", async () => {
      stubOwnBuild("abc1234");
      mockChrome.management.getSelf.mockResolvedValue({
        installType: "normal",
      });
      const result = await UpdateCheckService.isEligible();
      expect(result.eligible).toBe(false);
    });
  });

  describe("fetchDeployedCommit", () => {
    it("returns the API root's commit", async () => {
      mockFetch.mockImplementation(() => jsonResponse({ commit: "serversha" }));
      await expect(UpdateCheckService.fetchDeployedCommit()).resolves.toBe(
        "serversha",
      );
      // polls the ORIGIN root, not under /api/v1
      expect(mockFetch).toHaveBeenCalledWith("https://api.example.com/");
    });

    it('returns null for "unknown" (no false positives)', async () => {
      mockFetch.mockImplementation(() => jsonResponse({ commit: "unknown" }));
      await expect(
        UpdateCheckService.fetchDeployedCommit(),
      ).resolves.toBeNull();
    });

    it("returns null on network failure", async () => {
      mockFetch.mockRejectedValue(new Error("offline"));
      await expect(
        UpdateCheckService.fetchDeployedCommit(),
      ).resolves.toBeNull();
    });
  });

  describe("checkForUpdate", () => {
    it("reports an update when commits differ", async () => {
      stubOwnBuild("abc1234");
      await expect(UpdateCheckService.checkForUpdate()).resolves.toEqual({
        updateAvailable: true,
        ownCommit: "abc1234",
        deployedCommit: "serversha",
      });
    });

    it("reports no update when commits match", async () => {
      mockFetch.mockImplementation((url: string) =>
        url.startsWith("chrome-extension://")
          ? jsonResponse({ commit: "samesha" })
          : jsonResponse({ commit: "samesha" }),
      );
      const result = await UpdateCheckService.checkForUpdate();
      expect(result?.updateAvailable).toBe(false);
    });

    it("returns null when ineligible", async () => {
      stubOwnBuild("dev");
      await expect(UpdateCheckService.checkForUpdate()).resolves.toBeNull();
    });
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bazel test //tabula/extension:unit_tests --test_arg=updateCheck --test_output=all`
Expected: FAIL — `Cannot find module './updateCheck'`.

- [ ] **Step 3: Implement `tabula/extension/src/services/updateCheck.ts`**

(MIT header, then:)

```ts
/**
 * Dev-channel update detection (issue #45, M1).
 *
 * A load-unpacked CI-built install compares its own baked-in commit
 * (build_info.json, injected by the dev-latest workflow) against the deployed
 * dev API's GET / provenance (#32). A mismatch means a newer bundle is
 * published: the user runs `tabcli ext update`, then reloads.
 *
 * Never active for Web Store installs (installType !== "development") or
 * local ad-hoc builds (commit === "dev"). chrome.management.getSelf() is
 * exempt from the "management" permission.
 */

const { API_URL } = process.env;

export interface BuildInfo {
  commit: string;
  builtAt?: string;
  version?: string;
}

export interface UpdateCheckResult {
  updateAvailable: boolean;
  ownCommit: string;
  deployedCommit: string;
}

export class UpdateCheckService {
  /** Read this build's identity from the packaged build_info.json. */
  static async getOwnBuildInfo(): Promise<BuildInfo | null> {
    try {
      const res = await fetch(chrome.runtime.getURL("build_info.json"));
      if (!res.ok) return null;
      return (await res.json()) as BuildInfo;
    } catch {
      return null;
    }
  }

  /** Dev installs of CI-built bundles only. */
  static async isEligible(): Promise<{
    eligible: boolean;
    ownCommit: string | null;
  }> {
    const info = await this.getOwnBuildInfo();
    const ownCommit = info?.commit ?? null;
    if (!ownCommit || ownCommit === "dev") {
      return { eligible: false, ownCommit };
    }
    try {
      const self = await chrome.management.getSelf();
      if (self.installType !== "development") {
        return { eligible: false, ownCommit };
      }
    } catch {
      return { eligible: false, ownCommit };
    }
    return { eligible: true, ownCommit };
  }

  /** The deployed dev API's commit, from its GET / provenance endpoint. */
  static async fetchDeployedCommit(): Promise<string | null> {
    if (!API_URL) return null;
    try {
      const origin = new URL(API_URL).origin;
      const res = await fetch(`${origin}/`);
      if (!res.ok) return null;
      const body = (await res.json()) as { commit?: string };
      if (!body.commit || body.commit === "unknown") return null;
      return body.commit;
    } catch {
      return null;
    }
  }

  /** null = ineligible or no reliable answer (failures stay silent). */
  static async checkForUpdate(): Promise<UpdateCheckResult | null> {
    const { eligible, ownCommit } = await this.isEligible();
    if (!eligible || !ownCommit) return null;
    const deployedCommit = await this.fetchDeployedCommit();
    if (!deployedCommit) return null;
    return {
      updateAvailable: deployedCommit !== ownCommit,
      ownCommit,
      deployedCommit,
    };
  }
}

export default UpdateCheckService;
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bazel test //tabula/extension:unit_tests --test_arg=updateCheck --test_output=all`
Expected: PASS — all updateCheck tests green.

- [ ] **Step 5: Commit**

```bash
npx --no-install prettier --write tabula/extension/src/services/updateCheck.ts tabula/extension/src/services/updateCheck.test.ts
git add tabula/extension/src/services/updateCheck.ts tabula/extension/src/services/updateCheck.test.ts
git commit -m "feat(tabula): update-check service — own build commit vs deployed API commit"
```

---

### Task 6: UpdateBanner component + Dashboard mount

**Files:**

- Create: `tabula/extension/src/components/UpdateBanner.tsx`
- Create: `tabula/extension/src/components/UpdateBanner.test.tsx`
- Modify: `tabula/extension/src/dashboard/Dashboard.tsx` (import + mount next to `<SyncStatusIndicator />`, line ~1043)
- Modify: `tabula/extension/src/styles/components.css`

- [ ] **Step 1: Write the failing tests**

`tabula/extension/src/components/UpdateBanner.test.tsx` (MIT header, then:)

```tsx
import React from "react";
import { render, screen, fireEvent, act } from "@testing-library/react";
import "@testing-library/jest-dom";
import { UpdateBanner } from "./UpdateBanner";
import { UpdateCheckService } from "../services/updateCheck";

jest.mock("../services/updateCheck");

const mockReload = jest.fn();
// eslint-disable-next-line @typescript-eslint/no-explicit-any
(globalThis as any).chrome = {
  ...((globalThis as any).chrome ?? {}),
  runtime: { reload: mockReload },
};

const checkForUpdate = UpdateCheckService.checkForUpdate as jest.Mock;

describe("UpdateBanner", () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it("renders nothing when no update is available", async () => {
    checkForUpdate.mockResolvedValue({
      updateAvailable: false,
      ownCommit: "a",
      deployedCommit: "a",
    });
    render(<UpdateBanner />);
    await act(async () => {});
    expect(screen.queryByRole("status")).not.toBeInTheDocument();
  });

  it("renders nothing when the check is ineligible (null)", async () => {
    checkForUpdate.mockResolvedValue(null);
    render(<UpdateBanner />);
    await act(async () => {});
    expect(screen.queryByRole("status")).not.toBeInTheDocument();
  });

  it("shows the deployed short-sha and reloads on click", async () => {
    checkForUpdate.mockResolvedValue({
      updateAvailable: true,
      ownCommit: "oldsha12",
      deployedCommit: "newsha9876",
    });
    render(<UpdateBanner />);
    await act(async () => {});

    expect(screen.getByRole("status")).toHaveTextContent("newsha9");
    expect(screen.getByRole("status")).toHaveTextContent("tabcli ext update");

    fireEvent.click(screen.getByRole("button", { name: /reload/i }));
    expect(mockReload).toHaveBeenCalled();
  });

  it("dismiss hides the banner for that deployed commit", async () => {
    checkForUpdate.mockResolvedValue({
      updateAvailable: true,
      ownCommit: "oldsha12",
      deployedCommit: "newsha9876",
    });
    render(<UpdateBanner />);
    await act(async () => {});

    fireEvent.click(screen.getByRole("button", { name: /dismiss/i }));
    expect(screen.queryByRole("status")).not.toBeInTheDocument();
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bazel test //tabula/extension:unit_tests --test_arg=UpdateBanner --test_output=all`
Expected: FAIL — `Cannot find module './UpdateBanner'`.

- [ ] **Step 3: Implement `tabula/extension/src/components/UpdateBanner.tsx`**

(MIT header, then:)

```tsx
/**
 * UpdateBanner — dev-channel "new build available" nudge (issue #45, M1).
 *
 * Polls UpdateCheckService on mount and every 15 minutes. When the deployed
 * commit differs from this build's commit, offers Reload
 * (chrome.runtime.reload()) — the user runs `tabcli ext update` first so the
 * on-disk files are already the new build. Failures stay silent; the fixed
 * interval is the backoff. Dismiss hides the banner for that deployed commit.
 */

import React, { useEffect, useState } from "react";
import { UpdateCheckService } from "../services/updateCheck";

const POLL_INTERVAL_MS = 15 * 60 * 1000;

export const UpdateBanner: React.FC = () => {
  const [deployedCommit, setDeployedCommit] = useState<string | null>(null);
  const [dismissedCommit, setDismissedCommit] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    const check = async () => {
      const result = await UpdateCheckService.checkForUpdate();
      if (cancelled) return;
      // null = ineligible or no reliable answer — keep the current banner
      // state rather than flickering it off on a transient failure.
      if (result === null) return;
      setDeployedCommit(result.updateAvailable ? result.deployedCommit : null);
    };
    check();
    const id = setInterval(check, POLL_INTERVAL_MS);
    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, []);

  if (!deployedCommit || deployedCommit === dismissedCommit) return null;

  return (
    <div className="update-banner" role="status">
      <span>
        New build deployed ({deployedCommit.slice(0, 7)}) — run{" "}
        <code>tabcli ext update</code>, then reload.
      </span>
      <button
        type="button"
        className="update-banner-reload"
        onClick={() => chrome.runtime.reload()}
      >
        Reload
      </button>
      <button
        type="button"
        className="update-banner-dismiss"
        onClick={() => setDismissedCommit(deployedCommit)}
      >
        Dismiss
      </button>
    </div>
  );
};
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bazel test //tabula/extension:unit_tests --test_arg=UpdateBanner --test_output=all`
Expected: PASS.

- [ ] **Step 5: Mount in the Dashboard + styles**

In `tabula/extension/src/dashboard/Dashboard.tsx`:

- Add `import { UpdateBanner } from "../components/UpdateBanner";` next to the `SyncStatusIndicator` import (line ~42).
- Render `<UpdateBanner />` as a **sibling immediately BEFORE** the Sync Status Indicator footer `<div>` (the flex-row div with `justifyContent: "space-between"`), NOT inside it. When visible, the banner is full sidebar-width and does not squeeze `<SyncStatusIndicator />`.

Append to `tabula/extension/src/styles/components.css`:

```css
/* Dev-channel update banner (UpdateBanner.tsx). The yellow background is
   intentionally theme-invariant, so the text color must be pinned dark —
   the inherited body color is near-white under [data-theme='dark']. */
.update-banner {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
  margin: 8px 16px 0;
  padding: 6px 12px;
  border-radius: 6px;
  background: #fff8e1;
  border: 1px solid #f0c36d;
  color: rgb(41, 47, 61);
  font-size: 13px;
}
.update-banner code {
  font-family: monospace;
  background: rgba(0, 0, 0, 0.06);
  padding: 1px 4px;
  border-radius: 3px;
}
.update-banner button {
  border: 1px solid #f0c36d;
  background: transparent;
  color: rgb(41, 47, 61);
  border-radius: 4px;
  padding: 2px 8px;
  cursor: pointer;
}
.update-banner button:hover {
  background: rgba(0, 0, 0, 0.06);
}
.update-banner .update-banner-reload {
  font-weight: 600;
}
```

- [ ] **Step 6: Full extension suite + bundle build**

Run: `bazel test //tabula/extension:unit_tests --test_summary=terse && bazel build //tabula/extension:dist`
Expected: all tests PASS; dist builds.

- [ ] **Step 7: Commit**

```bash
npx --no-install prettier --write tabula/extension/src/components/UpdateBanner.tsx tabula/extension/src/components/UpdateBanner.test.tsx tabula/extension/src/dashboard/Dashboard.tsx tabula/extension/src/styles/components.css
git add tabula/extension/src/components/UpdateBanner.tsx tabula/extension/src/components/UpdateBanner.test.tsx tabula/extension/src/dashboard/Dashboard.tsx tabula/extension/src/styles/components.css
git commit -m "feat(tabula): dashboard update banner for dev installs"
```

---

### Task 7: dev-latest publish workflow

**Files:**

- Create: `.github/workflows/tabula-dev-latest.yaml`

- [ ] **Step 1: Create the workflow**

(`#`-style MIT header like `.github/workflows/tabula-release.yml`, then:)

```yaml
# Publishes a rolling "dev-latest" extension bundle on every main commit that
# touches the extension. The fixed prerelease tag tabula-extension-dev-latest
# hosts two assets, overwritten per run:
#   tabula-extension-chrome.zip  — the dist_release bundle with build_info.json
#                                  stamped to the real commit (injected POST
#                                  Bazel build: the webpack action must stay
#                                  hermetic, see tabula/extension/webpack.config.js)
#   build_info.json              — the same identity, downloadable on its own
# Consumed by `tabcli ext update` and the in-extension update banner (#45).
# Release-please owns tabula-extension-v* tags; this fixed tag never collides.

name: tabula-dev-latest

on:
  push:
    branches: [main]
    paths:
      # Union with tabula-deploy.yaml's trigger paths: the banner clears only
      # when the published bundle's commit equals the deployed API's commit,
      # so BOTH artifacts must re-stamp on any commit that moves either.
      - "tabula/extension/**"
      - "tabula/shared/**"
      - "tabula/api/**"
      - "infrastructure/pulumi/apps/tabula/**"
      - ".github/workflows/tabula-dev-latest.yaml"
      - ".github/workflows/tabula-deploy.yaml"

permissions:
  contents: write

concurrency:
  group: tabula-dev-latest
  cancel-in-progress: true

jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6

      - name: Set up Bazel
        uses: bazel-contrib/setup-bazel@c5acdfb288317d0b5c0bbd7a396a3dc868bb0f86 # 0.19.0
        with:
          bazelisk-cache: true
          repository-cache: true

      - name: Build extension bundle
        run: bazel build //tabula/extension:chrome_zip

      - name: Stamp build identity into the bundle
        run: |
          cp bazel-bin/tabula/extension/tabula-extension-chrome.zip \
            "$RUNNER_TEMP/tabula-extension-chrome.zip"
          chmod +w "$RUNNER_TEMP/tabula-extension-chrome.zip"
          VERSION="$(node -p "require('./tabula/extension/package.json').version")"
          cd "$RUNNER_TEMP"
          printf '{"commit":"%s","builtAt":"%s","version":"%s"}\n' \
            "$GITHUB_SHA" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$VERSION" \
            > build_info.json
          # zip updates the existing (placeholder) entry in place
          zip -q tabula-extension-chrome.zip build_info.json

      - name: Publish to the rolling dev-latest prerelease
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          TAG: tabula-extension-dev-latest
        run: |
          gh release view "$TAG" >/dev/null 2>&1 || \
            gh release create "$TAG" --prerelease \
              --title "tabula-extension dev-latest (rolling)" \
              --notes "Rolling dev bundle; assets overwritten on every main commit."
          gh release upload "$TAG" \
            "$RUNNER_TEMP/tabula-extension-chrome.zip" \
            "$RUNNER_TEMP/build_info.json" \
            --clobber
          gh release edit "$TAG" \
            --notes "commit: ${GITHUB_SHA} — built $(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

- [ ] **Step 2: Lint the workflow**

Run: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/tabula-dev-latest.yaml')); print('YAML OK')"`
Expected: `YAML OK`. (If `actionlint` is installed, run it too.)

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/tabula-dev-latest.yaml
git commit -m "ci(tabula): rolling dev-latest extension bundle per main commit"
```

---

### Task 8: Docs + final verification

**Files:**

- Create: `tabula/extension/docs/DEV_UPDATES.md`
- Modify: `tabula/cli/README.md` (add `ext` to the commands section — read the file and follow its existing command-doc format)

- [ ] **Step 1: Write the tester how-to**

`tabula/extension/docs/DEV_UPDATES.md`:

```markdown
# Dev builds & self-update

Every `main` commit touching `tabula/extension/**` publishes a rolling
prerelease (`tabula-extension-dev-latest`) with the built bundle, stamped with
the source commit (`build_info.json`).

## One-time setup

1. `tabcli ext update` — downloads the latest bundle to `~/.tabula/extension`
   (override with `--dir`).
2. `chrome://extensions` → enable **Developer mode** → **Load unpacked** →
   pick the directory printed by `tabcli ext path`.

## Updating

When a newer build is deployed, the dashboard shows a banner
("New build deployed (…) — run `tabcli ext update`, then reload"):

1. `tabcli ext update`
2. Click **Reload** in the banner (or ↻ on chrome://extensions).

The banner only appears on load-unpacked installs of CI-built bundles —
local `npm run build` bundles carry `commit: "dev"` and never check. The
check compares this build's commit against the deployed dev API's `GET /`
provenance and polls every 15 minutes; network failures stay silent.

Requirements: `gh` (authenticated: `gh auth login`) and `unzip` on PATH.
```

- [ ] **Step 2: Document `tabcli ext` in the CLI README**

Read `tabula/cli/README.md`; add an `ext` section following the existing per-command format, covering `ext update` (with `--dir`, `--repo`) and `ext path`, linking to `tabula/extension/docs/DEV_UPDATES.md`.

- [ ] **Step 3: Full verification sweep**

Run, in order; all must pass:

```bash
bazel test //tabula/cli:unit_tests //tabula/extension:unit_tests --test_summary=terse
bazel build //tabula/extension:dist //tabula/extension:chrome_zip //tabula/cli/...
npx --no-install prettier --check $(git diff --name-only origin/main -- '*.ts' '*.tsx' '*.js' '*.json' '*.md' | tr '\n' ' ')
bazel run //:tidy 2>/dev/null || true   # if the repo's tidy target applies, ensure no diff
git status --short                       # only intended files
```

- [ ] **Step 4: Commit docs**

```bash
git add tabula/extension/docs/DEV_UPDATES.md tabula/cli/README.md
git commit -m "docs(tabula): dev self-update how-to + tabcli ext reference"
```

- [ ] **Step 5: Push and open the PR**

```bash
git push -u origin feat/tabula-dev-self-update
gh pr create --base main --title "feat(tabula): dev-channel self-update — dev-latest bundle, tabcli ext, update banner (#45 M1)" --body "<summarize: spec link, the loop, components, verification; note M2/M3 roadmap stays in #45>"
```

Expected follow-ups after merge (manual, documented in the PR body): first `tabula-dev-latest` run publishes the release; run `tabcli ext update`; load-unpack once; verify the banner appears after the _next_ main commit deploys the API.

---

## Self-review notes

- **Spec coverage:** build identity (Task 4 + 7), CI publish (7), tabcli update/path + atomic swap + errors (2, 3), checker gates + polling + silence-on-failure (5), banner + reload + dismiss (6), docs (8), no-Playwright decision honored (tests are jest-only), M2/M3 untouched.
- **Type consistency:** `BundleInfo` (cli) vs `BuildInfo` (extension) are intentionally separate modules with separate shapes; `DEV_LATEST_TAG`/`DEFAULT_REPO` only referenced from `utils/extension.ts`; `UpdateCheckService.checkForUpdate()` return shape matches the banner's usage.
- **Known judgment calls:** rollback test in Task 2 mocks `fs.renameSync` selectively (first call real, second throws); CLI command happy-path (gh+unzip orchestration) is deliberately not integration-tested — utils carry the risk and are fully tested; manual verification closes the loop post-merge.
