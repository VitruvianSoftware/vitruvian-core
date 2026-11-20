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

// Minimal stdio MCP server (JSON-RPC 2.0) for vitruvian-orchestrator.
// Exposes `progress` (called by the lead session) and `step` (called by worker
// subagents) and appends contract events to:
//   ~/.gemini/antigravity/vitruvian-orchestrator/flows/<root_conversation_id>.jsonl
//
// Antigravity passes `_meta` on MCP tools/call requests with:
//   - _meta["antigravity.google/root_conversation_id"]: lead conversation UUID
//   - _meta["antigravity.google/conversation_id"]: calling session's own UUID
//     (for a subagent, its worker conversation ID; for the root session, same
//     as root_conversation_id)
//   - _meta["antigravity.google/parent_conversation_id"]: parent UUID when in a subagent
//   - _meta["antigravity.google/agent_name"]: subagent type name (e.g. "wren")
//   - _meta["antigravity.google/artifacts_dir"]: conversation brain directory

import { spawnSync } from "node:child_process";
import fs, {
  appendFileSync,
  closeSync,
  existsSync,
  fstatSync,
  lstatSync,
  mkdirSync,
  openSync,
  readdirSync,
  readFileSync,
  realpathSync,
  statSync,
} from "node:fs";
import { homedir } from "node:os";
import {
  basename,
  dirname,
  isAbsolute,
  join,
  relative,
  resolve,
  sep,
} from "node:path";
import { fileURLToPath } from "node:url";

import {
  agentRoleMap,
  applyAgentModels,
  board as boardView,
  channels as channelsView,
  checkBoardChannel,
  initialFlow,
  isValidWorktree,
  MAX_AGENT_FILE_BYTES,
  MAX_TEAM_FILE_BYTES,
  parseTeam,
  planTeamSync,
  reduce,
  remaining,
  renderStarterTeam,
  resolveTeam,
  starterAgentFile,
  TEAM_AGENT_DIRS,
  VALID_PHASES,
  VALID_TIERS,
  validateChannelAction,
  validatePostChannel,
  validateStarterAgents,
  validateTeamEvent,
} from "../sidecars/panel/lib/orchestrator-core.mjs";
import { TIER_DEFAULTS } from "../sidecars/panel/lib/tier-defaults.mjs";

export const SERVER_INFO = Object.freeze({
  name: "vitruvian-orchestrator",
  version: "0.2.0",
});

export const TOOLS = Object.freeze([
  Object.freeze({
    name: "progress",
    description:
      "Called by the lead orchestrator to report the task plan, phase transitions, task accept/return review verdicts, and flow completion.",
    inputSchema: {
      type: "object",
      properties: {
        title: {
          type: "string",
          description: "Title of the orchestrated flow.",
        },
        phase: {
          type: "string",
          enum: ["plan", "design", "delegate", "review", "close"],
          description: "Current orchestration phase.",
        },
        tasks: {
          type: "array",
          description: "Planned tasks in 1-based order.",
          items: {
            type: "object",
            properties: {
              title: { type: "string" },
              specialist: { type: "string" },
              tier: {
                type: "string",
                enum: [...VALID_TIERS],
              },
              after: {
                type: "array",
                items: { type: "integer" },
              },
              model: {
                type: "string",
                description:
                  "Optional Gemini model override for this task (e.g. gemini-4-carbon-high).",
              },
              worktree: {
                type: "string",
                description:
                  "Optional git worktree branch name for isolating parallel edits.",
              },
            },
            required: ["title", "specialist", "tier"],
          },
        },
        accept: {
          type: "integer",
          description: "1-based task number accepted after review.",
        },
        return: {
          type: "integer",
          description: "1-based task number returned for another pass.",
        },
        retire: {
          type: "string",
          description: "Run id or specialist agent name to retire.",
        },
        kill: {
          type: "string",
          description: "Run id or specialist agent name to kill.",
        },
        finished: {
          type: "boolean",
          description: "Set true to close the flow.",
        },
      },
    },
  }),
  Object.freeze({
    name: "step",
    description:
      "Called by a worker subagent about itself to report step progress (done, total, optional note) or pause status (paused: 'quota' | 'error').",
    inputSchema: {
      type: "object",
      properties: {
        done: {
          type: "integer",
          description: "Number of steps completed so far.",
        },
        total: {
          type: "integer",
          description: "Total steps planned for this worker task.",
        },
        note: {
          type: "string",
          description: "Optional short status note for the current step.",
        },
        delegate: {
          type: "string",
          description:
            "Optional delegated model identifier (e.g. gemini-4-carbon-high).",
        },
        delegateUsage: {
          type: "object",
          description: "Optional delegated token usage totals.",
          properties: {
            input: { type: "integer" },
            output: { type: "integer" },
            thinking: { type: "integer" },
            cacheRead: { type: "integer" },
          },
        },
        paused: {
          type: "string",
          enum: ["quota", "error"],
          description:
            "Optional pause reason when blocked ('quota' or 'error').",
        },
        detail: {
          type: "string",
          description: "Optional detail explaining why the member paused.",
        },
        worktree: {
          type: "string",
          description:
            "Optional git worktree branch name created or used by this helper.",
        },
      },
    },
  }),
  Object.freeze({
    name: "post",
    description:
      "Called by the lead or any specialist subagent to post a message to the shared Orchestrator board (results, defect lists, questions, or notes). Supports @name, @all, and @lead mentions.",
    inputSchema: {
      type: "object",
      properties: {
        text: {
          type: "string",
          description: "Post body text (capped at 4000 characters).",
        },
        to: {
          type: "array",
          items: { type: "string" },
          description: "Optional explicit recipient agent names.",
        },
        kind: {
          type: "string",
          enum: ["note", "question", "defect", "result"],
          description: "Post kind: note, question, defect, or result.",
        },
        replyTo: {
          type: "integer",
          minimum: 1,
          description: "Optional seq number of the post being replied to.",
        },
        channel: {
          type: "string",
          description:
            "Optional channel handle (default 'main'; must match [a-z0-9][a-z0-9-]{0,31}).",
        },
      },
      required: ["text"],
    },
  }),
  Object.freeze({
    name: "board",
    description:
      "Read posts from the shared Orchestrator board with optional recipient, author, kind, channel, substring, and limit filters.",
    inputSchema: {
      type: "object",
      properties: {
        to: {
          type: "string",
          description:
            "Optional recipient handle filter (e.g. 'wren', or 'me' for posts mentioning the caller; includes @all broadcasts).",
        },
        from: {
          type: "string",
          description: "Optional author handle filter.",
        },
        kind: {
          type: "string",
          enum: ["note", "question", "defect", "result"],
          description: "Optional post kind filter.",
        },
        channel: {
          type: "string",
          description: "Optional channel handle filter (e.g. 'main').",
        },
        search: {
          type: "string",
          description: "Optional case-insensitive substring filter.",
        },
        limit: {
          type: "integer",
          minimum: 1,
          maximum: 100,
          description:
            "Maximum newest matching posts to return (default 20, max 100).",
        },
      },
    },
  }),
  Object.freeze({
    name: "channel",
    description:
      "Create, archive, or list shared Orchestrator board channels ('create' and 'archive' are lead-only; 'list' is open to all).",
    inputSchema: {
      type: "object",
      properties: {
        action: {
          type: "string",
          enum: ["create", "archive", "list"],
          description: "Channel action: create, archive, or list.",
        },
        name: {
          type: "string",
          description:
            "Channel handle ([a-z0-9][a-z0-9-]{0,31]) for create or archive.",
        },
      },
      required: ["action"],
    },
  }),
  Object.freeze({
    name: "team",
    description:
      "Read and resolve the repository's optional .agents/team.json role-to-agent mapping, engines (always native on Antigravity with Antigravity tier defaults), model overrides, and project notes (read-only).",
    inputSchema: {
      type: "object",
      properties: {
        root: {
          type: "string",
          description:
            "Optional absolute path to the repository root directory containing .agents/team.json.",
        },
      },
      additionalProperties: false,
    },
    annotations: {
      readOnlyHint: true,
    },
  }),
  Object.freeze({
    name: "team_setup",
    description:
      "Initialize a starter .agents/team.json (and optional team-<role> starter agents) or sync explicit team.json harness model settings into repository agent files.",
    inputSchema: {
      type: "object",
      properties: {
        action: {
          type: "string",
          enum: ["init", "sync"],
          description: "Setup action: init or sync.",
        },
        root: {
          type: "string",
          description:
            "Optional absolute path to the repository root directory.",
        },
        agents: {
          type: "array",
          items: { type: "string" },
          description:
            "Optional non-lead role names to copy as editable team-<role> starter agents during init.",
        },
        check: {
          type: "boolean",
          description:
            "When true, check and report changes without writing any files.",
        },
      },
      required: ["action"],
      additionalProperties: false,
    },
  }),
]);

function workspaceValueToPath(val) {
  if (typeof val !== "string") return "";
  const trimmed = val.trim();
  if (!trimmed) return "";
  if (trimmed.startsWith("file://")) {
    try {
      return fileURLToPath(trimmed);
    } catch {
      return "";
    }
  }
  return trimmed;
}

function extractWorkspaceFromMeta(meta) {
  if (!meta || typeof meta !== "object") return "";
  const candidates = [
    meta["antigravity.google/cwd"],
    meta["antigravity.google/workspace_root"],
    meta["antigravity.google/workspace_uri"],
    Array.isArray(meta["antigravity.google/workspace_uris"])
      ? meta["antigravity.google/workspace_uris"][0]
      : "",
    meta.cwd,
    meta.workspace_root,
    meta.workspaceRoot,
    meta.workspaceUri,
    meta.workspace_uri,
    Array.isArray(meta.workspacePaths) ? meta.workspacePaths[0] : "",
  ];
  for (const cand of candidates) {
    const p = workspaceValueToPath(cand);
    if (p) return p;
  }
  return "";
}

function extractWorkspaceFromTranscript(transcriptText) {
  if (!transcriptText || typeof transcriptText !== "string") return "";
  const activeWsMatch = /Active Workspaces:\s*\r?\n\s*-\s*([^\r\n]+)/.exec(
    transcriptText,
  );
  if (activeWsMatch?.[1]) {
    const p = workspaceValueToPath(activeWsMatch[1]);
    if (p) return p;
  }
  const cwdMatch = /Command Working Directory:\s*([^\r\n]+)/.exec(
    transcriptText,
  );
  if (cwdMatch?.[1]) {
    const p = workspaceValueToPath(cwdMatch[1]);
    if (p) return p;
  }
  const lines = transcriptText.split("\n");
  for (let i = lines.length - 1; i >= 0; i -= 1) {
    const line = lines[i].trim();
    if (!line) continue;
    try {
      const parsed = JSON.parse(line);
      if (parsed && typeof parsed === "object") {
        const ws = extractWorkspaceFromMeta(parsed);
        if (ws) return ws;
        if (typeof parsed.content === "string") {
          const innerActive =
            /Active Workspaces:\s*\r?\n\s*-\s*([^\r\n]+)/.exec(parsed.content);
          if (innerActive?.[1]) {
            const p = workspaceValueToPath(innerActive[1]);
            if (p) return p;
          }
          const innerCwd = /Command Working Directory:\s*([^\r\n]+)/.exec(
            parsed.content,
          );
          if (innerCwd?.[1]) {
            const p = workspaceValueToPath(innerCwd[1]);
            if (p) return p;
          }
        }
      }
    } catch {
      // Ignore malformed line.
    }
  }
  return "";
}

function extractWorkspaceFromFlowFile(filePath) {
  if (!filePath || !existsSync(filePath)) return "";
  try {
    const lines = readFileSync(filePath, "utf8").split("\n");
    for (let i = lines.length - 1; i >= 0; i -= 1) {
      const line = lines[i].trim();
      if (!line) continue;
      try {
        const ev = JSON.parse(line);
        if (!ev || typeof ev !== "object") continue;
        const fromMeta = extractWorkspaceFromMeta(ev._meta);
        if (fromMeta) return fromMeta;
        const fromEv = extractWorkspaceFromMeta(ev);
        if (fromEv) return fromEv;
      } catch {
        // Ignore malformed event line.
      }
    }
  } catch {
    // Ignore unreadable flow file.
  }
  return "";
}

/**
 * Resolves the active workspace path using `_meta` first, explicit overrides,
 * the conversation's persisted flow/transcript state, environment hints, and
 * `process.cwd()` last.
 *
 * @param {Record<string, any>} [meta]
 * @param {{ cwd?: string, workspaceUri?: string, flowsDir?: string, brainRoots?: string[] }} [options]
 * @returns {string}
 */
export function resolveWorkspaceRoot(meta = {}, options = {}) {
  const fromMeta = extractWorkspaceFromMeta(meta);
  if (fromMeta) return fromMeta;

  const fromOptCwd = workspaceValueToPath(options.cwd);
  if (fromOptCwd) return fromOptCwd;

  const fromOptUri = workspaceValueToPath(options.workspaceUri);
  if (fromOptUri) return fromOptUri;

  const { rootConversationId, callerConversationId, parentConversationId } =
    extractConversationMeta(meta, options.brainRoots);
  if (rootConversationId && rootConversationId !== "default") {
    const flowsDir = options.flowsDir || defaultFlowsDir();
    const fromFlow = extractWorkspaceFromFlowFile(
      join(flowsDir, `${rootConversationId}.jsonl`),
    );
    if (fromFlow) return fromFlow;
  }

  const roots = resolveServerBrainRoots({
    brainRoots: options.brainRoots,
    meta,
  });
  for (const cid of [
    callerConversationId,
    rootConversationId,
    parentConversationId,
  ]) {
    if (!cid || cid === "default") continue;
    const transcript = readServerTranscript(cid, roots);
    const fromTranscript = extractWorkspaceFromTranscript(transcript);
    if (fromTranscript) return fromTranscript;
  }

  const fromEnv =
    workspaceValueToPath(process.env.ANTIGRAVITY_WORKSPACE_ROOT) ||
    workspaceValueToPath(process.env.ANTIGRAVITY_CWD);
  if (fromEnv) return fromEnv;

  return process.cwd();
}

