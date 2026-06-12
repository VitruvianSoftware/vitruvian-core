# Tabula Release Channels (M2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add alpha/beta release channels to the load-unpacked self-update loop (M1), with stable visibly reserved for the M3 Web Store listing.

**Architecture:** The install describes itself — `tabcli ext update` writes `channel.json` next to `build_info.json`; bare updates stay on-channel, `--channel` switches. Beta rides the existing `tabula-extension-v*` release zips (now stamped with `build_info.json`, same post-Bazel mechanism as dev-latest). Both update signals reuse the dev API's `GET /`: alpha compares commits (M1, unchanged), beta compares lockstep versions. The extension's banner and a new Settings "Developer" section become channel-aware; the Settings picker displays + guides (copyable `tabcli` command) and never swaps files.

**Tech Stack:** commander + `gh` CLI (tabcli), GitHub Actions, React 18, jest + @swc/jest, Bazel.

**Spec:** `docs/superpowers/specs/2026-06-12-tabula-release-channels-design.md`

**Branch:** `feat/tabula-release-channels` (already created; spec committed on it).

**Conventions for every task:**

- New `.ts`/`.tsx` files start with the exact 21-line MIT header from the top of `tabula/cli/src/index.ts`.
- `npx --no-install prettier --write <changed files>` before each commit.
- All commands run from the repo root. Never switch branches or push.

---

## File map

| File                                                       | Action | Responsibility                                                             |
| ---------------------------------------------------------- | ------ | -------------------------------------------------------------------------- |
| `tabula/cli/src/utils/extension.ts`                        | modify | channel types/helpers, semver compare, release-tag resolution              |
| `tabula/cli/src/utils/extension.test.ts`                   | modify | tests for the above                                                        |
| `tabula/cli/src/commands/ext.ts`                           | modify | `--channel` flag, channel-aware update flow, `runToolCapture`              |
| `tabula/cli/src/commands/ext.test.ts`                      | modify | channel wiring + resolution tests                                          |
| `.github/workflows/tabula-release.yml`                     | modify | stamp `build_info.json` into release zips                                  |
| `tabula/extension/src/services/updateCheck.ts`             | modify | channel read, `fetchDeployedInfo`, `compareVersions`, channel-aware result |
| `tabula/extension/src/services/updateCheck.test.ts`        | modify | channel-aware service tests                                                |
| `tabula/extension/src/components/UpdateBanner.tsx`         | modify | per-channel copy, dismiss keyed on offered value                           |
| `tabula/extension/src/components/UpdateBanner.test.tsx`    | modify | per-channel banner tests                                                   |
| `tabula/extension/src/components/AccountSettings.tsx`      | modify | Developer section in Preferences                                           |
| `tabula/extension/src/components/AccountSettings.test.tsx` | modify | service mock + Developer section tests                                     |
| `tabula/extension/src/dashboard/Dashboard.tsx`             | modify | footer `v… · channel · sha7`                                               |
| `tabula/extension/docs/DEV_UPDATES.md`                     | modify | channels how-to                                                            |
| `tabula/cli/README.md`                                     | modify | `--channel` docs                                                           |

---

### Task 1: tabcli channel + release-resolution helpers (utils)

Pure, fully testable helpers. TDD.

**Files:**

- Modify: `tabula/cli/src/utils/extension.ts`
- Modify: `tabula/cli/src/utils/extension.test.ts`

- [ ] **Step 1: Write the failing tests** — append to `tabula/cli/src/utils/extension.test.ts` (inside the file, after the existing `atomicInstall` describe; extend the top import from `./extension` with the new symbols):

```ts
describe("channel helpers", () => {
  it("readInstalledChannel reads a valid channel.json", () => {
    const dir = mkTmp();
    fs.writeFileSync(
      path.join(dir, "channel.json"),
      JSON.stringify({ channel: "beta" }),
    );
    expect(readInstalledChannel(dir)).toBe("beta");
  });

  it("readInstalledChannel returns null for absent, corrupt, or unknown values", () => {
    const dir = mkTmp();
    expect(readInstalledChannel(dir)).toBeNull();
    fs.writeFileSync(path.join(dir, "channel.json"), "not json");
    expect(readInstalledChannel(dir)).toBeNull();
    fs.writeFileSync(
      path.join(dir, "channel.json"),
      JSON.stringify({ channel: "stable" }),
    );
    expect(readInstalledChannel(dir)).toBeNull();
  });

  it("writeInstalledChannel round-trips", () => {
    const dir = mkTmp();
    writeInstalledChannel(dir, "alpha");
    expect(readInstalledChannel(dir)).toBe("alpha");
  });
});

describe("resolveChannel", () => {
  it("explicit flag wins over installed channel", () => {
    expect(resolveChannel("beta", "alpha")).toBe("beta");
  });

  it("falls back to the installed channel, then alpha", () => {
    expect(resolveChannel(undefined, "beta")).toBe("beta");
    expect(resolveChannel(undefined, null)).toBe("alpha");
  });

  it("explains that stable arrives with the Web Store listing (M3)", () => {
    expect(() => resolveChannel("stable", null)).toThrow(/Web Store.*M3/);
  });

  it("rejects unknown channels listing the valid ones", () => {
    expect(() => resolveChannel("nightly", null)).toThrow(
      /alpha, beta, stable/,
    );
  });
});

describe("compareSemver", () => {
  it("orders numerically per segment", () => {
    expect(compareSemver("0.10.0", "0.9.9")).toBeGreaterThan(0);
    expect(compareSemver("1.0.0", "1.0.0")).toBe(0);
    expect(compareSemver("0.1.9", "0.2.0")).toBeLessThan(0);
  });

  it("treats missing segments as zero", () => {
    expect(compareSemver("1.0", "1.0.0")).toBe(0);
    expect(compareSemver("1.0.1", "1.0")).toBeGreaterThan(0);
  });
});

describe("resolveLatestExtensionTag", () => {
  it("picks the highest tabula-extension-v* among monorepo tag noise", () => {
    const json = JSON.stringify([
      { tagName: "tabula-cli-v0.3.0" },
      { tagName: "tabula-extension-v0.1.9" },
      { tagName: "tabula-extension-dev-latest" },
      { tagName: "tabula-extension-v0.1.10" },
      { tagName: "devx-v1.2.3" },
      { tagName: "tabula-extension-v0.1.2" },
    ]);
    expect(resolveLatestExtensionTag(json)).toBe("tabula-extension-v0.1.10");
  });

  it("returns null when no extension release exists", () => {
    expect(
      resolveLatestExtensionTag(JSON.stringify([{ tagName: "devx-v1.0.0" }])),
    ).toBeNull();
    expect(resolveLatestExtensionTag("[]")).toBeNull();
  });

  it("returns null on unparseable input", () => {
    expect(resolveLatestExtensionTag("gh exploded")).toBeNull();
  });
});
```

