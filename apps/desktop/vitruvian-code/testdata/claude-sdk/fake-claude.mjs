// A stand-in for the user's `claude`, for the tests that run the real bundled Claude helper.
//
// It speaks the part of Claude Code's stream-json protocol the Agent SDK uses: `--version`, then
// newline-delimited JSON on standard input and output. The SDK sends `control_request`s
// (`initialize`, `interrupt`, ...) and `user` messages; this answers the first kind and replays,
// for each `user` message, the next turn of a recorded script.
//
// It is run by the bundled Node through a one-line wrapper script the test writes (the SDK
// starts a path that does not end in .js directly, so `claude` has to be an executable).
//
// Settings come from the environment the wrapper exports:
//   FAKE_CLAUDE_VERSION       the version `--version` prints (default 2.1.400)
//   FAKE_CLAUDE_VERSION_MODE  ok (default), garbage (prints no version) or fail (exits 1)
//   FAKE_CLAUDE_SCRIPT        path of the script: {"turns": [{"steps": [...]}]}
//   FAKE_CLAUDE_LOG           path of a JSON-lines file that records what the process saw
//   FAKE_CLAUDE_RECORD_ENV    comma-separated environment names whose values are logged
//   FAKE_CLAUDE_IGNORE_TERM   1 to ignore SIGTERM, so only SIGKILL ends it
//
// Script steps (every string may hold ${SESSION_ID}):
//   {"emit": {...}}                         write one JSON line
//   {"can_use_tool": {...}, "branches": {"allow": [...], "deny": [...]}}
//                                           ask the SDK, then run the branch the answer picks
//   {"wait_interrupt": true, "then": [...]} wait for an `interrupt`, then run `then`
//   {"sleep_ms": 50}                        wait
//   {"hang": true}                          never finish this turn
import { appendFileSync, readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { createInterface } from "node:readline";

const args = process.argv.slice(2);
const version = process.env.FAKE_CLAUDE_VERSION || "2.1.400";
const logPath = process.env.FAKE_CLAUDE_LOG;

function log(entry) {
  if (!logPath) return;
  appendFileSync(logPath, JSON.stringify(entry) + "\n");
}

if (args.includes("--version")) {
  const mode = process.env.FAKE_CLAUDE_VERSION_MODE || "ok";
  if (mode === "fail") {
    process.stderr.write("fake claude: cannot report a version\n");
    process.exit(1);
  }
  process.stdout.write(
    mode === "garbage" ? "no version here\n" : `${version} (Claude Code)\n`,
  );
  process.exit(0);
}

if (process.env.FAKE_CLAUDE_IGNORE_TERM === "1") {
  process.on("SIGTERM", () => {});
}

// The SDK writes `--name=value`; `--name value` is read too.
function flag(name) {
  const joined = args.find((arg) => arg.startsWith(`${name}=`));
  if (joined) return joined.slice(name.length + 1);
  const index = args.indexOf(name);
  return index >= 0 ? args[index + 1] : undefined;
}

const sessionId =
  flag("--session-id") ||
  flag("--resume") ||
  "00000000-0000-4000-8000-000000000000";

function psText(extraFlags) {
  try {
    return execFileSync(
      "ps",
      [...extraFlags, "-o", "command=", "-p", String(process.ppid)],
      {
        encoding: "utf8",
      },
    );
  } catch {
    return "";
  }
}

const recordedEnv = {};
for (const name of (process.env.FAKE_CLAUDE_RECORD_ENV || "")
  .split(",")
  .filter(Boolean)) {
  recordedEnv[name] = process.env[name] ?? null;
}
log({
  kind: "start",
  args,
  pid: process.pid,
  ppid: process.ppid,
  env: recordedEnv,
  parentCommand: psText(["-ww"]),
  parentEnvironment: psText(["-E", "-ww"]),
});

const script = process.env.FAKE_CLAUDE_SCRIPT
  ? JSON.parse(readFileSync(process.env.FAKE_CLAUDE_SCRIPT, "utf8"))
  : { turns: [] };
let turnIndex = 0;

function fill(value) {
  if (typeof value === "string")
    return value.replaceAll("${SESSION_ID}", sessionId);
  if (Array.isArray(value)) return value.map(fill);
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([k, v]) => [k, fill(v)]),
    );
  }
  return value;
}