function isPathInsideRealRoot(realRoot, realTarget) {
  const rel = relative(realRoot, realTarget);
  return (
    rel.length > 0 &&
    rel !== ".." &&
    !rel.startsWith(`..${sep}`) &&
    !rel.startsWith("../") &&
    !rel.startsWith("..\\") &&
    !isAbsolute(rel)
  );
}

const DEFAULT_PLUGIN_AGENTS_DIR = resolve(
  dirname(fileURLToPath(import.meta.url)),
  "..",
  "agents",
);

function inspectRepoPath(root, realRoot, segments) {
  let cur = root;
  const components = [];
  for (let i = 0; i < segments.length; i += 1) {
    cur = join(cur, segments[i]);
    const isLast = i === segments.length - 1;
    let lst;
    try {
      lst = fs.lstatSync(cur);
    } catch (err) {
      const code = err && typeof err === "object" ? err.code : undefined;
      if (code === "ENOENT") {
        return { status: "absent", existingComponents: components };
      }
      if (code === "ENOTDIR") {
        const parentLabel =
          i > 0 ? segments.slice(0, i).join("/") : segments[0];
        return {
          status: "error",
          reason: "parent-not-directory",
          error: `ENOTDIR: ${parentLabel} is not a directory`,
        };
      }
      const msg = err instanceof Error ? err.message : String(err);
      return { status: "error", reason: "stat-error", error: msg };
    }

    if (lst.isSymbolicLink()) {
      return {
        status: "symlink",
        reason: "symlink",
        error: `${segments.slice(0, i + 1).join("/")} is a symlink`,
      };
    }

    let realCur;
    try {
      realCur = fs.realpathSync(cur);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      return { status: "error", reason: "realpath-error", error: msg };
    }
    if (!isPathInsideRealRoot(realRoot, realCur)) {
      return {
        status: "outside-root",
        reason: "outside-root",
        error: `${segments.slice(0, i + 1).join("/")} resolves outside root`,
      };
    }

    components.push({
      path: cur,
      segment: segments[i],
      relPath: segments.slice(0, i + 1).join("/"),
      dev: lst.dev,
      ino: lst.ino,
      realPath: realCur,
    });

    if (!isLast) {
      if (!lst.isDirectory()) {
        return {
          status: "error",
          reason: "parent-not-directory",
          error: `${segments.slice(0, i + 1).join("/")} is not a directory`,
        };
      }
    } else {
      if (!lst.isFile()) {
        return {
          status: "not-a-file",
          reason: "not-a-file",
          error: `${segments.join("/")} is not a regular file`,
        };
      }
      if (lst.nlink > 1) {
        return {
          status: "hardlink",
          reason: "hardlink",
          error: `${segments.join("/")} is a hardlink`,
        };
      }
      return {
        status: "file",
        path: cur,
        realPath: realCur,
        size: lst.size,
        dev: lst.dev,
        ino: lst.ino,
        components,
      };
    }
  }
  return { status: "error", reason: "invalid-path", error: "empty path" };
}

function readBoundedFileNoFollow(filePath, maxBytes, label) {
  const noFollow = fs.constants?.O_NOFOLLOW ?? 0;
  let fd;
  try {
    fd = fs.openSync(filePath, fs.constants.O_RDONLY | noFollow);
  } catch (err) {
    const code = err && typeof err === "object" ? err.code : undefined;
    if (code === "ELOOP") {
      return { ok: false, reason: "symlink", error: `${label} is a symlink` };
    }
    const msg = err instanceof Error ? err.message : String(err);
    return {
      ok: false,
      reason: "read-error",
      error: `failed to read ${label}: ${msg}`,
    };
  }

  try {
    const st = fs.fstatSync(fd);
    if (!st.isFile()) {
      return {
        ok: false,
        reason: "not-a-file",
        error: `${label} is not a regular file`,
      };
    }
    if (st.nlink > 1) {
      return {
        ok: false,
        reason: "hardlink",
        error: `${label} is a hardlink`,
      };
    }
    if (st.size > maxBytes) {
      return {
        ok: false,
        reason: "too-large",
        error: `${label} exceeds maximum size of ${maxBytes} bytes`,
      };
    }
    const chunks = [];
    let totalBytes = 0;
    const buf = Buffer.allocUnsafe(8192);
    while (true) {
      const n = fs.readSync(fd, buf, 0, buf.length, null);
      if (n === 0) break;
      totalBytes += n;
      if (totalBytes > maxBytes) {
        return {
          ok: false,
          reason: "too-large",
          error: `${label} exceeds maximum size of ${maxBytes} bytes`,
        };
      }
      chunks.push(Buffer.from(buf.subarray(0, n)));
    }
    return {
      ok: true,
      text: Buffer.concat(chunks, totalBytes).toString("utf8"),
    };
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    return {
      ok: false,
      reason: "read-error",
      error: `failed to read ${label}: ${msg}`,
    };
  } finally {
    try {
      fs.closeSync(fd);
    } catch {
      // Ignore close error.
    }
  }
}

function verifyRootUnchanged(root, realRoot, rootSnap, realRootSnap) {
  try {
    const curRootLst = fs.lstatSync(root);
    if (curRootLst.dev !== rootSnap.dev || curRootLst.ino !== rootSnap.ino) {
      return false;
    }
    const curRealRoot = fs.realpathSync(root);
    if (curRealRoot !== realRoot) {
      return false;
    }
    const curRealRootLst = fs.lstatSync(realRoot);
    return (
      curRealRootLst.isDirectory() &&
      curRealRootLst.dev === realRootSnap.dev &&
      curRealRootLst.ino === realRootSnap.ino
    );
  } catch {
    return false;
  }
}

function recordInitDirSnapshot(expectedDirs, segments, existingComponents) {
  for (let i = 0; i < segments.length - 1; i += 1) {
    const relDir = segments.slice(0, i + 1).join("/");
    if (i < existingComponents.length) {
      const comp = existingComponents[i];
      const prev = expectedDirs.get(relDir);
      if (prev === null) {
        return {
          ok: false,
          error: `${relDir} changed before write (changed-during-sync)`,
        };
      }
      if (
        prev &&
        (prev.dev !== comp.dev ||
          prev.ino !== comp.ino ||
          prev.realPath !== comp.realPath)
      ) {
        return {
          ok: false,
          error: `${relDir} changed before write (changed-during-sync)`,
        };
      }
      if (!prev) {
        expectedDirs.set(relDir, {
          dev: comp.dev,
          ino: comp.ino,
          realPath: comp.realPath,
        });
      }
    } else {
      if (expectedDirs.has(relDir) && expectedDirs.get(relDir) !== null) {
        return {
          ok: false,
          error: `${relDir} changed before write (changed-during-sync)`,
        };
      }
      expectedDirs.set(relDir, null);
    }
  }
  return { ok: true };
}

function ensureDirInsideRootChecked(
  root,
  realRoot,
  rootSnap,
  realRootSnap,
  dirSegments,
  expectedDirs,
) {
  if (!verifyRootUnchanged(root, realRoot, rootSnap, realRootSnap)) {
    throw new Error("root changed before write (changed-during-sync)");
  }
  let cur = root;
  for (let i = 0; i < dirSegments.length; i += 1) {
    cur = join(cur, dirSegments[i]);
    const relDir = dirSegments.slice(0, i + 1).join("/");
    const expected = expectedDirs.get(relDir);
    let lst;
    try {
      lst = fs.lstatSync(cur);
    } catch (err) {
      const code = err && typeof err === "object" ? err.code : undefined;
      if (code === "ENOENT") {
        if (expected !== null && expected !== undefined) {
          throw new Error(
            `${relDir} disappeared before write (changed-during-sync)`,
          );
        }
        fs.mkdirSync(cur);
        lst = fs.lstatSync(cur);
        if (lst.isSymbolicLink()) {
          throw new Error(`${relDir} is a symlink (changed-during-sync)`);
        }
        if (!lst.isDirectory()) {
          throw new Error(`${relDir} is not a directory (changed-during-sync)`);
        }
        const createdRealCur = fs.realpathSync(cur);
        if (!isPathInsideRealRoot(realRoot, createdRealCur)) {
          throw new Error(
            `${relDir} resolves outside root (changed-during-sync)`,
          );
        }
        expectedDirs.set(relDir, {
          dev: lst.dev,
          ino: lst.ino,
          realPath: createdRealCur,
        });
        continue;
      }
      throw err;
    }
    if (lst.isSymbolicLink()) {
      throw new Error(`${relDir} is a symlink (changed-during-sync)`);
    }
    if (!lst.isDirectory()) {
      throw new Error(`${relDir} is not a directory (changed-during-sync)`);
    }
    const realCur = fs.realpathSync(cur);
    if (!isPathInsideRealRoot(realRoot, realCur)) {
      throw new Error(`${relDir} resolves outside root (changed-during-sync)`);
    }
    if (expected === null) {
      throw new Error(`${relDir} appeared before write (changed-during-sync)`);
    }
    if (
      expected &&
      (lst.dev !== expected.dev ||
        lst.ino !== expected.ino ||
        realCur !== expected.realPath)
    ) {
      throw new Error(`${relDir} changed before write (changed-during-sync)`);
    }
  }
}

function verifyCreatedFileUnchanged(
  root,
  realRoot,
  rootSnap,
  realRootSnap,
  expectedDirs,
  item,
) {
  if (!verifyRootUnchanged(root, realRoot, rootSnap, realRootSnap)) {
    return false;
  }
  let cur = root;
  for (let i = 0; i < item.segments.length - 1; i += 1) {
    cur = join(cur, item.segments[i]);
    const relDir = item.segments.slice(0, i + 1).join("/");
    const expected = expectedDirs.get(relDir);
    if (!expected) {
      return false;
    }
    try {
      const lst = fs.lstatSync(cur);
      if (
        lst.isSymbolicLink() ||
        !lst.isDirectory() ||
        lst.dev !== expected.dev ||
        lst.ino !== expected.ino
      ) {
        return false;
      }
      const realCur = fs.realpathSync(cur);
      if (
        realCur !== expected.realPath ||
        !isPathInsideRealRoot(realRoot, realCur)
      ) {
        return false;
      }
    } catch {
      return false;
    }
  }
  try {
    const fileLst = fs.lstatSync(item.path);
    if (
      fileLst.isSymbolicLink() ||
      !fileLst.isFile() ||
      fileLst.dev !== item.dev ||
      fileLst.ino !== item.ino
    ) {
      return false;
    }
    const realFile = fs.realpathSync(item.path);
    return isPathInsideRealRoot(realRoot, realFile);
  } catch {
    return false;
  }
}

function writeNewFileNoFollow(
  root,
  realRoot,
  rootSnap,
  realRootSnap,
  segments,
  text,
  expectedDirs,
  beforeWriteHook = null,
) {
  if (beforeWriteHook) {
    beforeWriteHook({
      action: "init",
      path: segments.join("/"),
      segments: [...segments],
      root,
      realRoot,
    });
  }
  ensureDirInsideRootChecked(
    root,
    realRoot,
    rootSnap,
    realRootSnap,
    segments.slice(0, -1),
    expectedDirs,
  );
  const targetPath = join(root, ...segments);
  let preLst = null;
  try {
    preLst = fs.lstatSync(targetPath);
  } catch (err) {
    if (!err || typeof err !== "object" || err.code !== "ENOENT") {
      throw err;
    }
  }
  if (preLst !== null) {
    const why =
      preLst.nlink > 1
        ? "is a hardlink"
        : preLst.isSymbolicLink()
          ? "is a symlink"
          : "appeared before write";
    throw new Error(`${segments.join("/")} ${why} (changed-during-sync)`);
  }
  const noFollow = fs.constants?.O_NOFOLLOW ?? 0;
  const fd = fs.openSync(
    targetPath,
    fs.constants.O_WRONLY |
      fs.constants.O_CREAT |
      fs.constants.O_EXCL |
      noFollow,
    0o644,
  );
  let completed = false;
  let fdStat = null;
  try {
    fdStat = fs.fstatSync(fd);
    if (!fdStat.isFile() || fdStat.nlink !== 1) {
      throw new Error(
        `${segments.join("/")} changed before write (changed-during-sync)`,
      );
    }
    const buf = Buffer.from(text, "utf8");
    let written = 0;
    while (written < buf.length) {
      written += fs.writeSync(fd, buf, written, buf.length - written);
    }
    completed = true;
    return {
      path: targetPath,
      segments: [...segments],
      dev: fdStat.dev,
      ino: fdStat.ino,
    };
  } finally {
    fs.closeSync(fd);
    if (!completed) {
      const canUnlink =
        fdStat &&
        verifyCreatedFileUnchanged(
          root,
          realRoot,
          rootSnap,
          realRootSnap,
          expectedDirs,
          {
            path: targetPath,
            segments: [...segments],
            dev: fdStat.dev,
            ino: fdStat.ino,
          },
        );
      if (canUnlink) {
        try {
          fs.unlinkSync(targetPath);
        } catch {
          // Best-effort cleanup of partial new file.
        }
      }
    }
  }
}