- [ ] **Step 2: Run to verify failure**

Run: `bazel test //tabula/cli:unit_tests --test_output=all`
Expected: FAIL — the new symbols are not exported from `./extension`.

- [ ] **Step 3: Implement** — append to `tabula/cli/src/utils/extension.ts`:

```ts
/**
 * Switchable release channels for the load-unpacked install (M2 of #45).
 * "stable" exists in the UX but is not installable until the Web Store
 * listing ships (M3) — see resolveChannel.
 */
export type InstallChannel = "alpha" | "beta";

/** Tag prefix of release-please's extension releases (beta channel source). */
export const EXTENSION_RELEASE_TAG_PREFIX = "tabula-extension-v";

/** Read the install's channel marker; null when absent/corrupt/unknown. */
export function readInstalledChannel(dir: string): InstallChannel | null {
  try {
    const parsed = JSON.parse(
      fs.readFileSync(path.join(dir, "channel.json"), "utf-8"),
    ) as { channel?: string };
    return parsed.channel === "alpha" || parsed.channel === "beta"
      ? parsed.channel
      : null;
  } catch {
    return null;
  }
}

/** Label the install with the channel it was installed from. */
export function writeInstalledChannel(
  dir: string,
  channel: InstallChannel,
): void {
  fs.writeFileSync(
    path.join(dir, "channel.json"),
    `${JSON.stringify({ channel }, null, 2)}\n`,
  );
}

/** Precedence: explicit flag > installed channel.json > alpha. */
export function resolveChannel(
  flag: string | undefined,
  installed: InstallChannel | null,
): InstallChannel {
  if (flag === "stable") {
    throw new Error(
      "The stable channel arrives with the Chrome Web Store listing (M3) — use --channel alpha or beta for now.",
    );
  }
  if (flag === "alpha" || flag === "beta") return flag;
  if (flag !== undefined) {
    throw new Error(`Unknown channel '${flag}' — valid: alpha, beta, stable.`);
  }
  return installed ?? "alpha";
}

/**
 * Numeric-segment version compare (missing segments are zero).
 * Mirrors compareVersions in tabula/extension/src/services/updateCheck.ts —
 * duplicated deliberately: the CLI must not depend on extension code.
 */
export function compareSemver(a: string, b: string): number {
  const as = a.split(".").map((s) => parseInt(s, 10) || 0);
  const bs = b.split(".").map((s) => parseInt(s, 10) || 0);
  const len = Math.max(as.length, bs.length);
  for (let i = 0; i < len; i += 1) {
    const diff = (as[i] ?? 0) - (bs[i] ?? 0);
    if (diff !== 0) return diff;
  }
  return 0;
}

/**
 * Pick the newest tabula-extension-v* tag from `gh release list --json
 * tagName` output. Pure (takes the JSON text) so it is testable without gh.
 * Null when no extension release exists or the input is unparseable.
 */
export function resolveLatestExtensionTag(
  releaseListJson: string,
): string | null {
  try {
    const releases = JSON.parse(releaseListJson) as { tagName?: string }[];
    const versions = releases
      .map((r) => r.tagName ?? "")
      .filter((t) => t.startsWith(EXTENSION_RELEASE_TAG_PREFIX))
      .map((t) => t.slice(EXTENSION_RELEASE_TAG_PREFIX.length))
      .filter((v) => /^\d+(\.\d+)*$/.test(v));
    if (versions.length === 0) return null;
    versions.sort(compareSemver);
    return `${EXTENSION_RELEASE_TAG_PREFIX}${versions[versions.length - 1]}`;
  } catch {
    return null;
  }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `bazel test //tabula/cli:unit_tests --test_output=all`
Expected: PASS — all new describes green, existing 12 tests untouched.

- [ ] **Step 5: Commit**

```bash
npx --no-install prettier --write tabula/cli/src/utils/extension.ts tabula/cli/src/utils/extension.test.ts
git add tabula/cli/src/utils/extension.ts tabula/cli/src/utils/extension.test.ts
git commit -m "feat(tabula): tabcli channel + release-tag resolution helpers"
```

---

### Task 2: channel-aware `tabcli ext update`

**Files:**

- Modify: `tabula/cli/src/commands/ext.ts`
- Modify: `tabula/cli/src/commands/ext.test.ts`

- [ ] **Step 1: Write the failing tests** — in `tabula/cli/src/commands/ext.test.ts`, extend the import from `./ext` to also pull `runToolCapture`, and append:

```ts
describe("update --channel option", () => {
  it("declares the --channel option", () => {
    const updateCmd = extCommand.commands.find((c) => c.name() === "update")!;
    const chOpt = updateCmd.options.find((o) => o.long === "--channel");
    expect(chOpt).toBeDefined();
    expect(chOpt!.defaultValue).toBeUndefined(); // installed channel decides
  });
});

describe("runToolCapture", () => {
  it("returns captured stdout on success", () => {
    (spawnSync as jest.Mock).mockReturnValue({
      error: undefined,
      status: 0,
      stdout: '[{"tagName":"tabula-extension-v0.1.9"}]',
    });
    expect(runToolCapture("gh", ["release", "list"])).toBe(
      '[{"tagName":"tabula-extension-v0.1.9"}]',
    );
  });

  it("explains when the tool is not installed", () => {
    (spawnSync as jest.Mock).mockReturnValue({
      error: Object.assign(new Error("spawn gh ENOENT"), { code: "ENOENT" }),
      status: null,
    });
    expect(() => runToolCapture("gh", ["release", "list"])).toThrow(
      /'gh' not found on PATH/,
    );
  });

  it("surfaces non-zero exits with the command line", () => {
    (spawnSync as jest.Mock).mockReturnValue({
      error: undefined,
      status: 1,
      stdout: "",
    });
    expect(() => runToolCapture("gh", ["release", "list"])).toThrow(
      /gh release list failed \(exit 1\)/,
    );
  });
});
```

