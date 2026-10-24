#!/bin/sh
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# Antigravity runs this on Stop (see ../hooks.json). It reads the active loop
# state from ~/.gemini/antigravity/ralph-loop-state/<conversationId>.json.
# When active, iteration < maxIterations, and the last assistant message in
# transcriptPath does not contain <promise>${completionPromise}</promise>, it
# increments iteration and outputs:
#   {"decision": "continue", "reason": "Ralph Loop (iteration N/M): continue working on the task until completion criteria are met and emit <promise>...</promise>."}
# Otherwise it outputs {}.

payload=$(cat)

node -e '
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

function done(obj = {}) {
  process.stdout.write(JSON.stringify(obj));
  process.exit(0);
}

let event;
try {
  event = JSON.parse(process.argv[1] || "{}");
} catch {
  done({});
}

const convId = String(event.conversationId || event.session_id || "").trim();
if (!convId || /[/\\]/.test(convId)) done({});

const stateDir = path.join(
  process.env.ANTIGRAVITY_APP_DATA_DIR || path.join(os.homedir(), ".gemini", "antigravity"),
  "ralph-loop-state"
);
const stateFile = path.join(stateDir, `${convId}.json`);
if (!fs.existsSync(stateFile)) done({});

let state;
try {
  state = JSON.parse(fs.readFileSync(stateFile, "utf8"));
} catch {
  done({});
}

if (!state || state.active !== true) done({});

const promiseText = String(state.completionPromise || "DONE").trim();
const tag = `<promise>${promiseText}</promise>`;

let lastAssistantText = String(event.lastAssistantMessage || event.response || "");
const transcriptPath = event.transcriptPath || event.transcript_path;
if (transcriptPath && typeof transcriptPath === "string" && fs.existsSync(transcriptPath)) {
  try {
    const lines = fs.readFileSync(transcriptPath, "utf8").trim().split("\n");
    for (let i = lines.length - 1; i >= 0; i--) {
      try {
        const entry = JSON.parse(lines[i]);
        const role = entry.role || entry.type || entry.source;
        if (
          role === "assistant" ||
          role === "MODEL" ||
          role === "PLANNER_RESPONSE"
        ) {
          lastAssistantText =
            typeof entry.content === "string"
              ? entry.content
              : JSON.stringify(entry);
          break;
        }
      } catch {
        continue;
      }
    }
  } catch {
    // Fall back to lastAssistantText
  }
}

function saveState(next) {
  try {
    const tmp = `${stateFile}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify(next, null, 2), "utf8");
    fs.renameSync(tmp, stateFile);
  } catch {
    // Ignore write failure in hook
  }
}

if (lastAssistantText.includes(tag)) {
  saveState({
    ...state,
    active: false,
    status: "completed",
    completedAt: Date.now(),
    updatedAt: Date.now(),
  });
  done({});
}

const iteration = Number(state.iteration) || 0;
const maxIterations = Number(state.maxIterations) || 10;

if (iteration >= maxIterations) {
  saveState({
    ...state,
    active: false,
    status: "max_iterations",
    completedAt: Date.now(),
    updatedAt: Date.now(),
  });
  done({});
}

const nextIteration = iteration + 1;
saveState({
  ...state,
  iteration: nextIteration,
  status: "running",
  updatedAt: Date.now(),
});

const taskHint = state.prompt ? ` Task: ${state.prompt}` : "";
done({
  decision: "continue",
  reason: `Ralph Loop (iteration ${nextIteration}/${maxIterations}): continue working on the task until completion criteria are met and emit <promise>${promiseText}</promise>.${taskHint}`,
});
' "$payload" 2>/dev/null || printf '{}'
exit 0