function verifySyncTargetUnchanged(root, realRoot, rootSnap, realRootSnap, op) {
  if (!verifyRootUnchanged(root, realRoot, rootSnap, realRootSnap)) {
    return { ok: false, reason: "changed-during-sync" };
  }
  let cur = root;
  for (let i = 0; i < op.segments.length; i += 1) {
    cur = join(cur, op.segments[i]);
    const isLast = i === op.segments.length - 1;
    const expected = op.components[i];
    if (!expected) {
      return { ok: false, reason: "changed-during-sync" };
    }
    let lst;
    try {
      lst = fs.lstatSync(cur);
    } catch {
      return { ok: false, reason: "changed-during-sync" };
    }
    if (lst.isSymbolicLink()) {
      return { ok: false, reason: "changed-during-sync" };
    }
    if (lst.dev !== expected.dev || lst.ino !== expected.ino) {
      return { ok: false, reason: "changed-during-sync" };
    }
    let realCur;
    try {
      realCur = fs.realpathSync(cur);
    } catch {
      return { ok: false, reason: "changed-during-sync" };
    }
    if (
      realCur !== expected.realPath ||
      !isPathInsideRealRoot(realRoot, realCur)
    ) {
      return { ok: false, reason: "changed-during-sync" };
    }
    if (!isLast) {
      if (!lst.isDirectory()) {
        return { ok: false, reason: "changed-during-sync" };
      }
    } else {
      if (!lst.isFile()) {
        return { ok: false, reason: "changed-during-sync" };
      }
      if (lst.nlink > 1) {
        return { ok: false, reason: "hardlink" };
      }
    }
  }
  return { ok: true };
}

function overwriteFileNoFollow(filePath, text, expectedFileStat = null) {
  const noFollow = fs.constants?.O_NOFOLLOW ?? 0;
  let fd;
  try {
    fd = fs.openSync(filePath, fs.constants.O_WRONLY | noFollow);
  } catch (err) {
    const code = err && typeof err === "object" ? err.code : undefined;
    if (code === "ENOENT" || code === "ELOOP" || code === "ENOTDIR") {
      return { ok: false, reason: "changed-during-sync" };
    }
    throw err;
  }
  try {
    const st = fs.fstatSync(fd);
    if (!st.isFile()) {
      return { ok: false, reason: "changed-during-sync" };
    }
    if (st.nlink > 1) {
      return { ok: false, reason: "hardlink" };
    }
    if (
      expectedFileStat &&
      (st.dev !== expectedFileStat.dev || st.ino !== expectedFileStat.ino)
    ) {
      return { ok: false, reason: "changed-during-sync" };
    }
    fs.ftruncateSync(fd, 0);
    const buf = Buffer.from(text, "utf8");
    let written = 0;
    while (written < buf.length) {
      written += fs.writeSync(fd, buf, written, buf.length - written, written);
    }
    return { ok: true };
  } finally {
    fs.closeSync(fd);
  }
}

/**
 * Executes `team_setup` (`init` or `sync`) for Antigravity, enforcing explicit
 * `root`, symlink and hardlink refusal, realpath containment, and TOCTOU rechecks.
 *
 * @param {Record<string, any>} args
 * @param {{ meta?: Record<string, any>, cwd?: string, workspaceUri?: string, flowsDir?: string, brainRoots?: string[], pluginAgentsDir?: string, _beforeWrite?: (ctx: Record<string, any>) => void }} [options]
 */
export function runTeamSetup(args = {}, options = {}) {
  const inp = args && typeof args === "object" ? args : {};
  const action = typeof inp.action === "string" ? inp.action.trim() : "";
  if (action !== "init" && action !== "sync") {
    return { ok: false, error: 'action must be "init" or "sync"' };
  }
  if (inp.check !== undefined && typeof inp.check !== "boolean") {
    return { ok: false, error: "check must be a boolean" };
  }
  const check = inp.check === true;
  const beforeWriteHook =
    typeof options._beforeWrite === "function" ? options._beforeWrite : null;

  const hasRoot =
    Object.prototype.hasOwnProperty.call(inp, "root") && inp.root !== undefined;
  const rawRoot = hasRoot
    ? inp.root
    : resolveRepoRoot(resolveWorkspaceRoot(options.meta ?? {}, options));
  const rootCheck = validateExplicitRoot(rawRoot);
  if (!rootCheck.ok) {
    return { ok: false, error: rootCheck.error };
  }
  const root = rootCheck.root.replace(/\/+$/, "") || "/";
  let realRoot;
  let rootSnap;
  let realRootSnap;
  try {
    rootSnap = fs.lstatSync(root);
    realRoot = fs.realpathSync(root);
    realRootSnap = fs.lstatSync(realRoot);
  } catch {
    return { ok: false, error: INVALID_ROOT_ERROR };
  }

  if (action === "init") {
    const starterCheck = validateStarterAgents(inp.agents);
    if (!starterCheck.ok) {
      return { ok: false, error: starterCheck.error };
    }
    const starterRoles = starterCheck.roles;

    const expectedDirs = new Map();
    const teamInspect = inspectRepoPath(root, realRoot, [
      ".agents",
      "team.json",
    ]);
    if (teamInspect.status !== "absent") {
      return {
        ok: false,
        error:
          teamInspect.status === "file"
            ? ".agents/team.json already exists"
            : teamInspect.error || ".agents/team.json cannot be created",
      };
    }
    const teamSnap = recordInitDirSnapshot(
      expectedDirs,
      [".agents", "team.json"],
      teamInspect.existingComponents,
    );
    if (!teamSnap.ok) {
      return { ok: false, error: teamSnap.error };
    }

    const callingHarness = "antigravity";
    const pluginAgentsDir =
      options.pluginAgentsDir || DEFAULT_PLUGIN_AGENTS_DIR;
    const agentDirs = TEAM_AGENT_DIRS[callingHarness];
    /** @type {Array<{ segments: string[], relPath: string, text: string, role: string, agent: string }>} */
    const plannedAgents = [];

    for (const role of starterRoles) {
      const agentName = `team-${role}`;
      const segments = [...agentDirs, `${agentName}.md`];
      const relPath = segments.join("/");
      const targetInspect = inspectRepoPath(root, realRoot, segments);
      if (targetInspect.status !== "absent") {
        return {
          ok: false,
          error:
            targetInspect.status === "file"
              ? `${relPath} already exists`
              : targetInspect.error || `${relPath} cannot be created`,
        };
      }
      const targetSnap = recordInitDirSnapshot(
        expectedDirs,
        segments,
        targetInspect.existingComponents,
      );
      if (!targetSnap.ok) {
        return { ok: false, error: targetSnap.error };
      }
      const templatePath = join(pluginAgentsDir, `${role}.md`);
      let templateText;
      try {
        const st = fs.statSync(templatePath);
        if (!st.isFile() || st.size > MAX_AGENT_FILE_BYTES) {
          return {
            ok: false,
            error: `plugin starter template agents/${role}.md is invalid`,
          };
        }
        templateText = fs.readFileSync(templatePath, "utf8");
        if (Buffer.byteLength(templateText, "utf8") > MAX_AGENT_FILE_BYTES) {
          return {
            ok: false,
            error: `plugin starter template agents/${role}.md is invalid`,
          };
        }
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        return {
          ok: false,
          error: `failed to read plugin template agents/${role}.md: ${msg}`,
        };
      }
      plannedAgents.push({
        segments,
        relPath,
        text: starterAgentFile(templateText, role),
        role,
        agent: agentName,
      });
    }

    const teamText = renderStarterTeam(starterRoles);
    if (!check) {
      const createdFiles = [];
      try {
        for (const item of plannedAgents) {
          createdFiles.push(
            writeNewFileNoFollow(
              root,
              realRoot,
              rootSnap,
              realRootSnap,
              item.segments,
              item.text,
              expectedDirs,
              beforeWriteHook,
            ),
          );
        }
        createdFiles.push(
          writeNewFileNoFollow(
            root,
            realRoot,
            rootSnap,
            realRootSnap,
            [".agents", "team.json"],
            teamText,
            expectedDirs,
            beforeWriteHook,
          ),
        );
      } catch (err) {
        const cleanupErrors = [];
        for (let i = createdFiles.length - 1; i >= 0; i -= 1) {
          const created = createdFiles[i];
          if (!created) continue;
          if (
            !verifyCreatedFileUnchanged(
              root,
              realRoot,
              rootSnap,
              realRootSnap,
              expectedDirs,
              created,
            )
          ) {
            cleanupErrors.push(`${created.path}: path changed before rollback`);
            continue;
          }
          try {
            fs.unlinkSync(created.path);
          } catch (rmErr) {
            const rmMsg =
              rmErr instanceof Error ? rmErr.message : String(rmErr);
            cleanupErrors.push(`${created.path}: ${rmMsg}`);
          }
        }
        const rollbackNote =
          cleanupErrors.length > 0
            ? `; rollback errors: ${cleanupErrors.join("; ")}`
            : "";
        const msg = err instanceof Error ? err.message : String(err);
        return {
          ok: false,
          error: `failed to write starter files: ${msg}${rollbackNote}`,
        };
      }
    }

    const files = [
      ...plannedAgents.map((item) => ({
        path: item.relPath,
        harness: callingHarness,
        role: item.role,
        agent: item.agent,
        status: "created",
        reason: null,
      })),
      { path: ".agents/team.json", status: "created", reason: null },
    ];
    return {
      ok: true,
      result: { action: "init", root, check, files },
    };
  }

  // action === "sync"
  const teamInspect = inspectRepoPath(root, realRoot, [".agents", "team.json"]);
  if (teamInspect.status === "absent") {
    return { ok: false, error: ".agents/team.json does not exist" };
  }
  if (teamInspect.status !== "file") {
    return {
      ok: false,
      error: teamInspect.error || ".agents/team.json cannot be read",
    };
  }
  if (teamInspect.size > MAX_TEAM_FILE_BYTES) {
    return {
      ok: false,
      error: `.agents/team.json exceeds maximum size of ${MAX_TEAM_FILE_BYTES} bytes (64 KiB)`,
    };
  }
  const teamRead = readBoundedFileNoFollow(
    teamInspect.realPath,
    MAX_TEAM_FILE_BYTES,
    ".agents/team.json",
  );
  if (!teamRead.ok) {
    return { ok: false, error: teamRead.error };
  }
  const parsed = parseTeam(teamRead.text);
  if (parsed.errors.length > 0 || !parsed.team) {
    const firstErr = parsed.errors[0];
    return {
      ok: false,
      error:
        parsed.errors.length === 1 &&
        typeof firstErr === "string" &&
        firstErr.startsWith("invalid JSON:")
          ? firstErr
          : `invalid .agents/team.json: ${parsed.errors.join("; ")}`,
    };
  }

  const targets = planTeamSync(parsed.team);
  const files = [];
  const plannedWrites = [];

  for (const target of targets) {
    const inspected = inspectRepoPath(root, realRoot, target.segments);
    if (inspected.status === "error") {
      return { ok: false, error: inspected.error };
    }
    if (inspected.status === "absent") {
      continue;
    }
    if (inspected.status !== "file") {
      files.push({
        path: target.path,
        harness: target.harness,
        role: target.role,
        agent: target.agent,
        status: "skipped",
        reason: inspected.reason,
      });
      continue;
    }
    if (target.conflict) {
      files.push({
        path: target.path,
        harness: target.harness,
        role: target.role,
        agent: target.agent,
        status: "skipped",
        reason: target.reason,
      });
      continue;
    }
    if (inspected.size > MAX_AGENT_FILE_BYTES) {
      files.push({
        path: target.path,
        harness: target.harness,
        role: target.role,
        agent: target.agent,
        status: "skipped",
        reason: "too-large",
      });
      continue;
    }

    const fileRead = readBoundedFileNoFollow(
      inspected.realPath,
      MAX_AGENT_FILE_BYTES,
      target.path,
    );
    if (!fileRead.ok) {
      files.push({
        path: target.path,
        harness: target.harness,
        role: target.role,
        agent: target.agent,
        status: "skipped",
        reason: fileRead.reason,
      });
      continue;
    }

    const applied = applyAgentModels(fileRead.text, target.harness, {
      model: target.model,
      effort: target.effort,
    });
    if (applied.reason !== null) {
      files.push({
        path: target.path,
        harness: target.harness,
        role: target.role,
        agent: target.agent,
        status: "skipped",
        reason: applied.reason,
      });
      continue;
    }
    if (applied.changed) {
      const fileIndex = files.length;
      plannedWrites.push({
        path: inspected.path,
        realPath: inspected.realPath,
        relPath: target.path,
        segments: target.segments,
        components: inspected.components,
        fileStat: { dev: inspected.dev, ino: inspected.ino },
        fileIndex,
        text: applied.text,
      });
      files.push({
        path: target.path,
        harness: target.harness,
        role: target.role,
        agent: target.agent,
        status: "changed",
        reason: null,
      });
    } else {
      files.push({
        path: target.path,
        harness: target.harness,
        role: target.role,
        agent: target.agent,
        status: "unchanged",
        reason: null,
      });
    }
  }

  if (!check) {
    for (const op of plannedWrites) {
      if (beforeWriteHook) {
        beforeWriteHook({
          action: "sync",
          path: op.relPath,
          segments: [...op.segments],
          root,
          realRoot,
        });
      }
      const verified = verifySyncTargetUnchanged(
        root,
        realRoot,
        rootSnap,
        realRootSnap,
        op,
      );
      if (!verified.ok) {
        files[op.fileIndex] = {
          ...files[op.fileIndex],
          status: "skipped",
          reason: verified.reason,
        };
        continue;
      }
      try {
        const writeRes = overwriteFileNoFollow(op.path, op.text, op.fileStat);
        if (!writeRes.ok) {
          files[op.fileIndex] = {
            ...files[op.fileIndex],
            status: "skipped",
            reason: writeRes.reason,
          };
          continue;
        }
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        return {
          ok: false,
          error: `failed to write ${op.relPath}: ${msg}`,
        };
      }
    }
  }

  return {
    ok: true,
    result: { action: "sync", root, check, files },
  };
}