- [ ] **Step 2: Run to verify failure**

Run: `bazel test //tabula/cli:unit_tests --test_output=all`
Expected: FAIL — `runToolCapture` is not exported; the `--channel` option test fails.

- [ ] **Step 3: Implement** — in `tabula/cli/src/commands/ext.ts`:

a) Extend the utils import:

```ts
import {
  DEFAULT_REPO,
  DEV_LATEST_TAG,
  type InstallChannel,
  atomicInstall,
  defaultExtensionDir,
  readBundleInfo,
  readInstalledChannel,
  resolveChannel,
  resolveLatestExtensionTag,
  writeInstalledChannel,
} from "../utils/extension";
```

b) Add `runToolCapture` directly below `runTool`:

```ts
/** Run an external tool capturing stdout (stderr still inherited). */
export function runToolCapture(cmd: string, args: string[]): string {
  const res = spawnSync(cmd, args, {
    stdio: ["ignore", "pipe", "inherit"],
    encoding: "utf-8",
  });
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
  return res.stdout ?? "";
}
```

c) Replace the whole `update` subcommand registration with the channel-aware version:

```ts
extCommand
  .command("update")
  .description(
    "Download the channel's latest build into the load-unpacked directory",
  )
  .option("--dir <path>", "extension directory", defaultExtensionDir())
  .option("--repo <owner/repo>", "GitHub repository", DEFAULT_REPO)
  .option(
    "--channel <channel>",
    "release channel: alpha (every main commit) | beta (latest release cut) | stable (M3). Defaults to the installed channel, else alpha.",
  )
  .action((opts: { dir: string; repo: string; channel?: string }) => {
    try {
      const target = path.resolve(opts.dir);
      const channel: InstallChannel = resolveChannel(
        opts.channel,
        readInstalledChannel(target),
      );

      // Per-channel artifact: alpha = the rolling dev-latest prerelease;
      // beta = the newest tabula-extension-v* release (the cut's own zip,
      // promoted — never rebuilt).
      let tag = DEV_LATEST_TAG;
      let zipName = "tabula-extension-chrome.zip";
      if (channel === "beta") {
        const listJson = runToolCapture("gh", [
          "release",
          "list",
          "--repo",
          opts.repo,
          "--limit",
          "100",
          "--json",
          "tagName",
        ]);
        const latest = resolveLatestExtensionTag(listJson);
        if (!latest) {
          throw new Error(
            `No tabula-extension-v* release found in ${opts.repo} — the beta channel needs at least one release cut.`,
          );
        }
        tag = latest;
        zipName = `${latest}-chrome.zip`;
      }

      const downloadDir = fs.mkdtempSync(path.join(os.tmpdir(), "tabula-ext-"));
      // Staging must share a filesystem with the target for an atomic rename.
      const staging = `${target}.staging-${process.pid}`;
      try {
        console.log(`Fetching ${tag} (${channel}) from ${opts.repo}…`);
        runTool("gh", [
          "release",
          "download",
          tag,
          "--repo",
          opts.repo,
          "--pattern",
          zipName,
          "--dir",
          downloadDir,
          "--clobber",
        ]);
        // A run killed mid-unzip strands this dir; with a recycled pid the
        // overlayed unzip below could leak stale files into the install.
        fs.rmSync(staging, { recursive: true, force: true });
        fs.mkdirSync(staging, { recursive: true });
        runTool("unzip", [
          "-o",
          "-q",
          path.join(downloadDir, zipName),
          "-d",
          staging,
        ]);
        atomicInstall(staging, target);
        // Label only a SUCCESSFUL install — a failed update must never
        // relabel the surviving previous install.
        writeInstalledChannel(target, channel);

        const info = readBundleInfo(target);
        const identity = [
          info?.version ? `v${info.version}` : null,
          info?.commit ? `(${info.commit.slice(0, 7)})` : null,
        ]
          .filter(Boolean)
          .join(" ");
        console.log(
          chalk.green(
            `✓ Installed ${channel} ${identity || "build"} → ${target}`,
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
    } catch (error) {
      if (error instanceof Error) {
        console.error(chalk.red(error.message));
      }
      process.exit(1);
    }
  });
```

- [ ] **Step 4: Run to verify pass**

Run: `bazel test //tabula/cli:unit_tests --test_output=all`
Expected: PASS (all utils + command tests).

- [ ] **Step 5: Build the binary + type gate**

Run: `bazel build //tabula/cli/...`
Expected: success.

- [ ] **Step 6: Commit**

```bash
npx --no-install prettier --write tabula/cli/src/commands/ext.ts tabula/cli/src/commands/ext.test.ts
git add tabula/cli/src/commands/ext.ts tabula/cli/src/commands/ext.test.ts
git commit -m "feat(tabula): channel-aware tabcli ext update (alpha/beta, stable reserved)"
```

---

### Task 3: stamp release zips (CI)

**Files:**

- Modify: `.github/workflows/tabula-release.yml`

- [ ] **Step 1: Replace the "Attach to release" step** of the `package-extension` job (currently `cp … "${TAG}-chrome.zip"` + `gh release upload`) with:

```yaml
- name: Stamp build identity and attach to release
  env:
    GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    TAG: ${{ needs.release-please.outputs.extension_tag_name }}
  run: |
    cp bazel-bin/tabula/extension/tabula-extension-chrome.zip \
      "$RUNNER_TEMP/${TAG}-chrome.zip"
    chmod +w "$RUNNER_TEMP/${TAG}-chrome.zip"
    VERSION="${TAG#tabula-extension-v}"
    cd "$RUNNER_TEMP"
    printf '{"commit":"%s","builtAt":"%s","version":"%s"}\n' \
      "$GITHUB_SHA" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$VERSION" \
      > build_info.json
    # Replace the placeholder entry in place — same post-Bazel stamping
    # as tabula-dev-latest.yaml; the hermetic build stays untouched.
    # Without this, beta installs would carry commit "dev" and the
    # update checker would disable itself.
    zip -q "${TAG}-chrome.zip" build_info.json
    gh release upload "$TAG" "$RUNNER_TEMP/${TAG}-chrome.zip"
```

