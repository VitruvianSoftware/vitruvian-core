#!/bin/sh
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# Antigravity runs this on PreToolUse and Stop (see ../hooks.json).
# It loads declarative rules from .agents/hookify.*.md in the workspace and
# ~/.gemini/antigravity/hookify-rules.json, evaluates them against the hook
# payload using sidecars/panel/lib/core.mjs, records audit events, and prints
# the JSON decision to stdout.

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

HOOKIFY_PAYLOAD="$payload" HOOKIFY_CORE="$CORE_MJS" node --input-type=module -e '
import { existsSync, mkdirSync, readdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

try {
  const core = await import(pathToFileURL(process.env.HOOKIFY_CORE).href);
  const payload = JSON.parse(process.env.HOOKIFY_PAYLOAD || "{}");
  const appDir = process.env.ANTIGRAVITY_APP_DATA_DIR || join(homedir(), ".gemini", "antigravity");
  const globalRulesFile = join(appDir, "hookify-rules.json");
  const eventsFile = join(appDir, "hookify-events.json");

  const rules = [];
  if (existsSync(globalRulesFile)) {
    try {
      const parsed = JSON.parse(readFileSync(globalRulesFile, "utf8"));
      const list = Array.isArray(parsed) ? parsed : Array.isArray(parsed?.rules) ? parsed.rules : [];
      rules.push(...list);
    } catch {}
  }

  const cwd = payload?.toolCall?.args?.Cwd || payload?.cwd || process.cwd();
  const agentsDir = join(cwd, ".agents");
  if (existsSync(agentsDir)) {
    try {
      for (const name of readdirSync(agentsDir).sort()) {
        if (/^hookify\..+\.md$/.test(name)) {
          const full = join(agentsDir, name);
          const rule = core.parseHookifyMarkdown(readFileSync(full, "utf8"), full);
          if (rule) rules.push(rule);
        }
      }
    } catch {}
  }

  const isStop =
    payload?.hook_event_name === "Stop" ||
    payload?.event === "Stop" ||
    (!payload?.toolCall && !payload?.tool_name && ("stop_hook_active" in payload || "reason" in payload));

  const res = isStop
    ? core.evaluateStop(rules, payload)
    : core.evaluatePreToolUse(rules, payload);

  if (res.matchedRules && res.matchedRules.length > 0) {
    try {
      mkdirSync(appDir, { recursive: true });
      let existing = [];
      if (existsSync(eventsFile)) {
        existing = JSON.parse(readFileSync(eventsFile, "utf8")) || [];
      }
      const next = [
        {
          id: `${Date.now()}-${Math.random().toString(36).slice(2, 7)}`,
          timestamp: Date.now(),
          event: isStop ? "Stop" : "PreToolUse",
          tool: payload?.toolCall?.name || payload?.tool_name || (isStop ? "Stop" : "unknown"),
          decision: isStop ? (res.continue === false ? "deny" : "warn") : res.decision,
          rules: res.matchedRules.map((r) => r.ruleName || r.ruleId),
          reason: res.reason || res.stopReason || res.systemMessage || "",
        },
        ...(Array.isArray(existing) ? existing : []),
      ].slice(0, 100);
      const tmp = `${eventsFile}.tmp`;
      writeFileSync(tmp, JSON.stringify(next, null, 2), "utf8");
      renameSync(tmp, eventsFile);
    } catch {}
  }

  process.stdout.write(JSON.stringify(res.hookOutput ?? {}));
} catch {
  process.stdout.write("{}");
}
' 2>/dev/null || printf '{}'

exit 0