function resolveRealTeamPath(root) {
  let realRoot;
  try {
    realRoot = realpathSync(root);
  } catch {
    realRoot = resolve(root);
  }
  const agentsDir = join(root, ".agents");
  const teamPath = join(agentsDir, "team.json");

  let linkStat;
  try {
    linkStat = lstatSync(teamPath);
  } catch (err) {
    const code = err && typeof err === "object" ? err.code : undefined;
    if (code === "ENOENT" || code === "ENOTDIR") {
      try {
        const dirStat = lstatSync(agentsDir);
        if (dirStat.isSymbolicLink()) {
          try {
            realpathSync(agentsDir);
          } catch (dirErr) {
            const msg =
              dirErr instanceof Error ? dirErr.message : String(dirErr);
            return {
              status: "error",
              error: `.agents/team.json is a dangling symlink: ${msg}`,
            };
          }
        }
      } catch {
        // .agents directory does not exist; treat as absent.
      }
      return { status: "absent" };
    }
    const msg = err instanceof Error ? err.message : String(err);
    return {
      status: "error",
      error: `failed to read .agents/team.json: ${msg}`,
    };
  }

  let realTeamPath;
  try {
    realTeamPath = realpathSync(teamPath);
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    if (linkStat.isSymbolicLink()) {
      return {
        status: "error",
        error: `.agents/team.json is a dangling symlink: ${msg}`,
      };
    }
    return {
      status: "error",
      error: `failed to read .agents/team.json: ${msg}`,
    };
  }

  if (!isPathInsideRealRoot(realRoot, realTeamPath)) {
    return {
      status: "error",
      error: ".agents/team.json must be inside the repository",
    };
  }
  return { status: "ok", realPath: realTeamPath };
}

/**
 * Resolves the git repository top-level directory for `cwd`, falling back to
 * `cwd` when `cwd` is not inside a git worktree.
 *
 * @param {string} [cwd]
 * @returns {string}
 */
export function resolveRepoRoot(cwd = process.cwd()) {
  const safeCwd =
    typeof cwd === "string" && cwd.trim() ? cwd.trim() : process.cwd();
  try {
    const res = spawnSync(
      "git",
      ["-C", safeCwd, "rev-parse", "--show-toplevel"],
      { encoding: "utf8", timeout: 5000 },
    );
    if (
      res.status === 0 &&
      typeof res.stdout === "string" &&
      res.stdout.trim()
    ) {
      return res.stdout.trim();
    }
  } catch {
    // Fall back to cwd outside git repositories.
  }
  return safeCwd;
}

export const INVALID_ROOT_ERROR =
  "root must be an absolute path to a directory";

function validateExplicitRoot(rawRoot) {
  if (typeof rawRoot !== "string" || !isAbsolute(rawRoot)) {
    return { ok: false, error: INVALID_ROOT_ERROR };
  }
  try {
    if (!statSync(rawRoot).isDirectory()) {
      return { ok: false, error: INVALID_ROOT_ERROR };
    }
  } catch {
    return { ok: false, error: INVALID_ROOT_ERROR };
  }
  return { ok: true, root: rawRoot };
}

/**
 * Reads `<root>/.agents/team.json` (capped at 64 KiB) directly from `root`
 * without climbing git top-level, parses and validates it, and resolves roles
 * against Antigravity's tier defaults.
 *
 * @param {string} root
 * @param {{ tiers?: Record<string, Record<string, unknown>> }} [defaults]
 */
function readTeamConfigAtRoot(root, defaults = TIER_DEFAULTS) {
  const checked = resolveRealTeamPath(root);
  if (checked.status === "absent") {
    const resolved = resolveTeam(null, "antigravity", defaults);
    return {
      file: null,
      errors: [],
      notes: resolved.notes,
      roles: resolved.roles,
    };
  }
  if (checked.status === "error") {
    const resolved = resolveTeam(null, "antigravity", defaults);
    return {
      file: ".agents/team.json",
      errors: [checked.error],
      notes: resolved.notes,
      roles: resolved.roles,
    };
  }

  let fd;
  try {
    fd = openSync(checked.realPath, "r");
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    const resolved = resolveTeam(null, "antigravity", defaults);
    return {
      file: ".agents/team.json",
      errors: [`failed to read .agents/team.json: ${msg}`],
      notes: resolved.notes,
      roles: resolved.roles,
    };
  }

  try {
    const st = fstatSync(fd);
    if (!st.isFile()) {
      const resolved = resolveTeam(null, "antigravity", defaults);
      return {
        file: ".agents/team.json",
        errors: [".agents/team.json is not a regular file"],
        notes: resolved.notes,
        roles: resolved.roles,
      };
    }
    if (st.size > MAX_TEAM_FILE_BYTES) {
      const resolved = resolveTeam(null, "antigravity", defaults);
      return {
        file: ".agents/team.json",
        errors: [
          `.agents/team.json exceeds maximum size of ${MAX_TEAM_FILE_BYTES} bytes (64 KiB)`,
        ],
        notes: resolved.notes,
        roles: resolved.roles,
      };
    }
    const chunks = [];
    let totalBytes = 0;
    const buf = Buffer.allocUnsafe(8192);
    while (true) {
      const n = fs.readSync(fd, buf, 0, buf.length, null);
      if (n === 0) break;
      totalBytes += n;
      if (totalBytes > MAX_TEAM_FILE_BYTES) {
        const resolved = resolveTeam(null, "antigravity", defaults);
        return {
          file: ".agents/team.json",
          errors: [
            `.agents/team.json exceeds maximum size of ${MAX_TEAM_FILE_BYTES} bytes (64 KiB)`,
          ],
          notes: resolved.notes,
          roles: resolved.roles,
        };
      }
      chunks.push(Buffer.from(buf.subarray(0, n)));
    }
    const text = Buffer.concat(chunks, totalBytes).toString("utf8");
    const parsed = parseTeam(text);
    const resolved = resolveTeam(parsed.team, "antigravity", defaults);
    return {
      file: ".agents/team.json",
      errors: parsed.errors,
      notes: resolved.notes,
      roles: resolved.roles,
    };
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    const resolved = resolveTeam(null, "antigravity", defaults);
    return {
      file: ".agents/team.json",
      errors: [`failed to read .agents/team.json: ${msg}`],
      notes: resolved.notes,
      roles: resolved.roles,
    };
  } finally {
    try {
      closeSync(fd);
    } catch {
      // Ignore close error.
    }
  }
}

/**
 * Reads `<repo root>/.agents/team.json` (capped at 64 KiB), parses and
 * validates it, and resolves roles against Antigravity's tier defaults.
 *
 * @param {string} [cwd]
 * @param {{ tiers?: Record<string, Record<string, string | null | undefined>> }} [defaults]
 */
export function readTeamConfig(cwd = process.cwd(), defaults = TIER_DEFAULTS) {
  return readTeamConfigAtRoot(resolveRepoRoot(cwd), defaults);
}

export function defaultFlowsDir() {
  if (process.env.VITRUVIAN_ORCH_DIR) {
    return process.env.VITRUVIAN_ORCH_DIR;
  }
  return join(
    homedir(),
    ".gemini",
    "antigravity",
    "vitruvian-orchestrator",
    "flows",
  );
}

const VALID_CONVERSATION_ID_RE = /^[a-zA-Z0-9][a-zA-Z0-9._-]{0,127}$/;
const VALID_HANDLE_RE = /^[a-z0-9][a-z0-9-]{0,63}$/;
export const MAX_STDIO_FRAME_BYTES = 256 * 1024;

export function sanitizeConversationId(rawId) {
  const trimmed = String(rawId ?? "").trim();
  if (
    !trimmed ||
    trimmed === "." ||
    trimmed === ".." ||
    trimmed.includes("..")
  ) {
    return "";
  }
  return VALID_CONVERSATION_ID_RE.test(trimmed) ? trimmed : "";
}

function canonicalizePathPrefix(p) {
  const raw = String(p ?? "").trim();
  if (!raw) return "";
  const abs = resolve(raw);
  let cur = abs;
  const suffix = [];
  while (true) {
    if (existsSync(cur)) {
      try {
        return join(realpathSync(cur), ...suffix);
      } catch {
        return abs;
      }
    }
    const parent = dirname(cur);
    if (parent === cur) {
      return abs;
    }
    suffix.unshift(basename(cur));
    cur = parent;
  }
}

function knownServerAppDataRoots(brainRoots) {
  const raw = Array.isArray(brainRoots)
    ? brainRoots
    : [
        process.env.ANTIGRAVITY_APP_DATA_DIR,
        join(homedir(), ".gemini", "antigravity"),
        join(homedir(), ".gemini", "antigravity-cli"),
      ];
  return raw.filter(Boolean);
}

function isTrustedArtifactsDir(artifactsDir, brainRoots) {
  const raw = String(artifactsDir ?? "").trim();
  if (!raw) return false;
  if (
    basename(dirname(raw)) !== "brain" ||
    !sanitizeConversationId(basename(raw))
  ) {
    return false;
  }
  const cand = canonicalizePathPrefix(raw);
  if (!cand) return false;
  for (const root of knownServerAppDataRoots(brainRoots)) {
    const canonRoot = canonicalizePathPrefix(root);
    if (!canonRoot) continue;
    const rel = relative(canonRoot, cand);
    if (rel && !rel.startsWith("..") && !isAbsolute(rel)) {
      return true;
    }
  }
  return false;
}

/**
 * Extracts root and calling subagent conversation metadata from MCP `_meta`.
 *
 * @param {Record<string, any> | null | undefined} meta
 * @param {string[]} [brainRoots]
 */
export function extractConversationMeta(meta = {}, brainRoots = undefined) {
  const m = meta && typeof meta === "object" ? meta : {};
  const artifactsDir = String(
    m["antigravity.google/artifacts_dir"] ?? m.artifacts_dir ?? "",
  ).trim();
  const artifactsCid = isTrustedArtifactsDir(artifactsDir, brainRoots)
    ? sanitizeConversationId(basename(artifactsDir))
    : "";
  const envCid = sanitizeConversationId(
    process.env.ANTIGRAVITY_CONVERSATION_ID,
  );

  const rawParent =
    m["antigravity.google/parent_conversation_id"] ??
    m.parent_conversation_id ??
    m.parentConversationId ??
    "";
  const parentConversationId = String(rawParent ?? "").trim();

  const rawAgent =
    m["antigravity.google/agent_name"] ?? m.agent_name ?? m.agentName ?? "";
  const agentName = String(rawAgent ?? "").trim();

  const explicitRoot =
    m["antigravity.google/root_conversation_id"] ??
    m.root_conversation_id ??
    m.rootConversationId ??
    m["antigravity.google/parent_conversation_id"] ??
    (envCid || undefined) ??
    m["antigravity.google/conversation_id"] ??
    (artifactsCid || undefined) ??
    m.conversation_id ??
    m.conversationId;

  const hasExplicitRoot =
    explicitRoot !== undefined && String(explicitRoot).trim() !== "";
  const rootConversationId = !hasExplicitRoot
    ? "default"
    : sanitizeConversationId(explicitRoot);

  const rawMetaCaller =
    m["antigravity.google/conversation_id"] ??
    m.conversation_id ??
    m.conversationId ??
    m.run_id ??
    m.runId ??
    m.id ??
    (artifactsCid || undefined);

  const hasMetaCaller =
    rawMetaCaller !== undefined && String(rawMetaCaller).trim() !== "";
  const callerConversationId = hasMetaCaller
    ? sanitizeConversationId(rawMetaCaller)
    : !parentConversationId && !agentName
      ? envCid
      : "";

  return {
    rootConversationId,
    callerConversationId,
    parentConversationId,
    agentName,
    rawMeta: m,
  };
}

function resolveMemberTarget(ref, flow) {
  const trimmed = String(ref ?? "").trim();
  if (!trimmed) return null;
  const norm = trimmed.replace(/^@+/, "").toLowerCase();
  if (norm === "lead") return null;
  if (flow && Array.isArray(flow.runs)) {
    if (flow.runs.some((r) => r.role === "lead" && r.id === trimmed)) {
      return null;
    }
    const exact = flow.runs.find((r) => r.role !== "lead" && r.id === trimmed);
    if (exact) return { id: exact.id, agent: exact.agent };
    const byPrefix = flow.runs.findLast(
      (r) => r.role !== "lead" && r.id.startsWith(`${trimmed}#`),
    );
    if (byPrefix) return { id: byPrefix.id, agent: byPrefix.agent };
    const activeByAgent = flow.runs.findLast(
      (r) =>
        r.role !== "lead" &&
        String(r.agent ?? "")
          .trim()
          .toLowerCase() === norm &&
        r.memberState !== "killed" &&
        r.memberState !== "retired",
    );
    if (activeByAgent)
      return { id: activeByAgent.id, agent: activeByAgent.agent };
    const anyByAgent = flow.runs.findLast(
      (r) =>
        r.role !== "lead" &&
        String(r.agent ?? "")
          .trim()
          .toLowerCase() === norm,
    );
    if (anyByAgent) return { id: anyByAgent.id, agent: anyByAgent.agent };
  }
  return {
    id: trimmed,
    agent: norm,
  };
}

/**
 * Validates `progress` tool arguments, returning a human-readable error message
 * when `phase` or any task's `tier` is missing/unknown instead of falling back.
 *
 * @param {Record<string, any>} args
 * @returns {string | null}
 */