- [ ] **Step 2: Lint**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/tabula-release.yml')); print('YAML OK')"`
Expected: `YAML OK`. Run `actionlint .github/workflows/tabula-release.yml` too if available.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/tabula-release.yml
git commit -m "ci(tabula): stamp build_info.json into extension release zips (beta channel identity)"
```

---

### Task 4: channel-aware update-check service (extension)

**Files:**

- Modify: `tabula/extension/src/services/updateCheck.ts`
- Modify: `tabula/extension/src/services/updateCheck.test.ts`

The result shape changes (`{channel, updateAvailable, current, latest}` replaces `{updateAvailable, ownCommit, deployedCommit}`), so existing tests are updated in the same task.

- [ ] **Step 1: Write the failing tests** — rework `tabula/extension/src/services/updateCheck.test.ts`:

a) Extend the service import:

```ts
import {
  UpdateCheckService,
  compareVersions,
  resetBuildInfoCacheForTests,
  resetChannelCacheForTests,
} from "./updateCheck";
```

b) The chrome mock at the top gains a manifest version (alongside `getURL`):

```ts
const mockChrome = {
  runtime: {
    getURL: jest.fn((p: string) => `chrome-extension://abc/${p}`),
    getManifest: jest.fn(() => ({ version: "0.1.9" })),
  },
  management: {
    getSelf: jest.fn(),
  },
};
```

c) In `beforeEach`, after `resetBuildInfoCacheForTests();` add `resetChannelCacheForTests();`.

d) Replace `stubOwnBuild` with a channel-aware stub (build_info AND channel.json AND API in one fetch mock):

```ts
const stubInstall = (opts: {
  commit?: string;
  channel?: string | null; // null => channel.json fetch fails (pre-M2 install)
  apiCommit?: string;
  apiVersion?: string;
}) => {
  const {
    commit = "abc1234",
    channel = "alpha",
    apiCommit = "serversha",
    apiVersion = "0.1.9",
  } = opts;
  mockFetch.mockImplementation((url: string) => {
    if (url.endsWith("build_info.json")) return jsonResponse({ commit });
    if (url.endsWith("channel.json")) {
      return channel === null
        ? Promise.resolve({ ok: false })
        : jsonResponse({ channel });
    }
    return jsonResponse({ commit: apiCommit, version: apiVersion });
  });
};
```

e) Update the THREE existing `fetchDeployedCommit` tests to the renamed `fetchDeployedInfo` (same scenarios, new shape):

```ts
describe("fetchDeployedInfo", () => {
  it("returns the API root's commit and version", async () => {
    mockFetch.mockImplementation(() =>
      jsonResponse({ commit: "serversha", version: "0.2.0" }),
    );
    await expect(UpdateCheckService.fetchDeployedInfo()).resolves.toEqual({
      commit: "serversha",
      version: "0.2.0",
    });
    expect(mockFetch).toHaveBeenCalledWith(
      "https://api.example.com/",
      expect.objectContaining({ cache: "no-store" }),
    );
  });

  it('returns null for an "unknown" commit (no false positives)', async () => {
    mockFetch.mockImplementation(() =>
      jsonResponse({ commit: "unknown", version: "0.2.0" }),
    );
    await expect(UpdateCheckService.fetchDeployedInfo()).resolves.toBeNull();
  });

  it("returns null on network failure", async () => {
    mockFetch.mockRejectedValue(new Error("offline"));
    await expect(UpdateCheckService.fetchDeployedInfo()).resolves.toBeNull();
  });

  it("tolerates a missing version field (alpha can still work)", async () => {
    mockFetch.mockImplementation(() => jsonResponse({ commit: "serversha" }));
    await expect(UpdateCheckService.fetchDeployedInfo()).resolves.toEqual({
      commit: "serversha",
      version: null,
    });
  });
});
```

f) Update the existing `checkForUpdate` describe to the new result shape and add channel coverage (replace the old three tests):

```ts
describe("checkForUpdate — alpha", () => {
  it("reports an update when commits differ", async () => {
    stubInstall({ commit: "abc1234", apiCommit: "serversha" });
    await expect(UpdateCheckService.checkForUpdate()).resolves.toEqual({
      channel: "alpha",
      updateAvailable: true,
      current: "abc1234",
      latest: "serversha",
    });
  });

  it("reports no update when commits match", async () => {
    stubInstall({ commit: "samesha", apiCommit: "samesha" });
    const result = await UpdateCheckService.checkForUpdate();
    expect(result?.updateAvailable).toBe(false);
  });

  it("treats a missing channel.json as alpha (pre-M2 install)", async () => {
    stubInstall({ channel: null, commit: "abc1234", apiCommit: "newsha" });
    const result = await UpdateCheckService.checkForUpdate();
    expect(result?.channel).toBe("alpha");
    expect(result?.updateAvailable).toBe(true);
  });

  it("returns null when ineligible", async () => {
    stubInstall({ commit: "dev" });
    await expect(UpdateCheckService.checkForUpdate()).resolves.toBeNull();
  });
});

describe("checkForUpdate — beta", () => {
  it("reports an update when the API version is newer", async () => {
    stubInstall({ channel: "beta", apiVersion: "0.2.0" }); // own manifest 0.1.9
    await expect(UpdateCheckService.checkForUpdate()).resolves.toEqual({
      channel: "beta",
      updateAvailable: true,
      current: "0.1.9",
      latest: "0.2.0",
    });
  });

  it("reports no update when versions match", async () => {
    stubInstall({ channel: "beta", apiVersion: "0.1.9" });
    const result = await UpdateCheckService.checkForUpdate();
    expect(result?.updateAvailable).toBe(false);
  });

  it("does not offer a DOWNGRADE when the API lags the install", async () => {
    stubInstall({ channel: "beta", apiVersion: "0.1.2" });
    const result = await UpdateCheckService.checkForUpdate();
    expect(result?.updateAvailable).toBe(false);
  });

  it("returns null when the API version is missing", async () => {
    stubInstall({ channel: "beta", apiVersion: undefined });
    mockFetch.mockImplementation((url: string) => {
      if (url.endsWith("build_info.json"))
        return jsonResponse({ commit: "abc1234" });
      if (url.endsWith("channel.json"))
        return jsonResponse({ channel: "beta" });
      return jsonResponse({ commit: "serversha" }); // no version field
    });
    await expect(UpdateCheckService.checkForUpdate()).resolves.toBeNull();
  });
});