function send(message) {
  process.stdout.write(JSON.stringify(fill(message)) + "\n");
}

const waiters = new Map(); // request_id -> resolve
let interruptWaiters = [];
let interrupted = false;
let turnQueue = Promise.resolve();

function respond(requestId, response) {
  send({
    type: "control_response",
    response: { subtype: "success", request_id: requestId, response },
  });
}

function handleControlRequest(message) {
  const request = message.request || {};
  log({ kind: "control_request", subtype: request.subtype });
  if (request.subtype === "initialize") {
    log({ kind: "initialize", mcpServers: request.mcpServers ?? null });
    respond(message.request_id, {
      commands: [
        {
          name: "compact",
          description: "Compact conversation history",
          argumentHint: "",
        },
      ],
      output_style: "default",
      available_output_styles: ["default"],
      models: [
        {
          value: "claude-sonnet-5-5",
          displayName: "Claude Sonnet 5.5",
          description: "Fake model",
        },
      ],
      account: {},
      claude_code_version: version,
      mcp_servers_applied: true,
    });
    return;
  }
  if (request.subtype === "interrupt") {
    interrupted = true;
    respond(message.request_id, {});
    const pending = interruptWaiters;
    interruptWaiters = [];
    for (const resolve of pending) resolve();
    return;
  }
  if (request.subtype === "mcp_status") {
    respond(message.request_id, {
      mcpServers: [
        {
          name: "local-docs",
          status: "connected",
          serverInfo: { name: "docs-mcp", version: "1.2.0" },
          scope: "dynamic",
          tools: [
            {
              name: "search_docs",
              description: "Search project markdown docs.",
            },
          ],
        },
        { name: "remote-mcp", status: "failed", error: "Connection refused" },
      ],
    });
    return;
  }
  respond(message.request_id, {});
}

let nextRequest = 1;
async function runSteps(steps) {
  for (const step of steps || []) {
    if (step.emit) {
      send(step.emit);
    } else if (step.can_use_tool) {
      const requestId = `fake_req_${nextRequest++}`;
      send({
        type: "control_request",
        request_id: requestId,
        request: { subtype: "can_use_tool", ...step.can_use_tool },
      });
      const response = await new Promise((resolve) =>
        waiters.set(requestId, resolve),
      );
      log({
        kind: "can_use_tool_answer",
        tool_name: step.can_use_tool.tool_name,
        response,
      });
      const behavior =
        response?.response?.behavior === "allow" ? "allow" : "deny";
      await runSteps((step.branches || {})[behavior]);
    } else if (step.wait_interrupt) {
      if (!interrupted)
        await new Promise((resolve) => interruptWaiters.push(resolve));
      interrupted = false;
      await runSteps(step.then);
    } else if (step.sleep_ms) {
      await new Promise((resolve) => setTimeout(resolve, step.sleep_ms));
    } else if (step.hang) {
      await new Promise(() => {});
    }
  }
}

function startTurn(message) {
  const turn = script.turns[Math.min(turnIndex, script.turns.length - 1)];
  turnIndex += 1;
  log({ kind: "user_message", content: message.message?.content });
  turnQueue = turnQueue.then(() => runSteps(turn ? turn.steps : []));
}

const lines = createInterface({ input: process.stdin });
lines.on("line", (line) => {
  if (!line.trim()) return;
  let message;
  try {
    message = JSON.parse(line);
  } catch {
    return;
  }
  if (message.type === "control_request") {
    handleControlRequest(message);
  } else if (message.type === "control_response") {
    const id = message.response?.request_id;
    const resolve = waiters.get(id);
    if (resolve) {
      waiters.delete(id);
      resolve(message.response);
    }
  } else if (message.type === "user") {
    startTurn(message);
  }
});
lines.on("close", () => process.exit(0));