export function validateProgressArgs(args = {}) {
  const inp = args && typeof args === "object" ? args : {};
  if (inp.phase !== undefined) {
    const phase = typeof inp.phase === "string" ? inp.phase.trim() : "";
    if (!VALID_PHASES.has(phase)) {
      return `invalid phase ${JSON.stringify(inp.phase)}: expected one of ${[...VALID_PHASES].join(", ")}`;
    }
  }
  if (Array.isArray(inp.tasks)) {
    for (let i = 0; i < inp.tasks.length; i += 1) {
      const rawTier = inp.tasks[i]?.tier;
      const tier =
        typeof rawTier === "string" ? rawTier.trim().toLowerCase() : "";
      if (!VALID_TIERS.has(tier)) {
        return `invalid tier ${JSON.stringify(rawTier)} for task ${i + 1}: expected one of ${[...VALID_TIERS].join(", ")}`;
      }
    }
  }
  return null;
}

/**
 * Maps `progress` tool arguments to an ordered list of orchestrator-core events:
 * `plan` -> `phase` -> `task.accept` -> `task.return` -> `member.retire` -> `member.kill` -> `close`.
 *
 * @param {Record<string, any>} args
 * @param {number} [at]
 * @param {string} [rootConversationId]
 * @param {Record<string, any>} [rawMeta]
 * @param {import("../sidecars/panel/lib/orchestrator-core.mjs").Flow | null} [flow]
 */
export function mapProgressToEvents(
  args = {},
  at = Date.now(),
  rootConversationId = "default",
  rawMeta = undefined,
  flow = undefined,
) {
  const validationError = validateProgressArgs(args);
  if (validationError) {
    throw new Error(validationError);
  }
  const inp = args && typeof args === "object" ? args : {};
  const events = [];
  const metaFields = {
    rootConversationId,
    ...(rawMeta && Object.keys(rawMeta).length > 0 ? { _meta: rawMeta } : {}),
  };

  if (Array.isArray(inp.tasks)) {
    const tasks = inp.tasks.map((t) => ({
      title: String(t?.title ?? "").trim(),
      specialist: String(t?.specialist ?? "wren").trim(),
      tier: String(t.tier).trim().toLowerCase(),
      after: Array.isArray(t?.after)
        ? t.after.map((n) => Number(n)).filter((n) => Number.isInteger(n))
        : [],
      ...(t?.model !== undefined && t?.model !== null
        ? { model: t.model }
        : {}),
      ...(t?.worktree !== undefined && t?.worktree !== null
        ? { worktree: t.worktree }
        : {}),
    }));
    const planEvent = {
      type: "plan",
      at,
      ...metaFields,
      tasks,
    };
    if (inp.title !== undefined) {
      planEvent.title = String(inp.title).trim();
    }
    events.push(planEvent);
  }

  if (typeof inp.phase === "string" && inp.phase.trim() !== "") {
    events.push({
      type: "phase",
      at,
      ...metaFields,
      phase: inp.phase.trim(),
    });
  }

  if (inp.accept !== undefined && inp.accept !== null) {
    const n = Number(inp.accept);
    if (Number.isInteger(n) && n > 0) {
      events.push({
        type: "task.accept",
        at,
        ...metaFields,
        n,
      });
    }
  }

  if (inp.return !== undefined && inp.return !== null) {
    const n = Number(inp.return);
    if (Number.isInteger(n) && n > 0) {
      events.push({
        type: "task.return",
        at,
        ...metaFields,
        n,
      });
    }
  }

  if (typeof inp.retire === "string" && inp.retire.trim() !== "") {
    const target = resolveMemberTarget(inp.retire, flow);
    if (target) {
      events.push({
        type: "member.retire",
        at,
        ...metaFields,
        id: target.id,
        ...(target.agent ? { agent: target.agent } : {}),
      });
    }
  }

  if (typeof inp.kill === "string" && inp.kill.trim() !== "") {
    const target = resolveMemberTarget(inp.kill, flow);
    if (target) {
      events.push({
        type: "member.kill",
        at,
        ...metaFields,
        id: target.id,
        ...(target.agent ? { agent: target.agent } : {}),
      });
    }
  }

  if (inp.finished === true) {
    events.push({
      type: "close",
      at,
      ...metaFields,
    });
  }

  return events;
}

/**
 * Maps `step` tool arguments and `_meta` to a `run.progress` event.
 * If the caller cannot be matched to a run, returns `{ matched: false, event: null, message }`.
 *
 * @param {Record<string, any>} args
 * @param {Record<string, any>} meta
 * @param {number} at
 * @param {import("../sidecars/panel/lib/orchestrator-core.mjs").Flow | null} [flow]
 */
export function mapStepToEvent(
  args = {},
  meta = {},
  at = Date.now(),
  flow = undefined,
  brainRoots = undefined,
) {
  const inp = args && typeof args === "object" ? args : {};
  const {
    rootConversationId,
    callerConversationId,
    parentConversationId,
    agentName,
    rawMeta,
  } = extractConversationMeta(meta, brainRoots);

  const hasPause = inp.paused === "quota" || inp.paused === "error";
  const hasInvalidPause =
    inp.paused !== undefined && inp.paused !== null && !hasPause;
  const rawWorktree =
    typeof inp.worktree === "string" ? inp.worktree.trim() : "";
  const validWorktree = isValidWorktree(rawWorktree) ? rawWorktree : undefined;
  const hasDelegateUpdate =
    (typeof inp.delegate === "string" && Boolean(inp.delegate.trim())) ||
    Boolean(inp.delegateUsage && typeof inp.delegateUsage === "object");
  const hasOtherField = hasPause || Boolean(validWorktree) || hasDelegateUpdate;
  const hasAnyStepCount = inp.done !== undefined || inp.total !== undefined;
  const hasValidStepCounts =
    typeof inp.done === "number" &&
    Number.isInteger(inp.done) &&
    inp.done >= 0 &&
    typeof inp.total === "number" &&
    Number.isInteger(inp.total) &&
    inp.total >= 1 &&
    inp.done <= inp.total;

  if (
    hasInvalidPause ||
    (hasAnyStepCount && !hasValidStepCounts) ||
    (!hasValidStepCounts && !hasOtherField)
  ) {
    const error =
      "Invalid params: step requires integer done (0 <= done <= total) and total (>= 1), paused ('quota' | 'error'), or a valid worktree";
    return {
      valid: false,
      matched: false,
      rootConversationId,
      event: null,
      events: [],
      error,
      message: error,
    };
  }

  const done = hasValidStepCounts ? inp.done : 0;
  const total = hasValidStepCounts ? inp.total : 0;
  const note = inp.note !== undefined ? String(inp.note) : "";

  let runId = callerConversationId;
  if (flow && Array.isArray(flow.runs)) {
    const directMatch =
      runId &&
      flow.runs.findLast((r) => r.id === runId || r.id.startsWith(`${runId}#`));
    if (directMatch) {
      runId = directMatch.id;
    } else if (agentName) {
      const agentMatch = flow.runs.findLast(
        (r) =>
          r.role === "worker" &&
          r.status === "running" &&
          r.agent === agentName,
      );
      if (agentMatch) {
        runId = agentMatch.id;
      } else if (flow.runs.length > 0 && !parentConversationId) {
        return {
          valid: true,
          matched: false,
          rootConversationId,
          event: null,
          events: [],
          message: `step ignored: caller '${callerConversationId || agentName}' could not be matched to an active run`,
        };
      }
    } else if (flow.runs.length > 0 && !parentConversationId) {
      return {
        valid: true,
        matched: false,
        rootConversationId,
        event: null,
        events: [],
        message: `step ignored: caller '${callerConversationId || "unknown"}' could not be matched to an active run`,
      };
    }
  }

  if (!runId) {
    return {
      valid: true,
      matched: false,
      rootConversationId,
      event: null,
      events: [],
      message: "step ignored: caller could not be matched to a run",
    };
  }

  const metaFields = {
    rootConversationId,
    ...(agentName ? { agent: agentName } : {}),
    ...(rawMeta && Object.keys(rawMeta).length > 0 ? { _meta: rawMeta } : {}),
  };

  const hasStepFields =
    hasValidStepCounts || hasDelegateUpdate || Boolean(validWorktree);

  const events = [];
  if (hasStepFields) {
    events.push({
      type: "run.progress",
      at,
      ...metaFields,
      id: runId,
      ...(hasValidStepCounts
        ? {
            steps: {
              done,
              total,
              note,
            },
          }
        : {}),
      ...(typeof inp.delegate === "string" && inp.delegate.trim()
        ? { delegate: inp.delegate.trim() }
        : {}),
      ...(inp.delegateUsage && typeof inp.delegateUsage === "object"
        ? { delegateTokens: inp.delegateUsage }
        : {}),
      ...(validWorktree ? { worktree: validWorktree } : {}),
    });
  }

  if (hasPause) {
    const detail =
      typeof inp.detail === "string" && inp.detail.trim()
        ? inp.detail.trim()
        : undefined;
    events.push({
      type: "member.pause",
      at,
      ...metaFields,
      id: runId,
      reason: inp.paused,
      ...(detail ? { detail } : {}),
    });
  }

  const event = events[0] ?? null;
  const pauseSuffix = hasPause
    ? ` [paused: ${inp.paused}${inp.detail ? ` — ${String(inp.detail).trim()}` : ""}]`
    : "";

  return {
    valid: true,
    matched: true,
    rootConversationId,
    event,
    events,
    message: hasValidStepCounts
      ? `step updated: ${done}/${total}${note ? ` (${note})` : ""}${pauseSuffix}`
      : hasPause
        ? `step paused: ${inp.paused}${inp.detail ? ` (${String(inp.detail).trim()})` : ""}`
        : `step updated: ${validWorktree ? `worktree ${validWorktree}` : `delegate ${String(inp.delegate ?? "").trim() || "usage"}`}${note ? ` (${note})` : ""}`,
  };
}

const NO_FLOW_POST =
  "no orchestrator flow is running, so this post was not saved. The lead starts one with the progress tool (title and tasks).";
const NO_FLOW_BOARD =
  "no orchestrator flow is running, so there is no board to read. The lead starts one with the progress tool (title and tasks).";

/**
 * Maps `post` tool arguments and `_meta` to a `post` event.
 *
 * @param {Record<string, any>} args
 * @param {Record<string, any>} meta
 * @param {number} at
 * @param {import("../sidecars/panel/lib/orchestrator-core.mjs").Flow | null} [flow]
 */
export function mapPostToEvent(
  args = {},
  meta = {},
  at = Date.now(),
  flow = undefined,
  brainRoots = undefined,
) {
  const inp = args && typeof args === "object" ? args : {};
  const {
    rootConversationId,
    callerConversationId,
    parentConversationId,
    agentName,
    rawMeta,
  } = extractConversationMeta(meta, brainRoots);

  const text = typeof inp.text === "string" ? inp.text : "";
  if (text.trim().length === 0) {
    return {
      valid: false,
      rootConversationId,
      event: null,
    };
  }

  const chCheck = validatePostChannel(flow ?? null, inp.channel);
  if (!chCheck.ok) {
    return {
      valid: false,
      error: chCheck.error,
      rootConversationId,
      event: null,
    };
  }

  let matchedRun = null;
  if (flow && Array.isArray(flow.runs)) {
    if (callerConversationId) {
      matchedRun =
        flow.runs.findLast(
          (r) =>
            r.id === callerConversationId ||
            r.id.startsWith(`${callerConversationId}#`),
        ) ?? null;
    }
    if (!matchedRun && agentName) {
      matchedRun =
        flow.runs.findLast(
          (r) =>
            r.role === "worker" &&
            String(r.agent ?? "").toLowerCase() === agentName.toLowerCase(),
        ) ?? null;
    }
  }

  const matchedWorkerRun =
    matchedRun && matchedRun.role !== "lead" ? matchedRun : null;
  const isLead =
    Boolean(callerConversationId) &&
    Boolean(rootConversationId) &&
    rootConversationId !== "default" &&
    callerConversationId === rootConversationId &&
    !parentConversationId &&
    !agentName &&
    !matchedWorkerRun;
  const isWorker = !isLead;

  let from = "lead";
  if (isWorker) {
    const runCandidate = String(matchedWorkerRun?.agent || "")
      .trim()
      .replace(/^@+/, "")
      .toLowerCase();
    const metaCandidate = String(agentName || "")
      .trim()
      .replace(/^@+/, "")
      .toLowerCase();
    const candidate =
      VALID_HANDLE_RE.test(runCandidate) && runCandidate !== "lead"
        ? runCandidate
        : metaCandidate;
    from =
      VALID_HANDLE_RE.test(candidate) && candidate !== "lead"
        ? candidate
        : "helper";
  }

  const runId =
    matchedWorkerRun?.id ||
    (isWorker && callerConversationId ? callerConversationId : undefined);

  const metaFields = {
    rootConversationId,
    ...(agentName ? { agent: agentName } : {}),
    ...(rawMeta && Object.keys(rawMeta).length > 0 ? { _meta: rawMeta } : {}),
  };

  const event = {
    type: "post",
    at,
    ...metaFields,
    from,
    text,
    ...(Array.isArray(inp.to) ? { to: inp.to } : {}),
    ...(typeof inp.kind === "string" && inp.kind.trim()
      ? { kind: inp.kind.trim() }
      : {}),
    ...(typeof inp.replyTo === "number" &&
    Number.isInteger(inp.replyTo) &&
    inp.replyTo > 0
      ? { replyTo: inp.replyTo }
      : {}),
    ...(chCheck.channel && chCheck.channel !== "main"
      ? { channel: chCheck.channel }
      : {}),
    ...(runId ? { runId } : {}),
  };

  return {
    valid: true,
    rootConversationId,
    event,
  };
}

/**
 * Queries board posts for the `board` MCP read tool, resolving caller identity
 * for Antigravity worker subagents when `to` is `"me"` or omitted.
 *
 * @param {Record<string, any>} args
 * @param {Record<string, any>} meta
 * @param {import("../sidecars/panel/lib/orchestrator-core.mjs").Flow | null} [flow]
 */