describe("getOwnChannel", () => {
  it("memoizes the channel read", async () => {
    stubInstall({ channel: "beta" });
    await UpdateCheckService.getOwnChannel();
    await UpdateCheckService.getOwnChannel();
    const channelFetches = mockFetch.mock.calls.filter(([url]) =>
      String(url).endsWith("channel.json"),
    );
    expect(channelFetches).toHaveLength(1);
  });

  it("falls back to alpha on unknown values", async () => {
    stubInstall({ channel: "stable" });
    await expect(UpdateCheckService.getOwnChannel()).resolves.toBe("alpha");
  });
});

describe("compareVersions", () => {
  it("orders numerically per segment", () => {
    expect(compareVersions("0.10.0", "0.9.9")).toBeGreaterThan(0);
    expect(compareVersions("1.0.0", "1.0.0")).toBe(0);
    expect(compareVersions("0.1.9", "0.2.0")).toBeLessThan(0);
  });

  it("treats missing segments as zero", () => {
    expect(compareVersions("1.0", "1.0.0")).toBe(0);
  });
});
```

g) Keep the eligibility + memoization describes as they are (they only use `build_info.json`-prefixed stubbing — update their `stubOwnBuild(...)` calls to `stubInstall({ commit: ... })`).

- [ ] **Step 2: Run to verify failure**

Run: `bazel test //tabula/extension:unit_tests --test_arg=updateCheck --test_output=all`
Expected: FAIL — `compareVersions`/`resetChannelCacheForTests`/`fetchDeployedInfo` missing; result shape mismatches.

- [ ] **Step 3: Implement** — in `tabula/extension/src/services/updateCheck.ts`:

a) Add after the `BuildInfo` interface:

```ts
/** Release channel of this install (channel.json, written by tabcli). */
export type Channel = "alpha" | "beta";

/**
 * Numeric-segment version compare (missing segments are zero). Mirrors
 * compareSemver in tabula/cli/src/utils/extension.ts — duplicated
 * deliberately: the CLI must not depend on extension code.
 */
export function compareVersions(a: string, b: string): number {
  const as = a.split(".").map((s) => parseInt(s, 10) || 0);
  const bs = b.split(".").map((s) => parseInt(s, 10) || 0);
  const len = Math.max(as.length, bs.length);
  for (let i = 0; i < len; i += 1) {
    const diff = (as[i] ?? 0) - (bs[i] ?? 0);
    if (diff !== 0) return diff;
  }
  return 0;
}
```

b) Replace `UpdateCheckResult` with the channel-aware shape:

```ts
export interface UpdateCheckResult {
  channel: Channel;
  updateAvailable: boolean;
  /** Own commit (alpha) or own version (beta). */
  current: string;
  /** Deployed commit (alpha) or deployed version (beta). */
  latest: string;
}
```

c) Add a channel cache next to the build-info cache:

```ts
// Same lifetime rule as the build-info read: the running context's channel
// is immutable even though tabcli may swap channel.json before the reload.
let channelPromise: Promise<Channel> | undefined;

export function resetChannelCacheForTests(): void {
  channelPromise = undefined;
}
```

d) Add to the class:

```ts
  /** This install's channel (channel.json); absent/unknown → alpha. */
  static async getOwnChannel(): Promise<Channel> {
    if (channelPromise !== undefined) return channelPromise;
    channelPromise = (async () => {
      try {
        const res = await fetch(chrome.runtime.getURL("channel.json"));
        if (!res.ok) return "alpha";
        const body = (await res.json()) as { channel?: string };
        return body.channel === "beta" ? "beta" : "alpha";
      } catch {
        return "alpha";
      }
    })();
    return channelPromise;
  }
```

e) Rename `fetchDeployedCommit` → `fetchDeployedInfo` returning both fields (same guards; version is optional):

```ts
  /** The deployed dev API's identity, from its GET / provenance endpoint. */
  static async fetchDeployedInfo(): Promise<{
    commit: string;
    version: string | null;
  } | null> {
    const apiUrl = process.env.API_URL;
    if (!apiUrl) return null;
    try {
      const origin = new URL(apiUrl).origin;
      // banner must never trust a cached provenance; hung polls shouldn't stall
      const res = await fetch(`${origin}/`, {
        cache: "no-store",
        signal: AbortSignal.timeout(10_000),
      });
      if (!res.ok) return null;
      const body = (await res.json()) as { commit?: string; version?: string };
      if (!body.commit || body.commit === "unknown") return null;
      return { commit: body.commit, version: body.version ?? null };
    } catch {
      return null;
    }
  }
```

f) Replace `checkForUpdate` with the channel-aware version:

```ts
  /** null = ineligible or no reliable answer (failures stay silent). */
  static async checkForUpdate(): Promise<UpdateCheckResult | null> {
    const { eligible, ownCommit } = await this.isEligible();
    if (!eligible || !ownCommit) return null;
    const deployed = await this.fetchDeployedInfo();
    if (!deployed) return null;

    const channel = await this.getOwnChannel();
    if (channel === "beta") {
      // Beta tracks release cuts: lockstep versioning makes the API's
      // version the latest cut. Strictly-newer only — never a downgrade.
      if (!deployed.version) return null;
      const own = chrome.runtime.getManifest().version;
      return {
        channel,
        updateAvailable: compareVersions(deployed.version, own) > 0,
        current: own,
        latest: deployed.version,
      };
    }
    return {
      channel,
      updateAvailable: deployed.commit !== ownCommit,
      current: ownCommit,
      latest: deployed.commit,
    };
  }
```

g) Update the file's top doc comment first paragraph to mention channels (alpha = commit vs main head; beta = version vs latest cut).

- [ ] **Step 4: Run to verify pass**

Run: `bazel test //tabula/extension:unit_tests --test_arg=updateCheck --test_output=all`
Expected: PASS — all channel-aware tests green.

- [ ] **Step 5: Commit**

