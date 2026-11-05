/**
 * Copyright (c) 2026 VitruvianSoftware
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

/* global console, process, setInterval */

// Backend for the worktree-band panel. Antigravity starts this file with Node.js
// (see sidecar.json) and keeps it running while the plugin is enabled.

import { execFile } from "node:child_process";
import { createHash } from "node:crypto";
import {
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  renameSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { homedir, userInfo } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import { Response, SidecarApp } from "sidecar_sdk";

import {
  countChecks,
  fmtSize,
  isRemovable,
  judgeCleanup,
  summariseWorktrees,
  totalCacheKb,
} from "./lib/core.mjs";
import { parseOpenUILang, toOpenUILang } from "./lib/openui.mjs";

const execFileAsync = promisify(execFile);
const HERE = dirname(fileURLToPath(import.meta.url));
const DATA_DIR =
  process.env.ANTIGRAVITY_EXECUTABLE_DATA_DIR || join(HERE, ".data");
const INBOX_DIR = join(
  process.env.ANTIGRAVITY_APP_DATA_DIR ||
    join(homedir(), ".gemini", "antigravity"),
  "worktree-band-inbox",
);
const STATE_FILE = join(DATA_DIR, "worktrees.json");

const app = new SidecarApp();

const readLocal = (name) => readFileSync(join(HERE, name), "utf8");

function readVersion() {
  try {
    return String(
      JSON.parse(readFileSync(join(HERE, "..", "..", "plugin.json"), "utf8"))
        .version ?? "",
    );
  } catch {
    return "";
  }
}
const VERSION = readVersion();

const fail = (message, status = 400) =>
  new Response(JSON.stringify({ error: message }), {
    contentType: "application/json",
    status,
  });

function loadStore() {
  if (existsSync(STATE_FILE)) {
    try {
      const parsed = JSON.parse(readFileSync(STATE_FILE, "utf8"));
      if (parsed && typeof parsed === "object") {
        return {
          worktrees: parsed.worktrees ?? {},
          settings: {
            mode: parsed.settings?.mode ?? "ask",
            bazelUserRoot: parsed.settings?.bazelUserRoot ?? "",
          },
        };
      }
    } catch (err) {
      console.error(
        `worktree-band: could not read ${STATE_FILE}: ${err.message}`,
      );
    }
  }
  return {
    worktrees: {},
    settings: { mode: "ask", bazelUserRoot: "" },
  };
}

let stateStore = loadStore();

function saveStore() {
  mkdirSync(dirname(STATE_FILE), { recursive: true });
  const tmp = `${STATE_FILE}.tmp`;
  writeFileSync(tmp, JSON.stringify(stateStore, null, 2), "utf8");
  renameSync(tmp, STATE_FILE);
}

async function runCmd(cmd, args, cwd, timeout = 20_000) {
  try {
    const { stdout, stderr } = await execFileAsync(cmd, args, {
      cwd,
      timeout,
      maxBuffer: 4 * 1024 * 1024,
    });
    return { ok: true, out: String(stdout).trim(), err: String(stderr).trim() };
  } catch (err) {
    return {
      ok: false,
      out: String(err.stdout ?? "").trim(),
      err: String(err.stderr ?? err.message ?? "").trim(),
    };
  }
}

function getSharedBazelRoots(configured) {
  const home = homedir();
  const user = process.env.USER || userInfo().username || "";
  if (configured) {
    return [configured.replace(/^~(?=\/)/, home).replace(/\/+$/, "")];
  }
  return [
    `${home}/Library/Caches/bazel/_bazel_${user}`,
    `${home}/.cache/bazel/_bazel_${user}`,
  ];
}

function findBazelCaches(root, configured) {
  const home = homedir();
  const shared = getSharedBazelRoots(configured);
  const found = [];

  try {
    const rc = readFileSync(join(root, "user.bazelrc"), "utf8");
    const pinned = /--output_user_root=(\S+)/
      .exec(rc)?.[1]
      ?.replace(/^~(?=\/)/, home)
      .replace(/\$\{?HOME\}?/, home)
      .replace(/\/+$/, "");
    if (pinned && isRemovable(pinned, home, shared) && existsSync(pinned)) {
      found.push(pinned);
    }
  } catch {
    // No user.bazelrc
  }

  const hash = createHash("md5").update(root).digest("hex");
  for (const base of shared.map((r) => `${r}/${hash}`)) {
    try {
      const owner = readFileSync(
        join(base, "DO_NOT_BUILD_HERE"),
        "utf8",
      ).trim();
      if (
        owner === root &&
        isRemovable(base, home, shared) &&
        !found.includes(base)
      ) {
        found.push(base);
      }
    } catch {
      continue;
    }
  }
  return found;
}

async function duKb(path) {
  const r = await runCmd("du", ["-sk", path], undefined, 60_000);
  const kb = Number.parseInt(r.out.split(/\s+/)[0] ?? "", 10);
  return Number.isFinite(kb) ? kb : null;
}

async function inspectWorktree(dir, prev = null, withSizes = false) {
  const where = await runCmd("git", [
    "-C",
    dir,
    "rev-parse",
    "--path-format=absolute",
    "--show-toplevel",
    "--git-common-dir",
    "HEAD",
  ]);
  const [root, common, head] = where.out.split("\n");
  if (!where.ok || !root || !common || !head) return null;

  const branchRes = await runCmd("git", [
    "-C",
    root,
    "symbolic-ref",
    "--short",
    "-q",
    "HEAD",
  ]);
  const branch = branchRes.out;
  if (!branch) return null;

  const remoteHead = await runCmd("git", [
    "-C",
    root,
    "symbolic-ref",
    "--short",
    "-q",
    "refs/remotes/origin/HEAD",
  ]);
  const defaultBranch = remoteHead.out.replace(/^origin\//, "") || "main";
  const mainRoot = dirname(common.replace(/\/+$/, ""));
  const place = {
    root,
    mainRoot,
    isLinked: root !== mainRoot,
    branch,
    head,
    defaultBranch,
  };

  let pr = null;
  const prRes = await runCmd(
    "gh",
    [
      "pr",
      "view",
      branch,
      "--json",
      "number,state,url,baseRefName,headRefOid,isDraft,statusCheckRollup",
    ],
    root,
  );
  if (prRes.ok) {
    try {
      const j = JSON.parse(prRes.out);
      pr = {
        number: j.number,
        state: j.state,
        url: j.url,
        base: j.baseRefName,
        head: j.headRefOid,
        isDraft: Boolean(j.isDraft),
        checks: countChecks(j.statusCheckRollup ?? []),
      };
    } catch {
      pr = null;
    }
  }

  const statusRes = await runCmd("git", ["-C", root, "status", "--porcelain"]);
  const verdict = judgeCleanup(place, pr, statusRes, stateStore.settings.mode);

  let treeKb = prev?.treeKb ?? null;
  let caches = prev?.caches ?? [];
  let sizedAt = prev?.sizedAt ?? 0;

  if (withSizes || !prev || Date.now() - sizedAt > 10 * 60_000) {
    treeKb = await duKb(root);
    const cachePaths = findBazelCaches(root, stateStore.settings.bazelUserRoot);
    caches = [];
    for (const p of cachePaths) {
      caches.push({ path: p, kb: await duKb(p) });
    }
    sizedAt = Date.now();
  }

  return {
    ...place,
    pr: pr ?? prev?.pr ?? null,
    treeKb,
    caches,
    sizedAt,
    updatedAt: Date.now(),
    conversationId: prev?.conversationId ?? "",
    ...verdict,
  };
}

function drainInbox() {
  if (!existsSync(INBOX_DIR)) return [];
  const discovered = [];
  for (const name of readdirSync(INBOX_DIR)) {
    if (!name.endsWith(".json")) continue;
    const file = join(INBOX_DIR, name);
    try {
      const payload = JSON.parse(readFileSync(file, "utf8"));
      const convId = String(payload.conversationId ?? "");
      const paths = Array.isArray(payload.workspacePaths)
        ? payload.workspacePaths
        : payload.cwd
          ? [payload.cwd]
          : [];
      for (const p of paths) {
        if (typeof p === "string" && p) {
          discovered.push({ path: p, conversationId: convId });
        }
      }
    } catch {
      // Ignore malformed note
    } finally {
      try {
        unlinkSync(file);
      } catch {
        // Already removed
      }
    }
  }
  return discovered;
}

async function refreshAll(withSizes = false) {
  const notes = drainInbox();
  for (const n of notes) {
    const info = await inspectWorktree(
      n.path,
      stateStore.worktrees[n.path],
      true,
    );
    if (info && info.isLinked) {
      stateStore.worktrees[info.root] = {
        ...info,
        conversationId: n.conversationId || info.conversationId,
      };
    }
  }

  for (const [root, cur] of Object.entries(stateStore.worktrees)) {
    if (cur.cleanup === "done") continue;
    const updated = await inspectWorktree(root, cur, withSizes);
    if (updated) {
      stateStore.worktrees[root] = updated;
    }
  }
  saveStore();
}

function buildState() {
  const list = Object.values(stateStore.worktrees);
  const summary = summariseWorktrees(list);
  return {
    version: VERSION,
    worktrees: summary.items,
    summary,
    settings: stateStore.settings,
  };
}

app.page("/", () => readLocal("index.html"));
app.page("/app.js", () => readLocal("app.js"));
app.api(
  "/styles.css",
  () => new Response(readLocal("styles.css"), { contentType: "text/css" }),
  "GET",
);
app.api(
  "/openui.mjs",
  () =>
    new Response(readLocal(join("lib", "openui.mjs")), {
      contentType: "text/javascript",
    }),
  "GET",
);

app.api(
  "/api/state",
  () => {
    const state = buildState();
    return { ...state, openuiDsl: toOpenUILang(state) };
  },
  "GET",
);

app.api(
  "/api/openui",
  () => {
    const dsl = toOpenUILang(buildState());
    return { dsl, parsed: parseOpenUILang(dsl) };
  },
  "GET",
);

app.api("/api/refresh", async (data) => {
  await refreshAll(Boolean(data?.withSizes));
  const state = buildState();
  return { ...state, openuiDsl: toOpenUILang(state) };
});

app.api("/api/track", async (data) => {
  let targetPath = String(data?.path ?? "").trim();
  if (!targetPath && data?.workspaceUri) {
    try {
      targetPath = fileURLToPath(String(data.workspaceUri));
    } catch {
      return fail("Could not resolve workspace URI");
    }
  }
  if (!targetPath) return fail("Provide a worktree path to track");
  const resolved = resolve(targetPath.replace(/^~(?=\/)/, homedir()));
  const info = await inspectWorktree(
    resolved,
    stateStore.worktrees[resolved],
    true,
  );
  if (!info) {
    return fail("That folder is not a git worktree on a branch");
  }
  info.conversationId = String(
    data?.conversationId ?? info.conversationId ?? "",
  );
  stateStore.worktrees[info.root] = info;
  saveStore();
  return { worktree: info };
});

app.api("/api/cleanup", async (data) => {
  const root = String(data?.root ?? "").trim();
  const cur = stateStore.worktrees[root];
  if (!cur) return fail("That worktree is not tracked", 404);

  const fresh = await inspectWorktree(root, cur, false);
  if (!fresh) return fail("Worktree could not be read", 400);
  if (fresh.cleanup !== "ready") {
    stateStore.worktrees[root] = {
      ...fresh,
      cleanup: fresh.cleanup === "none" ? "blocked" : fresh.cleanup,
      note: fresh.note || "the pull request is not merged",
    };
    saveStore();
    return fail(stateStore.worktrees[root].note, 400);
  }

  const home = homedir();
  const shared = getSharedBazelRoots(stateStore.settings.bazelUserRoot);
  const paths = findBazelCaches(
    fresh.root,
    stateStore.settings.bazelUserRoot,
  ).filter((p) => isRemovable(p, home, shared));

  let freedKb = 0;
  const failed = [];
  if (paths.length > 0) {
    await runCmd("bazel", ["shutdown"], fresh.root, 60_000);
    for (const p of paths) {
      const kb = cur.caches?.find((c) => c.path === p)?.kb ?? 0;
      await runCmd("chmod", ["-R", "u+w", p], undefined, 120_000);
      const rm = await runCmd("rm", ["-rf", p], undefined, 120_000);
      if (rm.ok && !existsSync(p)) freedKb += kb;
      else failed.push(p);
    }
  }

  const removed = await runCmd(
    "git",
    ["-C", fresh.mainRoot, "worktree", "remove", fresh.root],
    undefined,
    120_000,
  );
  if (removed.ok) freedKb += cur.treeKb ?? 0;
  const isDone = removed.ok && failed.length === 0;
  const note = isDone
    ? `freed ${fmtSize(freedKb)}; start next session in ${fresh.mainRoot}`
    : [
        removed.ok
          ? ""
          : `git worktree remove: ${removed.err.split("\n")[0] ?? "failed"}`,
        failed.length ? `could not remove ${failed.join(", ")}` : "",
      ]
        .filter(Boolean)
        .join("; ");

  stateStore.worktrees[root] = {
    ...fresh,
    cleanup: isDone ? "done" : "failed",
    note,
  };
  saveStore();
  return { worktree: stateStore.worktrees[root], freedKb };
});

setInterval(() => {
  void refreshAll(false);
}, 60_000);
void refreshAll(true);
app.run();