export function queryBoard(
  args = {},
  meta = {},
  flow = undefined,
  brainRoots = undefined,
) {
  const inp = args && typeof args === "object" ? args : {};
  const {
    rootConversationId,
    callerConversationId,
    parentConversationId,
    agentName,
  } = extractConversationMeta(meta, brainRoots);

  let matchedRun = null;
  if (flow && Array.isArray(flow.runs) && callerConversationId) {
    matchedRun =
      flow.runs.findLast(
        (r) =>
          r.role !== "lead" &&
          (r.id === callerConversationId ||
            r.id.startsWith(`${callerConversationId}#`)),
      ) ?? null;
  }

  const isLead =
    Boolean(callerConversationId) &&
    Boolean(rootConversationId) &&
    rootConversationId !== "default" &&
    callerConversationId === rootConversationId &&
    !parentConversationId &&
    !agentName &&
    !matchedRun;
  const isWorker = !isLead;

  let callerAgent = "";
  if (isWorker) {
    const runAgent = String(matchedRun?.agent || "")
      .trim()
      .replace(/^@+/, "")
      .toLowerCase();
    const metaAgent = String(agentName || "")
      .trim()
      .replace(/^@+/, "")
      .toLowerCase();
    if (VALID_HANDLE_RE.test(runAgent) && runAgent !== "lead") {
      callerAgent = runAgent;
    } else if (VALID_HANDLE_RE.test(metaAgent) && metaAgent !== "lead") {
      callerAgent = metaAgent;
    } else if (
      !callerConversationId ||
      runAgent === "lead" ||
      metaAgent === "lead"
    ) {
      callerAgent = "helper";
    }
  }

  const rawTo = typeof inp.to === "string" ? inp.to.trim() : "";
  const normTo = rawTo.replace(/^@+/, "").toLowerCase();
  let effectiveTo;
  if (normTo === "me") {
    effectiveTo = isWorker ? callerAgent || undefined : "lead";
  } else if (rawTo.length > 0) {
    effectiveTo = rawTo;
  } else if (isWorker && callerAgent) {
    effectiveTo = callerAgent;
  }

  const rawLimit =
    typeof inp.limit === "number" && Number.isFinite(inp.limit)
      ? Math.floor(inp.limit)
      : 20;
  const limit = Math.max(1, Math.min(100, rawLimit));

  return boardView(flow ?? null, {
    to: effectiveTo,
    from: typeof inp.from === "string" ? inp.from : undefined,
    kind: typeof inp.kind === "string" ? inp.kind : undefined,
    channel: typeof inp.channel === "string" ? inp.channel : undefined,
    search: typeof inp.search === "string" ? inp.search : undefined,
    limit,
  }).map((p) => ({
    seq: p.seq,
    from: p.from,
    to: p.to,
    kind: p.kind,
    replyTo: p.replyTo,
    at: p.at,
    text: p.text,
    ...(p.channel && p.channel !== "main" ? { channel: p.channel } : {}),
  }));
}

function unquoteTranscriptString(val) {
  const s = String(val ?? "").trim();
  if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
    try {
      const parsed = JSON.parse(s);
      if (typeof parsed === "string") return parsed.trim();
    } catch {
      return s.slice(1, -1).trim();
    }
  }
  return s;
}

function readTranscriptToolArgs(tc) {
  if (!tc || typeof tc !== "object") return {};
  const raw = tc.args ?? tc.arguments ?? tc.input ?? tc.parameters ?? {};
  if (typeof raw === "string") {
    try {
      return JSON.parse(raw);
    } catch {
      return {};
    }
  }
  return raw && typeof raw === "object" ? raw : {};
}

function parseTranscriptEntryTime(entry, fallbackMs) {
  if (typeof entry?.at === "number" && Number.isFinite(entry.at)) {
    return entry.at;
  }
  if (typeof entry?.created_at === "string" && entry.created_at) {
    const parsed = Date.parse(entry.created_at);
    if (Number.isFinite(parsed)) return parsed;
  }
  return fallbackMs;
}

function extractTranscriptRunEventsForServer(transcriptText = "", baseAt = 0) {
  const entries = [];
  for (const line of String(transcriptText ?? "").split("\n")) {
    if (!line.trim()) continue;
    try {
      const parsed = JSON.parse(line);
      if (parsed && typeof parsed === "object") entries.push(parsed);
    } catch {
      // Ignore malformed transcript line.
    }
  }

  const events = [];
  const subagentsByConvId = new Map();
  let leadStarted = false;
  let leadStartAt = baseAt;
  let leadModel = "pro";
  const leadTokens = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 };

  for (let i = 0; i < entries.length; i += 1) {
    const entry = entries[i];
    const stepAt = parseTranscriptEntryTime(
      entry,
      baseAt > 0 ? baseAt + i * 10 : 0,
    );

    const inTok = Number(entry.input_tokens ?? entry.inputTokens ?? 0) || 0;
    const outTok = Number(entry.output_tokens ?? entry.outputTokens ?? 0) || 0;
    const cacheReadTok =
      Number(entry.cache_read_tokens ?? entry.cacheReadTokens ?? 0) || 0;
    const cacheWriteTok =
      Number(entry.cache_write_tokens ?? entry.cacheWriteTokens ?? 0) || 0;
    if (inTok > 0 || outTok > 0 || cacheReadTok > 0 || cacheWriteTok > 0) {
      if (!leadStarted) {
        leadStarted = true;
        leadStartAt = stepAt;
        if (typeof entry.model === "string" && entry.model.trim()) {
          leadModel = unquoteTranscriptString(entry.model);
        }
        events.push({
          type: "run.start",
          at: leadStartAt,
          id: "lead",
          harness: "antigravity",
          agent: "lead",
          model: leadModel,
          effort: null,
          title: "Lead orchestrator",
          role: "lead",
          tokens: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
        });
      }
      leadTokens.input += inTok;
      leadTokens.output += outTok;
      leadTokens.cacheRead += cacheReadTok;
      leadTokens.cacheWrite += cacheWriteTok;
      events.push({
        type: "run.progress",
        at: stepAt,
        id: "lead",
        tokens: { ...leadTokens },
      });
    }

    if (
      entry.type === "SYSTEM_MESSAGE" &&
      typeof entry.content === "string" &&
      entry.content.includes("sender=")
    ) {
      const senderMatch = /\bsender=([a-zA-Z0-9_-]+)/.exec(entry.content);
      if (senderMatch) {
        const senderId = senderMatch[1];
        const sub = subagentsByConvId.get(senderId);
        if (sub && sub.activeRunId) {
          events.push({
            type: "run.end",
            at: stepAt,
            id: sub.activeRunId,
            status: "done",
          });
          sub.activeRunId = null;
        }
      }
    }

    const tcs = Array.isArray(entry.tool_calls) ? entry.tool_calls : [];
    for (let tcIdx = 0; tcIdx < tcs.length; tcIdx += 1) {
      const tc = tcs[tcIdx];
      if (!tc || typeof tc !== "object") continue;
      const name = String(tc.name ?? tc.tool_name ?? "unknown");
      const rawArgs = readTranscriptToolArgs(tc);

      if (name === "invoke_subagent") {
        let items = [rawArgs];
        if (typeof rawArgs.Subagents === "string") {
          try {
            const parsedList = JSON.parse(rawArgs.Subagents);
            if (Array.isArray(parsedList) && parsedList.length > 0) {
              items = parsedList;
            }
          } catch {
            // Fall back to rawArgs.
          }
        }

        let createdConvId = "";
        const nextEntry = entries[i + 1];
        if (
          nextEntry &&
          nextEntry.type === "GENERIC" &&
          typeof nextEntry.content === "string"
        ) {
          const cidMatch = /"conversationId"\s*:\s*"([^"]+)"/.exec(
            nextEntry.content,
          );
          if (cidMatch) {
            createdConvId = cidMatch[1].trim();
          }
        }

        for (const item of items) {
          const agent =
            unquoteTranscriptString(
              item.TypeName ??
                item.subagent_type ??
                item.type ??
                item.agent ??
                "self",
            ) || "self";
          const title =
            unquoteTranscriptString(
              item.Role ?? item.description ?? item.role ?? agent,
            ) || agent;
          const model =
            unquoteTranscriptString(item.Model ?? item.model ?? "inherit") ||
            "inherit";
          const effort = item.effort
            ? unquoteTranscriptString(item.effort)
            : null;

          const convId =
            createdConvId ||
            unquoteTranscriptString(
              item.conversationId ??
                tc.id ??
                tc.tool_call_id ??
                `subagent-${subagentsByConvId.size + 1}`,
            );

          subagentsByConvId.set(convId, {
            convId,
            agent,
            title,
            model,
            effort,
            round: 1,
            activeRunId: convId,
            asyncLifecycle: Boolean(createdConvId),
          });

          events.push({
            type: "run.start",
            at: stepAt,
            id: convId,
            harness: "antigravity",
            agent,
            model,
            effort,
            title,
            role: "worker",
          });

          if (!createdConvId) {
            if (entry.status === "ERROR") {
              events.push({
                type: "run.end",
                at: stepAt > 0 ? stepAt + 1 : 0,
                id: convId,
                status: "error",
              });
              subagentsByConvId.get(convId).activeRunId = null;
            } else if (entry.status === "DONE") {
              events.push({
                type: "run.end",
                at: stepAt > 0 ? stepAt + 1 : 0,
                id: convId,
                status: "done",
              });
              subagentsByConvId.get(convId).activeRunId = null;
            }
          }
        }
      } else if (name === "send_message") {
        const recipient = unquoteTranscriptString(
          rawArgs.Recipient ?? rawArgs.recipient ?? "",
        );
        if (recipient && subagentsByConvId.has(recipient)) {
          const sub = subagentsByConvId.get(recipient);
          sub.round += 1;
          const nextRunId = `${recipient}#${sub.round}`;
          sub.activeRunId = nextRunId;
          events.push({
            type: "run.start",
            at: stepAt,
            id: nextRunId,
            harness: "antigravity",
            agent: sub.agent,
            model: sub.model,
            effort: sub.effort,
            title: sub.title,
            role: "worker",
          });
          if (!sub.asyncLifecycle) {
            if (entry.status === "ERROR") {
              events.push({
                type: "run.end",
                at: stepAt > 0 ? stepAt + 1 : 0,
                id: nextRunId,
                status: "error",
              });
              subagentsByConvId.get(recipient).activeRunId = null;
            } else if (entry.status === "DONE") {
              events.push({
                type: "run.end",
                at: stepAt > 0 ? stepAt + 1 : 0,
                id: nextRunId,
                status: "done",
              });
              subagentsByConvId.get(recipient).activeRunId = null;
            }
          }
        }
      }
    }
  }

  return events;
}

const SERVER_EVENT_ORDER = Object.freeze({
  plan: 0,
  team: 1,
  phase: 2,
  "run.start": 3,
  "run.progress": 4,
  "member.pause": 4,
  "run.end": 5,
  channel: 6,
  post: 7,
  wake: 8,
  "member.retire": 9,
  "member.kill": 9,
  "task.return": 10,
  "task.accept": 11,
  close: 12,
});

function foldServerFlowEvents(flowEvents = [], transcriptEvents = []) {
  const firstPlan = flowEvents.find((e) => e?.type === "plan");
  const baseAt =
    typeof firstPlan?.at === "number" && Number.isFinite(firstPlan.at)
      ? firstPlan.at
      : 1000;

  const existingRunIds = new Set(
    flowEvents
      .filter((e) => e?.type === "run.start" && typeof e.id === "string")
      .map((e) => e.id),
  );

  const normalizedTranscript = [];
  for (let i = 0; i < transcriptEvents.length; i += 1) {
    const ev = transcriptEvents[i];
    if (!ev || typeof ev !== "object") continue;
    if (ev.id && existingRunIds.has(ev.id)) continue;
    const at = typeof ev.at === "number" && ev.at > 0 ? ev.at : baseAt + i + 1;
    normalizedTranscript.push({ ...ev, at });
  }

  const combined =
    normalizedTranscript.length > 0
      ? [...flowEvents, ...normalizedTranscript]
          .map((ev, idx) => ({ ev, idx }))
          .sort((a, b) => {
            const atA = typeof a.ev.at === "number" ? a.ev.at : baseAt;
            const atB = typeof b.ev.at === "number" ? b.ev.at : baseAt;
            if (atA !== atB) return atA - atB;
            const ordA = SERVER_EVENT_ORDER[a.ev.type] ?? 99;
            const ordB = SERVER_EVENT_ORDER[b.ev.type] ?? 99;
            if (ordA !== ordB) return ordA - ordB;
            return a.idx - b.idx;
          })
          .map((item) => item.ev)
      : flowEvents;

  let flow = initialFlow();
  let pendingTeamEvent = null;
  for (const rawEvent of combined) {
    let event = rawEvent;
    if (!flow && event?.type === "team" && validateTeamEvent(event).ok) {
      pendingTeamEvent = event;
      continue;
    }
    if (
      flow &&
      (event.type === "run.progress" || event.type === "member.pause") &&
      !flow.runs.some((r) => r.id === event.id)
    ) {
      const byPrefix =
        event.id &&
        flow.runs.findLast(
          (r) => r.id === event.id || r.id.startsWith(`${event.id}#`),
        );
      const byAgent =
        !byPrefix &&
        event.agent &&
        flow.runs.findLast(
          (r) =>
            r.role === "worker" &&
            r.status === "running" &&
            r.agent === event.agent,
        );
      const fallbackWorker =
        !byPrefix &&
        !byAgent &&
        flow.runs.findLast(
          (r) => r.role === "worker" && r.status === "running",
        );
      const target = byPrefix || byAgent || fallbackWorker;
      if (target) {
        event = { ...event, id: target.id };
      }
    } else if (
      flow &&
      (event.type === "member.retire" || event.type === "member.kill") &&
      !flow.runs.some((r) => r.id === event.id)
    ) {
      const byPrefix =
        event.id &&
        flow.runs.findLast(
          (r) =>
            r.role !== "lead" &&
            (r.id === event.id || r.id.startsWith(`${event.id}#`)),
        );
      const norm = String(event.agent || event.id || "")
        .trim()
        .replace(/^@+/, "")
        .toLowerCase();
      const activeByAgent =
        !byPrefix &&
        norm &&
        flow.runs.findLast(
          (r) =>
            r.role !== "lead" &&
            String(r.agent ?? "")
              .trim()
              .toLowerCase() === norm &&
            r.memberState !== "killed" &&
            r.memberState !== "retired",
        );
      const anyByAgent =
        !byPrefix &&
        !activeByAgent &&
        norm &&
        flow.runs.findLast(
          (r) =>
            r.role !== "lead" &&
            String(r.agent ?? "")
              .trim()
              .toLowerCase() === norm,
        );
      const target = byPrefix || activeByAgent || anyByAgent;
      if (target) {
        event = { ...event, id: target.id };
      }
    }
    try {
      flow = reduce(flow, event);
      if (flow && pendingTeamEvent && event?.type === "plan") {
        flow = reduce(flow, pendingTeamEvent);
        pendingTeamEvent = null;
      }
    } catch {
      // Ignore malformed event.
    }
  }
  return flow;
}