```bash
npx --no-install prettier --write tabula/extension/src/services/updateCheck.ts tabula/extension/src/services/updateCheck.test.ts
git add tabula/extension/src/services/updateCheck.ts tabula/extension/src/services/updateCheck.test.ts
git commit -m "feat(tabula): channel-aware update check (alpha: commit, beta: version)"
```

---

### Task 5: channel-aware banner

**Files:**

- Modify: `tabula/extension/src/components/UpdateBanner.tsx`
- Modify: `tabula/extension/src/components/UpdateBanner.test.tsx`

- [ ] **Step 1: Update the tests** — in `UpdateBanner.test.tsx`, the mocked `checkForUpdate` now resolves the new shape. Update the existing tests' mock values:
  - "renders nothing when no update is available": `{ channel: "alpha", updateAvailable: false, current: "a", latest: "a" }`
  - "shows the deployed short-sha and reloads on click": `{ channel: "alpha", updateAvailable: true, current: "oldsha12", latest: "newsha9876" }` (assertions unchanged — short sha + `tabcli ext update` text).
  - "dismiss hides the banner …": same new shape as above.
  - "keeps the banner when a later poll fails (null)": first resolve `{ channel: "alpha", updateAvailable: true, current: "oldsha12", latest: "newsha9876" }`, then null.

  And append one new test:

```tsx
it("phrases the beta channel offer as a release version", async () => {
  checkForUpdate.mockResolvedValue({
    channel: "beta",
    updateAvailable: true,
    current: "0.1.9",
    latest: "0.2.0",
  });
  render(<UpdateBanner />);
  expect(await screen.findByRole("status")).toHaveTextContent(
    "New release v0.2.0 available",
  );
  expect(screen.getByRole("status")).toHaveTextContent("tabcli ext update");
});
```

- [ ] **Step 2: Run to verify failure**

Run: `bazel test //tabula/extension:unit_tests --test_arg=UpdateBanner --test_output=all`
Expected: FAIL — component still reads `result.deployedCommit`.

- [ ] **Step 3: Implement** — replace the component body of `UpdateBanner.tsx` (keep header + doc comment, updating the comment's wording to "offered update (commit or version, per channel)"):

```tsx
import React, { useEffect, useState } from "react";
import { UpdateCheckService } from "../services/updateCheck";
import type { UpdateCheckResult } from "../services/updateCheck";

const POLL_INTERVAL_MS = 15 * 60 * 1000;

export const UpdateBanner: React.FC = () => {
  const [offer, setOffer] = useState<UpdateCheckResult | null>(null);
  const [dismissedLatest, setDismissedLatest] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    const check = async () => {
      const result = await UpdateCheckService.checkForUpdate();
      if (cancelled) return;
      // null = ineligible or no reliable answer — keep the current banner
      // state rather than flickering it off on a transient failure.
      if (result === null) return;
      setOffer(result.updateAvailable ? result : null);
    };
    check();
    const id = setInterval(check, POLL_INTERVAL_MS);
    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, []);

  if (!offer || offer.latest === dismissedLatest) return null;

  return (
    <div className="update-banner" role="status">
      <span>
        {offer.channel === "beta"
          ? `New release v${offer.latest} available`
          : `New build deployed (${offer.latest.slice(0, 7)})`}{" "}
        — run <code>tabcli ext update</code>, then reload.
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
        onClick={() => setDismissedLatest(offer.latest)}
      >
        Dismiss
      </button>
    </div>
  );
};
```

- [ ] **Step 4: Run to verify pass**

Run: `bazel test //tabula/extension:unit_tests --test_arg=UpdateBanner --test_output=all`
Expected: PASS — 6 tests.

- [ ] **Step 5: Commit**

```bash
npx --no-install prettier --write tabula/extension/src/components/UpdateBanner.tsx tabula/extension/src/components/UpdateBanner.test.tsx
git add tabula/extension/src/components/UpdateBanner.tsx tabula/extension/src/components/UpdateBanner.test.tsx
git commit -m "feat(tabula): per-channel update banner copy"
```

---

### Task 6: Settings Developer section + footer identity

**Files:**

- Modify: `tabula/extension/src/services/updateCheck.ts` (one method)
- Modify: `tabula/extension/src/services/updateCheck.test.ts`
- Modify: `tabula/extension/src/components/AccountSettings.tsx`
- Modify: `tabula/extension/src/components/AccountSettings.test.tsx`
- Modify: `tabula/extension/src/dashboard/Dashboard.tsx`

- [ ] **Step 1: Failing service test** — append to the service test file:

```ts
describe("getDisplayIdentity", () => {
  it("returns channel + commit + version for an eligible install", async () => {
    stubInstall({ channel: "beta", commit: "abc1234" });
    await expect(UpdateCheckService.getDisplayIdentity()).resolves.toEqual({
      channel: "beta",
      commit: "abc1234",
      version: "0.1.9", // from the mocked manifest
    });
  });

  it("returns null when ineligible (local/dev or Web Store install)", async () => {
    stubInstall({ commit: "dev" });
    await expect(UpdateCheckService.getDisplayIdentity()).resolves.toBeNull();
  });
});
```

Run: `bazel test //tabula/extension:unit_tests --test_arg=updateCheck --test_output=all` — expected FAIL (method missing).

- [ ] **Step 2: Implement `getDisplayIdentity`** — add to the class in `updateCheck.ts`:

```ts
  /**
   * Identity for display surfaces (Settings, dashboard footer). Null unless
   * this is an eligible dev install of a CI-built bundle — Web Store users
   * and local ad-hoc builds never see channel/commit chrome.
   */
  static async getDisplayIdentity(): Promise<{
    channel: Channel;
    commit: string;
    version: string;
  } | null> {
    const { eligible, ownCommit } = await this.isEligible();
    if (!eligible || !ownCommit) return null;
    return {
      channel: await this.getOwnChannel(),
      commit: ownCommit,
      version: chrome.runtime.getManifest().version,
    };
  }
```

Run the focused test again — expected PASS. Commit checkpoint:

```bash
npx --no-install prettier --write tabula/extension/src/services/updateCheck.ts tabula/extension/src/services/updateCheck.test.ts
git add tabula/extension/src/services/updateCheck.ts tabula/extension/src/services/updateCheck.test.ts
git commit -m "feat(tabula): getDisplayIdentity for settings/footer surfaces"
```

- [ ] **Step 3: Failing AccountSettings tests** — in `AccountSettings.test.tsx`:

a) Add a module mock near the other `jest.mock(...)` calls at the top, defaulting to "not a dev install" so every existing test keeps its current behavior:

```ts
jest.mock("../services/updateCheck", () => ({
  UpdateCheckService: {
    getDisplayIdentity: jest.fn().mockResolvedValue(null),
  },
}));
```

b) Append a new describe (import `UpdateCheckService` from `../services/updateCheck` at the top; reuse the file's existing render helpers/props pattern — read how existing tests render `<AccountSettings …>` and do the same):

```tsx
describe("Developer section (release channel)", () => {
  const identity = { channel: "alpha", commit: "abc1234def", version: "0.1.9" };
  const getDisplayIdentity = UpdateCheckService.getDisplayIdentity as jest.Mock;

  it("is hidden when the install is not an eligible dev install", async () => {
    getDisplayIdentity.mockResolvedValue(null);
    renderAccountSettings(); // the file's existing helper/pattern
    await act(async () => {
      await Promise.resolve();
    });
    expect(screen.queryByText("Developer")).not.toBeInTheDocument();
  });

  it("shows channel, version and sha for an eligible install", async () => {
    getDisplayIdentity.mockResolvedValue(identity);
    renderAccountSettings();
    expect(await screen.findByText("Developer")).toBeInTheDocument();
    expect(screen.getByText(/alpha · v0\.1\.9 · abc1234/)).toBeInTheDocument();
  });

  it("reveals the switch command for a different channel, with Copy", async () => {
    getDisplayIdentity.mockResolvedValue(identity);
    const writeText = jest.fn().mockResolvedValue(undefined);
    Object.assign(navigator, { clipboard: { writeText } });
    renderAccountSettings();
    await screen.findByText("Developer");

    fireEvent.click(screen.getByRole("button", { name: "beta" }));
    expect(
      screen.getByText("tabcli ext update --channel beta"),
    ).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: /copy/i }));
    expect(writeText).toHaveBeenCalledWith("tabcli ext update --channel beta");
  });

  it("explains stable instead of offering a command", async () => {
    getDisplayIdentity.mockResolvedValue(identity);
    renderAccountSettings();
    await screen.findByText("Developer");

    fireEvent.click(screen.getByRole("button", { name: "stable" }));
    expect(screen.getByText(/Web Store listing \(M3\)/)).toBeInTheDocument();
    expect(screen.queryByText(/--channel stable/)).not.toBeInTheDocument();
  });
});
```

(Adapt `renderAccountSettings()` to the file's actual render pattern — if it renders inline with props, write a tiny local helper in the new describe. The four behaviors asserted are the contract.)

Run: `bazel test //tabula/extension:unit_tests --test_arg=AccountSettings --test_output=all` — expected: the NEW tests fail (section missing), existing ones still pass (mock default null).

- [ ] **Step 4: Implement the Developer section** — in `AccountSettings.tsx`:

a) Add the import:

```ts
import { UpdateCheckService } from "../services/updateCheck";
import type { Channel } from "../services/updateCheck";
```

b) Add state + load effect near the other `useState` calls at the component top:

```tsx
const [devIdentity, setDevIdentity] = useState<{
  channel: Channel;
  commit: string;
  version: string;
} | null>(null);
const [selectedChannel, setSelectedChannel] = useState<string | null>(null);
const [copiedCommand, setCopiedCommand] = useState(false);

useEffect(() => {
  let cancelled = false;
  UpdateCheckService.getDisplayIdentity().then((identity) => {
    if (!cancelled) setDevIdentity(identity);
  });
  return () => {
    cancelled = true;
  };
}, []);
```

c) Insert the Developer section inside `renderPreferencesContent()`, after the Appearance `</section>` and before the closing `</div>`:

```tsx
{
  devIdentity && (
    <section style={{ marginTop: variant === "popup" ? "16px" : "24px" }}>
      <h3
        style={{
          fontSize: variant === "popup" ? "12px" : "14px",
          fontWeight: "600",
          marginBottom: variant === "popup" ? "12px" : "16px",
          color: "var(--color-text-secondary)",
        }}
      >
        Developer
      </h3>

      <div
        style={{
          padding: variant === "popup" ? "10px" : "12px",
          border: "1px solid var(--color-border)",
          borderRadius: "8px",
        }}
      >
        <div
          style={{
            display: "flex",
            alignItems: "center",
            justifyContent: "space-between",
            gap: "12px",
          }}
        >
          <div style={{ minWidth: 0 }}>
            <div
              style={{
                fontWeight: "500",
                fontSize: variant === "popup" ? "13px" : "14px",
                marginBottom: "2px",
              }}
            >
              Release channel
            </div>
            <div
              style={{
                fontSize: "11px",
                color: "var(--color-text-secondary)",
              }}
            >
              {devIdentity.channel} · v{devIdentity.version} ·{" "}
              {devIdentity.commit.slice(0, 7)}
            </div>
          </div>

          <div
            style={{
              display: "flex",
              gap: "4px",
              backgroundColor: "var(--color-bg-secondary)",
              padding: "3px",
              borderRadius: "6px",
              flexShrink: 0,
            }}
          >
            {(["alpha", "beta", "stable"] as const).map((ch) => (
              <button
                key={ch}
                onClick={() => {
                  setSelectedChannel(ch);
                  setCopiedCommand(false);
                }}
                style={{
                  padding: "4px 10px",
                  fontSize: "12px",
                  border: "none",
                  borderRadius: "4px",
                  cursor: "pointer",
                  backgroundColor:
                    (selectedChannel ?? devIdentity.channel) === ch
                      ? "var(--color-bg-primary)"
                      : "transparent",
                  color: "var(--color-text-primary)",
                }}
              >
                {ch}
              </button>
            ))}
          </div>
        </div>

        {selectedChannel === "stable" && (
          <div
            style={{
              marginTop: "10px",
              fontSize: "12px",
              color: "var(--color-text-secondary)",
            }}
          >
            The stable channel arrives with the Web Store listing (M3).
          </div>
        )}

        {selectedChannel &&
          selectedChannel !== "stable" &&
          selectedChannel !== devIdentity.channel && (
            <div
              style={{
                marginTop: "10px",
                display: "flex",
                alignItems: "center",
                gap: "8px",
              }}
            >
              <code
                style={{
                  flex: 1,
                  fontSize: "12px",
                  padding: "6px 8px",
                  backgroundColor: "var(--color-bg-secondary)",
                  borderRadius: "4px",
                  overflowX: "auto",
                  whiteSpace: "nowrap",
                }}
              >
                tabcli ext update --channel {selectedChannel}
              </code>
              <button
                type="button"
                onClick={() => {
                  navigator.clipboard
                    ?.writeText(
                      `tabcli ext update --channel ${selectedChannel}`,
                    )
                    .then(() => setCopiedCommand(true))
                    .catch(() => {});
                }}
                style={{
                  padding: "4px 10px",
                  fontSize: "12px",
                  border: "1px solid var(--color-border)",
                  borderRadius: "4px",
                  cursor: "pointer",
                  backgroundColor: "transparent",
                  color: "var(--color-text-primary)",
                  flexShrink: 0,
                }}
              >
                {copiedCommand ? "Copied!" : "Copy"}
              </button>
            </div>
          )}
      </div>
    </section>
  );
}
```

