#!/bin/sh
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# Antigravity runs this on PreToolUse (edit_file|write_file|run_command) and
# Stop (see ../hooks.json). It scans incoming file edits and shell commands for
# dangerous constructs and hardcoded secrets using sidecars/panel/lib/core.mjs,
# records audit findings for the Security Guidance sidecar panel, and emits a
# permissionDecision when critical/high findings are detected.

payload=$(cat)
if [ -z "$payload" ]; then
	printf '{}'
	exit 0
fi

HERE="$(cd "$(dirname "$0")" && pwd)"
CORE_MJS="${HERE}/../sidecars/panel/lib/core.mjs"

if ! command -v node >/dev/null 2>&1 || [ ! -f "$CORE_MJS" ]; then
	printf '{}'
	exit 0
fi

SEC_PAYLOAD="$payload" SEC_CORE="$CORE_MJS" node --input-type=module -e '
import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

try {
  const core = await import(pathToFileURL(process.env.SEC_CORE).href);
  const payload = JSON.parse(process.env.SEC_PAYLOAD || "{}");
  const appDir = process.env.ANTIGRAVITY_APP_DATA_DIR || join(homedir(), ".gemini", "antigravity");
  const stateFile = join(appDir, "security-guidance-state.json");

  let store = { findings: [], suppressions: [] };
  if (existsSync(stateFile)) {
    try {
      const parsed = JSON.parse(readFileSync(stateFile, "utf8"));
      if (parsed && typeof parsed === "object") {
        store = {
          findings: Array.isArray(parsed.findings) ? parsed.findings : [],
          suppressions: Array.isArray(parsed.suppressions) ? parsed.suppressions : [],
        };
      }
    } catch {}
  }

  const isStop =
    payload?.hook_event_name === "Stop" ||
    payload?.event === "Stop" ||
    (!payload?.toolCall && !payload?.tool_name && ("stop_hook_active" in payload || "reason" in payload));

  if (isStop) {
    process.stdout.write("{}");
    process.exit(0);
  }

  const args = payload?.toolCall?.args || payload?.tool_input || {};
  const toolName = payload?.toolCall?.name || payload?.tool_name || "unknown";
  const filePath = String(args.Path || args.file_path || (toolName === "run_command" ? "<shell>" : "<unknown>"));
  const content = String(args.Content ?? args.Replacement ?? args.new_string ?? args.CommandLine ?? args.command ?? "");

  const rawFindings = core.scanContentForPatterns(content, { filePath });
  const activeFindings = core.filterSuppressedFindings(rawFindings, store.suppressions);

  if (activeFindings.length === 0) {
    process.stdout.write("{}");
    process.exit(0);
  }

  const now = Date.now();
  const recorded = activeFindings.map((f) => ({
    ...f,
    id: f.id || `${f.ruleId}:${filePath}:${f.line}`,
    conversationId: payload?.conversationId || "",
    tool: toolName,
    timestamp: now,
  }));

  try {
    mkdirSync(appDir, { recursive: true });
    const byId = new Map();
    for (const item of [...recorded, ...store.findings]) {
      if (item && item.id && !byId.has(item.id)) byId.set(item.id, item);
    }
    store.findings = [...byId.values()].slice(0, 200);
    const tmp = `${stateFile}.tmp`;
    writeFileSync(tmp, JSON.stringify(store, null, 2) + "\n", "utf8");
    renameSync(tmp, stateFile);
  } catch {}

  const hasCritical = activeFindings.some((f) => f.severity === "critical");
  const decision = hasCritical ? "deny" : "ask";
  const reason = activeFindings
    .map((f) => `[${f.severity.toUpperCase()} ${f.ruleId}] (${f.cwe}) line ${f.line}: ${f.message} — Remediation: ${f.remediation}`)
    .join("\n\n");

  process.stdout.write(
    JSON.stringify({
      permissionDecision: decision,
      permissionDecisionReason: reason,
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: decision,
        permissionDecisionReason: reason,
      },
    }),
  );
} catch {
  process.stdout.write("{}");
}
' 2>/dev/null || printf '{}'

exit 0