export function resolveServerBrainRoots(options = {}) {
  const m =
    options?.meta && typeof options.meta === "object" ? options.meta : {};
  const artifactsDir = String(
    m["antigravity.google/artifacts_dir"] ?? m.artifacts_dir ?? "",
  ).trim();
  const knownRoots = knownServerAppDataRoots(options.brainRoots);
  const inferredRoot = isTrustedArtifactsDir(artifactsDir, options.brainRoots)
    ? dirname(dirname(canonicalizePathPrefix(artifactsDir)))
    : "";

  const rawRoots = [inferredRoot, ...knownRoots];
  return [...new Set(rawRoots.filter(Boolean))];
}

function readServerTranscript(conversationId, roots) {
  const safeCid = sanitizeConversationId(conversationId);
  if (!safeCid || safeCid === "default") return "";
  for (const root of roots) {
    const candidate = join(
      root,
      "brain",
      safeCid,
      ".system_generated",
      "logs",
      "transcript.jsonl",
    );
    if (!existsSync(candidate)) continue;
    try {
      return readFileSync(candidate, "utf8");
    } catch {
      // Try next candidate root.
    }
  }
  return "";
}

export function readFlowFromJsonlFile(filePath, options = {}) {
  if (!existsSync(filePath)) return initialFlow();
  const flowEvents = [];
  try {
    const raw = readFileSync(filePath, "utf8");
    for (const line of raw.split("\n")) {
      if (!line.trim()) continue;
      try {
        const parsed = JSON.parse(line);
        if (parsed && typeof parsed === "object") {
          flowEvents.push(parsed);
        }
      } catch {
        // Ignore malformed line.
      }
    }
  } catch {
    return initialFlow();
  }

  const firstPlan = flowEvents.find((e) => e?.type === "plan");
  const baseAt = typeof firstPlan?.at === "number" ? firstPlan.at : 0;
  const roots = resolveServerBrainRoots(options);
  const rootCid = sanitizeConversationId(
    options.conversationId || basename(filePath, ".jsonl"),
  );
  const parentCid = options.parentConversationId
    ? sanitizeConversationId(options.parentConversationId)
    : "";

  const transcriptEvents = [];
  const rootTranscript = readServerTranscript(rootCid, roots);
  if (rootTranscript) {
    transcriptEvents.push(
      ...extractTranscriptRunEventsForServer(rootTranscript, baseAt),
    );
  }
  if (parentCid && parentCid !== "default" && parentCid !== rootCid) {
    const parentTranscript = readServerTranscript(parentCid, roots);
    if (parentTranscript) {
      transcriptEvents.push(
        ...extractTranscriptRunEventsForServer(parentTranscript, baseAt),
      );
    }
  }

  return foldServerFlowEvents(flowEvents, transcriptEvents);
}

export function appendFlowEvents(flowsDir, rootConversationId, events) {
  if (!Array.isArray(events) || events.length === 0) return null;
  const safeId = sanitizeConversationId(rootConversationId);
  if (!safeId) return null;
  mkdirSync(flowsDir, { recursive: true });
  const filePath = join(flowsDir, `${safeId}.jsonl`);
  const payload = events.map((ev) => JSON.stringify(ev)).join("\n") + "\n";
  appendFileSync(filePath, payload, "utf8");
  return filePath;
}

function isKnownWorkerCaller(
  callerConversationId,
  currentFlow,
  flowsDir,
  options,
) {
  if (!callerConversationId) return false;
  const matchesWorker = (f) =>
    Boolean(
      f &&
      Array.isArray(f.runs) &&
      f.runs.some(
        (r) =>
          r.role !== "lead" &&
          (r.id === callerConversationId ||
            r.id.startsWith(`${callerConversationId}#`)),
      ),
    );
  if (matchesWorker(currentFlow)) return true;
  if (!flowsDir || !existsSync(flowsDir)) return false;
  try {
    for (const name of readdirSync(flowsDir)) {
      if (!name.endsWith(".jsonl")) continue;
      const cid = sanitizeConversationId(basename(name, ".jsonl"));
      if (!cid) continue;
      const candidatePath = join(flowsDir, `${cid}.jsonl`);
      const f = readFlowFromJsonlFile(candidatePath, {
        brainRoots: options?.brainRoots,
        conversationId: cid,
      });
      if (matchesWorker(f)) return true;
    }
  } catch {
    return false;
  }
  return false;
}

export function formatFlowSummary(flow) {
  if (!flow) {
    return "flow updated: 0/0 accepted";
  }
  const total = flow.tasks.length;
  const accepted = total - remaining(flow);
  return `flow updated: ${accepted}/${total} accepted`;
}

/**
 * Handles a single JSON-RPC 2.0 request or notification message.
 * Returns a JSON-RPC response object, or `null` for notifications.
 *
 * @param {Record<string, any>} message
 * @param {{ flowsDir?: string, now?: () => number, flow?: any }} [options]
 */