Run: `bazel test //tabula/extension:unit_tests --test_arg=AccountSettings --test_output=all` — expected PASS (new + existing).

- [ ] **Step 5: Footer identity** — in `Dashboard.tsx`:

a) Add the import next to the UpdateBanner import: `import { UpdateCheckService } from "../services/updateCheck";`

b) Near the other dashboard `useState`s add:

```tsx
const [buildIdentity, setBuildIdentity] = useState<{
  channel: string;
  commit: string;
} | null>(null);

useEffect(() => {
  let cancelled = false;
  UpdateCheckService.getDisplayIdentity().then((identity) => {
    if (!cancelled && identity) {
      setBuildIdentity({ channel: identity.channel, commit: identity.commit });
    }
  });
  return () => {
    cancelled = true;
  };
}, []);
```

c) Change the footer span content (currently `v{chrome?.runtime?.getManifest?.()?.version || "dev"}`) to:

```tsx
            v{chrome?.runtime?.getManifest?.()?.version || "dev"}
            {buildIdentity
              ? ` · ${buildIdentity.channel} · ${buildIdentity.commit.slice(0, 7)}`
              : ""}
```

- [ ] **Step 6: Full extension suite + bundle**

Run: `bazel test //tabula/extension:unit_tests --test_summary=terse && bazel build //tabula/extension:dist //tabula/extension:tests_lib`
Expected: all PASS, builds green.

- [ ] **Step 7: Commit**

```bash
npx --no-install prettier --write tabula/extension/src/components/AccountSettings.tsx tabula/extension/src/components/AccountSettings.test.tsx tabula/extension/src/dashboard/Dashboard.tsx
git add tabula/extension/src/components/AccountSettings.tsx tabula/extension/src/components/AccountSettings.test.tsx tabula/extension/src/dashboard/Dashboard.tsx
git commit -m "feat(tabula): settings Developer section + footer channel identity"
```

---

### Task 7: docs + full verification

**Files:**

- Modify: `tabula/extension/docs/DEV_UPDATES.md`
- Modify: `tabula/cli/README.md`

- [ ] **Step 1: DEV_UPDATES.md** — after the "## Updating" section, insert:

```markdown
## Channels

The install carries its channel (`channel.json`, written by tabcli); a bare
`tabcli ext update` stays on it.

| Channel | Tracks                                         | Switch                              |
| ------- | ---------------------------------------------- | ----------------------------------- |
| alpha   | every `main` commit (rolling dev-latest)       | `tabcli ext update --channel alpha` |
| beta    | the latest release cut (`tabula-extension-v*`) | `tabcli ext update --channel beta`  |
| stable  | the Web Store listing — **arrives with M3**    | —                                   |

The update banner is channel-aware: alpha offers new commits, beta offers new
release versions (never downgrades). Settings → Preferences → Developer shows
the current channel/build and the exact switch command.
```

- [ ] **Step 2: cli README** — in the `ext` section added in M1, document `--channel` on `ext update` (alpha | beta | stable-with-M3-note; default = installed channel, else alpha), following the section's existing formatting.

- [ ] **Step 3: Full verification sweep** — all must pass:

```bash
bazel test //tabula/cli:unit_tests //tabula/extension:unit_tests --test_summary=terse
bazel build //tabula/extension:dist //tabula/extension:chrome_zip //tabula/cli/... //tabula/extension:tests_lib
bazel run //:tidy && git status --porcelain -- ':!MODULE.bazel.lock'   # MUST leave the tree clean (CI gates on this — M1 lesson)
npx --no-install prettier --check $(git diff --name-only origin/main -- '*.ts' '*.tsx' '*.js' '*.md' | tr '\n' ' ')
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/tabula-release.yml')); print('YAML OK')"
git status --short   # only intended files
```

- [ ] **Step 4: Commit**

```bash
git add tabula/extension/docs/DEV_UPDATES.md tabula/cli/README.md
git commit -m "docs(tabula): channel how-to + tabcli --channel reference"
```

(The controller pushes and opens the PR after the final integration review.)

---

## Self-review notes

- **Spec coverage:** channel model + signals (T4), self-describing install + precedence + stable error (T1/T2), release stamping (T3), banner copy + dismiss-on-offered-value (T5), Developer section + footer (T6), docs (T7), error handling (stable/no-release/corrupt-channel/missing-version spread across T1/T2/T4), no-Playwright honored.
- **Type consistency:** `InstallChannel` (cli) vs `Channel` (extension) — intentional twins, both cross-referenced like `BundleInfo`/`BuildInfo`; `UpdateCheckResult {channel, updateAvailable, current, latest}` used identically in T4 (service), T5 (banner); `getDisplayIdentity` shape matches T6's consumers; `resolveLatestExtensionTag` returns the full tag consumed by T2's download.
- **Known judgment calls:** beta "downgrade" guarded (strictly-newer only); deployed-commit `"unknown"` still nulls both channels (consistent contract); AccountSettings tests get a default-null service mock so 30+ existing tests stay untouched; the verification sweep now includes `bazel run //:tidy` (the M1 CI lesson).