export function handleJsonRpcMessage(message, options = {}) {
  if (!message || typeof message !== "object") {
    return {
      jsonrpc: "2.0",
      id: null,
      error: { code: -32600, message: "Invalid Request" },
    };
  }

  const hasId = Object.prototype.hasOwnProperty.call(message, "id");
  const id = message.id ?? null;
  const method = String(message.method ?? "");
  const params =
    message.params && typeof message.params === "object" ? message.params : {};

  if (!hasId) {
    // JSON-RPC notification (e.g., notifications/initialized)
    return null;
  }

  if (method === "initialize") {
    const protocolVersion =
      typeof params.protocolVersion === "string" && params.protocolVersion
        ? params.protocolVersion
        : "2024-11-05";
    return {
      jsonrpc: "2.0",
      id,
      result: {
        protocolVersion,
        capabilities: {
          tools: {},
        },
        serverInfo: SERVER_INFO,
      },
    };
  }

  if (method === "ping") {
    return {
      jsonrpc: "2.0",
      id,
      result: {},
    };
  }

  if (method === "tools/list") {
    return {
      jsonrpc: "2.0",
      id,
      result: {
        tools: TOOLS,
      },
    };
  }

  if (method === "tools/call") {
    const toolName = String(params.name ?? "");
    const toolArgs =
      params.arguments && typeof params.arguments === "object"
        ? params.arguments
        : {};
    const meta =
      params._meta && typeof params._meta === "object"
        ? params._meta
        : message._meta && typeof message._meta === "object"
          ? message._meta
          : {};
    const flowsDir = options.flowsDir || defaultFlowsDir();
    const at = typeof options.now === "function" ? options.now() : Date.now();

    if (toolName === "progress") {
      const {
        rootConversationId,
        callerConversationId,
        parentConversationId,
        agentName,
        rawMeta,
      } = extractConversationMeta(meta, options.brainRoots);
      const isMetaHelper =
        Boolean(parentConversationId) ||
        Boolean(agentName) ||
        (Boolean(callerConversationId) &&
          Boolean(rootConversationId) &&
          callerConversationId !== rootConversationId);
      if (isMetaHelper) {
        return {
          jsonrpc: "2.0",
          id,
          error: {
            code: -32602,
            message: "progress is for the lead only",
          },
        };
      }
      if (
        !callerConversationId ||
        !rootConversationId ||
        rootConversationId === "default" ||
        callerConversationId !== rootConversationId
      ) {
        return {
          jsonrpc: "2.0",
          id,
          error: {
            code: -32602,
            message: "progress is for the lead only: caller unknown",
          },
        };
      }
      const loaderOpts = {
        brainRoots: options.brainRoots,
        meta,
        conversationId: rootConversationId,
        parentConversationId,
      };
      const existingPath = join(flowsDir, `${rootConversationId}.jsonl`);
      const currentFlow =
        options.flow !== undefined
          ? options.flow
          : existsSync(existingPath)
            ? readFlowFromJsonlFile(existingPath, loaderOpts)
            : undefined;
      if (
        isKnownWorkerCaller(
          callerConversationId,
          currentFlow,
          flowsDir,
          options,
        )
      ) {
        return {
          jsonrpc: "2.0",
          id,
          error: {
            code: -32602,
            message: "progress is for the lead only",
          },
        };
      }
      const validationError = validateProgressArgs(toolArgs);
      if (validationError) {
        return {
          jsonrpc: "2.0",
          id,
          error: {
            code: -32602,
            message: validationError,
          },
        };
      }
      const events = mapProgressToEvents(
        toolArgs,
        at,
        rootConversationId,
        rawMeta,
        currentFlow,
      );
      const filePath =
        appendFlowEvents(flowsDir, rootConversationId, events) || existingPath;
      const flow = readFlowFromJsonlFile(filePath, loaderOpts);
      const text = formatFlowSummary(flow);
      return {
        jsonrpc: "2.0",
        id,
        result: {
          content: [{ type: "text", text }],
        },
      };
    }

    if (toolName === "step") {
      const { rootConversationId, parentConversationId } =
        extractConversationMeta(meta, options.brainRoots);
      if (!rootConversationId) {
        return {
          jsonrpc: "2.0",
          id,
          result: {
            content: [
              {
                type: "text",
                text: "step ignored: invalid conversation id",
              },
            ],
          },
        };
      }
      const loaderOpts = {
        brainRoots: options.brainRoots,
        meta,
        conversationId: rootConversationId,
        parentConversationId,
      };
      const filePath = join(flowsDir, `${rootConversationId}.jsonl`);
      const currentFlow =
        options.flow !== undefined
          ? options.flow
          : existsSync(filePath)
            ? readFlowFromJsonlFile(filePath, loaderOpts)
            : undefined;
      const mapped = mapStepToEvent(
        toolArgs,
        meta,
        at,
        currentFlow,
        options.brainRoots,
      );
      if (mapped.valid === false) {
        return {
          jsonrpc: "2.0",
          id,
          error: {
            code: -32602,
            message: mapped.error,
          },
        };
      }
      const toAppend =
        Array.isArray(mapped.events) && mapped.events.length > 0
          ? mapped.events
          : mapped.event
            ? [mapped.event]
            : [];
      if (mapped.matched && toAppend.length > 0) {
        appendFlowEvents(flowsDir, mapped.rootConversationId, toAppend);
      }
      return {
        jsonrpc: "2.0",
        id,
        result: {
          content: [{ type: "text", text: mapped.message }],
        },
      };
    }

    if (toolName === "post") {
      const { rootConversationId, parentConversationId } =
        extractConversationMeta(meta, options.brainRoots);
      if (!rootConversationId) {
        const chCheck = validatePostChannel(null, toolArgs.channel);
        if (!chCheck.ok) {
          return {
            jsonrpc: "2.0",
            id,
            error: {
              code: -32602,
              message: chCheck.error,
            },
          };
        }
        const rawText = typeof toolArgs.text === "string" ? toolArgs.text : "";
        if (rawText.trim().length > 0) {
          return {
            jsonrpc: "2.0",
            id,
            error: { code: -32602, message: NO_FLOW_POST },
          };
        }
        return {
          jsonrpc: "2.0",
          id,
          result: {
            content: [{ type: "text", text: JSON.stringify({ seq: 0 }) }],
          },
        };
      }
      const loaderOpts = {
        brainRoots: options.brainRoots,
        meta,
        conversationId: rootConversationId,
        parentConversationId,
      };
      const filePath = join(flowsDir, `${rootConversationId}.jsonl`);
      const currentFlow =
        options.flow !== undefined
          ? options.flow
          : existsSync(filePath)
            ? readFlowFromJsonlFile(filePath, loaderOpts)
            : undefined;
      const mapped = mapPostToEvent(
        toolArgs,
        meta,
        at,
        currentFlow,
        options.brainRoots,
      );
      if (!mapped.valid || !mapped.event) {
        if (mapped.error) {
          return {
            jsonrpc: "2.0",
            id,
            error: {
              code: -32602,
              message: mapped.error,
            },
          };
        }
        return {
          jsonrpc: "2.0",
          id,
          result: {
            content: [{ type: "text", text: JSON.stringify({ seq: 0 }) }],
          },
        };
      }
      // With no flow the reducer drops the post, so saving it would hand back
      // a number for a post the board never shows.
      if (!currentFlow) {
        return {
          jsonrpc: "2.0",
          id,
          error: { code: -32602, message: NO_FLOW_POST },
        };
      }
      const prevSeq =
        currentFlow.posts?.[currentFlow.posts.length - 1]?.seq ?? 0;
      appendFlowEvents(flowsDir, mapped.rootConversationId, [mapped.event]);
      const nextFlow = readFlowFromJsonlFile(filePath, loaderOpts);
      const seq = nextFlow?.posts?.[nextFlow.posts.length - 1]?.seq ?? 0;
      if (seq <= prevSeq) {
        return {
          jsonrpc: "2.0",
          id,
          error: {
            code: -32602,
            message: "the board did not accept this post, so it was not saved",
          },
        };
      }
      return {
        jsonrpc: "2.0",
        id,
        result: {
          content: [{ type: "text", text: JSON.stringify({ seq }) }],
        },
      };
    }

    if (toolName === "board") {
      const { rootConversationId, parentConversationId } =
        extractConversationMeta(meta, options.brainRoots);
      if (!rootConversationId) {
        return {
          jsonrpc: "2.0",
          id,
          error: { code: -32602, message: NO_FLOW_BOARD },
        };
      }
      const loaderOpts = {
        brainRoots: options.brainRoots,
        meta,
        conversationId: rootConversationId,
        parentConversationId,
      };
      const filePath = join(flowsDir, `${rootConversationId}.jsonl`);
      const currentFlow =
        options.flow !== undefined
          ? options.flow
          : existsSync(filePath)
            ? readFlowFromJsonlFile(filePath, loaderOpts)
            : null;
      if (!currentFlow) {
        return {
          jsonrpc: "2.0",
          id,
          error: { code: -32602, message: NO_FLOW_BOARD },
        };
      }
      const channelError = checkBoardChannel(currentFlow, toolArgs.channel);
      if (channelError) {
        return {
          jsonrpc: "2.0",
          id,
          error: { code: -32602, message: channelError },
        };
      }
      const rows = queryBoard(toolArgs, meta, currentFlow, options.brainRoots);
      return {
        jsonrpc: "2.0",
        id,
        result: {
          content: [{ type: "text", text: JSON.stringify(rows) }],
        },
      };
    }

    if (toolName === "channel") {
      const action =
        typeof toolArgs.action === "string" ? toolArgs.action.trim() : "";
      if (action !== "create" && action !== "archive" && action !== "list") {
        return {
          jsonrpc: "2.0",
          id,
          error: {
            code: -32602,
            message: 'channel action must be "create", "archive", or "list"',
          },
        };
      }

      const {
        rootConversationId,
        callerConversationId,
        parentConversationId,
        agentName,
        rawMeta,
      } = extractConversationMeta(meta, options.brainRoots);

      if (action === "list") {
        if (!rootConversationId) {
          return {
            jsonrpc: "2.0",
            id,
            result: {
              content: [
                { type: "text", text: JSON.stringify(channelsView(null)) },
              ],
            },
          };
        }
        const loaderOpts = {
          brainRoots: options.brainRoots,
          meta,
          conversationId: rootConversationId,
          parentConversationId,
        };
        const filePath = join(flowsDir, `${rootConversationId}.jsonl`);
        const currentFlow =
          options.flow !== undefined
            ? options.flow
            : existsSync(filePath)
              ? readFlowFromJsonlFile(filePath, loaderOpts)
              : null;
        return {
          jsonrpc: "2.0",
          id,
          result: {
            content: [
              {
                type: "text",
                text: JSON.stringify(channelsView(currentFlow)),
              },
            ],
          },
        };
      }

      const isMetaHelper =
        Boolean(parentConversationId) ||
        Boolean(agentName) ||
        (Boolean(callerConversationId) &&
          Boolean(rootConversationId) &&
          callerConversationId !== rootConversationId);
      if (isMetaHelper) {
        return {
          jsonrpc: "2.0",
          id,
          error: {
            code: -32602,
            message: `channel ${action} is for the lead only`,
          },
        };
      }
      if (
        !callerConversationId ||
        !rootConversationId ||
        rootConversationId === "default" ||
        callerConversationId !== rootConversationId
      ) {
        return {
          jsonrpc: "2.0",
          id,
          error: {
            code: -32602,
            message: `channel ${action} is for the lead only: caller unknown`,
          },
        };
      }

      const loaderOpts = {
        brainRoots: options.brainRoots,
        meta,
        conversationId: rootConversationId,
        parentConversationId,
      };
      const existingPath = join(flowsDir, `${rootConversationId}.jsonl`);
      const currentFlow =
        options.flow !== undefined
          ? options.flow
          : existsSync(existingPath)
            ? readFlowFromJsonlFile(existingPath, loaderOpts)
            : null;
      if (
        isKnownWorkerCaller(
          callerConversationId,
          currentFlow,
          flowsDir,
          options,
        )
      ) {
        return {
          jsonrpc: "2.0",
          id,
          error: {
            code: -32602,
            message: `channel ${action} is for the lead only`,
          },
        };
      }

      const check = validateChannelAction(currentFlow, {
        action,
        name: toolArgs.name,
      });
      if (!check.ok) {
        return {
          jsonrpc: "2.0",
          id,
          error: {
            code: -32602,
            message: check.error,
          },
        };
      }

      let nextFlow = currentFlow;
      if (!check.noop) {
        const metaFields = {
          rootConversationId,
          ...(rawMeta && Object.keys(rawMeta).length > 0
            ? { _meta: rawMeta }
            : {}),
        };
        const filePath =
          appendFlowEvents(flowsDir, rootConversationId, [
            {
              type: "channel",
              at,
              ...metaFields,
              action,
              name: check.name,
            },
          ]) || existingPath;
        nextFlow = readFlowFromJsonlFile(filePath, loaderOpts);
      }

      return {
        jsonrpc: "2.0",
        id,
        result: {
          content: [
            { type: "text", text: JSON.stringify(channelsView(nextFlow)) },
          ],
        },
      };
    }

    if (toolName === "team") {
      const hasRoot =
        toolArgs &&
        typeof toolArgs === "object" &&
        Object.prototype.hasOwnProperty.call(toolArgs, "root") &&
        toolArgs.root !== undefined;
      const defaults = options.teamDefaults ?? TIER_DEFAULTS;
      let teamResult;
      if (hasRoot) {
        const rootCheck = validateExplicitRoot(toolArgs.root);
        if (!rootCheck.ok) {
          return {
            jsonrpc: "2.0",
            id,
            error: {
              code: -32602,
              message: rootCheck.error,
            },
          };
        }
        teamResult = readTeamConfigAtRoot(rootCheck.root, defaults);
      } else {
        const workspaceRoot = resolveWorkspaceRoot(meta, options);
        teamResult = readTeamConfig(workspaceRoot, defaults);
      }

      const roleMap = agentRoleMap(teamResult);
      const roles = Object.entries(roleMap).map(([agent, role]) => ({
        agent,
        role,
      }));
      const teamCheck = validateTeamEvent({ roles });
      const { rootConversationId, parentConversationId, rawMeta } =
        extractConversationMeta(meta, options.brainRoots);
      if (
        teamCheck.ok &&
        flowsDir &&
        rootConversationId &&
        rootConversationId !== "default" &&
        !parentConversationId
      ) {
        const metaFields = {
          rootConversationId,
          ...(rawMeta && Object.keys(rawMeta).length > 0
            ? { _meta: rawMeta }
            : {}),
        };
        appendFlowEvents(flowsDir, rootConversationId, [
          {
            type: "team",
            at,
            ...metaFields,
            roles: teamCheck.roles,
          },
        ]);
      }

      return {
        jsonrpc: "2.0",
        id,
        result: {
          content: [{ type: "text", text: JSON.stringify(teamResult) }],
        },
      };
    }

    if (toolName === "team_setup") {
      const setupRes = runTeamSetup(toolArgs, {
        cwd: options.cwd,
        workspaceUri: options.workspaceUri,
        flowsDir: options.flowsDir,
        brainRoots: options.brainRoots,
        pluginAgentsDir: options.pluginAgentsDir,
        meta,
      });
      if (!setupRes.ok) {
        return {
          jsonrpc: "2.0",
          id,
          error: {
            code: -32602,
            message: setupRes.error,
          },
        };
      }
      return {
        jsonrpc: "2.0",
        id,
        result: {
          content: [{ type: "text", text: JSON.stringify(setupRes.result) }],
        },
      };
    }

    return {
      jsonrpc: "2.0",
      id,
      error: {
        code: -32601,
        message: `Unknown tool: ${toolName}`,
      },
    };
  }

  return {
    jsonrpc: "2.0",
    id,
    error: {
      code: -32601,
      message: `Method not found: ${method}`,
    },
  };
}

/**
 * Parses incoming stdio data supporting both newline-delimited JSON (MCP standard)
 * and Content-Length header framing, rejecting frames larger than `MAX_STDIO_FRAME_BYTES` (256 KB).
 *
 * @param {string} buffer
 * @returns {{ messages: any[], errors: any[], rest: string, mode: "ndjson" | "content-length", discardUntilNewline?: boolean }}
 */
export function parseJsonRpcFrames(buffer) {
  let rest = String(buffer ?? "");
  const messages = [];
  const errors = [];
  let mode = "ndjson";
  let discardUntilNewline = false;

  const makeOversizedError = () => ({
    jsonrpc: "2.0",
    id: null,
    error: {
      code: -32600,
      message: `Frame exceeds maximum size of ${MAX_STDIO_FRAME_BYTES} bytes`,
    },
  });

  while (rest.length > 0) {
    const leadingTrimmed = rest.replace(/^[ \t\r\n]+/, "");
    if (!leadingTrimmed) {
      rest = "";
      break;
    }

    if (/^Content-Length:/i.test(leadingTrimmed)) {
      mode = "content-length";
      rest = leadingTrimmed;
      const sepMatch = /\r?\n\r?\n/.exec(rest);
      if (!sepMatch) {
        if (Buffer.byteLength(rest, "utf8") > MAX_STDIO_FRAME_BYTES) {
          errors.push(makeOversizedError());
          rest = "";
        }
        break;
      }
      const headerBlock = rest.slice(0, sepMatch.index);
      const lenMatch = /Content-Length:\s*(\d+)/i.exec(headerBlock);
      if (!lenMatch) {
        rest = rest.slice(sepMatch.index + sepMatch[0].length);
        continue;
      }
      const byteLength = Number(lenMatch[1]);
      const bodyStart = sepMatch.index + sepMatch[0].length;
      const bodyBuf = Buffer.from(rest, "utf8");
      const headerByteLen = Buffer.byteLength(rest.slice(0, bodyStart), "utf8");
      if (
        !Number.isFinite(byteLength) ||
        byteLength > MAX_STDIO_FRAME_BYTES ||
        headerByteLen > MAX_STDIO_FRAME_BYTES
      ) {
        errors.push(makeOversizedError());
        if (
          Number.isFinite(byteLength) &&
          bodyBuf.length >= headerByteLen + byteLength
        ) {
          rest = bodyBuf.subarray(headerByteLen + byteLength).toString("utf8");
          continue;
        }
        rest = "";
        break;
      }
      if (bodyBuf.length < headerByteLen + byteLength) {
        break;
      }
      const jsonText = bodyBuf
        .subarray(headerByteLen, headerByteLen + byteLength)
        .toString("utf8");
      rest = bodyBuf.subarray(headerByteLen + byteLength).toString("utf8");
      try {
        messages.push(JSON.parse(jsonText));
      } catch {
        // Ignore malformed frame payload.
      }
      continue;
    }

    const newlineIdx = rest.indexOf("\n");
    if (newlineIdx === -1) {
      if (Buffer.byteLength(rest, "utf8") > MAX_STDIO_FRAME_BYTES) {
        errors.push(makeOversizedError());
        rest = "";
        discardUntilNewline = true;
      }
      break;
    }
    const rawLine = rest.slice(0, newlineIdx);
    rest = rest.slice(newlineIdx + 1);
    if (Buffer.byteLength(rawLine, "utf8") > MAX_STDIO_FRAME_BYTES) {
      errors.push(makeOversizedError());
      continue;
    }
    const line = rawLine.trim();
    if (!line) continue;
    try {
      messages.push(JSON.parse(line));
    } catch {
      // Ignore malformed JSON line.
    }
  }

  return { messages, errors, rest, mode, discardUntilNewline };
}

/**
 * Formats a JSON-RPC response object for stdio output.
 *
 * @param {Record<string, any>} message
 * @param {"ndjson" | "content-length"} [mode]
 */
export function formatJsonRpcFrame(message, mode = "ndjson") {
  const json = JSON.stringify(message);
  if (mode === "content-length") {
    const byteLength = Buffer.byteLength(json, "utf8");
    return `Content-Length: ${byteLength}\r\n\r\n${json}`;
  }
  return `${json}\n`;
}

export function startStdioServer(options = {}) {
  let buffer = "";
  let discardUntilNewline = false;
  process.stdin.setEncoding("utf8");
  process.stdin.on("data", (chunk) => {
    let incoming = String(chunk ?? "");
    if (discardUntilNewline) {
      const nl = incoming.indexOf("\n");
      if (nl === -1) {
        return;
      }
      incoming = incoming.slice(nl + 1);
      discardUntilNewline = false;
    }
    buffer += incoming;
    const parsed = parseJsonRpcFrames(buffer);
    buffer = parsed.rest;
    if (parsed.discardUntilNewline) {
      discardUntilNewline = true;
    }
    for (const errResp of parsed.errors) {
      process.stdout.write(formatJsonRpcFrame(errResp, parsed.mode));
    }
    for (const msg of parsed.messages) {
      const response = handleJsonRpcMessage(msg, options);
      if (response) {
        process.stdout.write(formatJsonRpcFrame(response, parsed.mode));
      }
    }
  });
}

function isMainModule() {
  try {
    if (!process.argv[1]) return false;
    return (
      realpathSync(process.argv[1]) ===
      realpathSync(fileURLToPath(import.meta.url))
    );
  } catch {
    return false;
  }
}

if (isMainModule()) {
  startStdioServer();
}
