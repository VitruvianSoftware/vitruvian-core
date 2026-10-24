#!/bin/sh
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# Stop hook: inspects the assistant response at the end of a turn against the
# active response contract, logs the verdict to verdicts.jsonl, and in "enforce"
# mode bounces once (decision: "continue") when an empty filler closing line is
# detected.

payload=$(cat)
state_dir="${ANTIGRAVITY_APP_DATA_DIR:-$HOME/.gemini/antigravity}/live-context-state"

if command -v node >/dev/null 2>&1; then
	printf '%s' "$payload" | node -e '
    import("node:fs").then(async ({ appendFileSync, existsSync, mkdirSync, readFileSync }) => {
      const { join } = await import("node:path");
      const { evaluateStopShape } = await import("./sidecars/panel/lib/core.mjs");
      const dir = process.env.STATE_DIR || "";
      let ev = {};
      try {
        ev = JSON.parse(readFileSync(0, "utf8"));
      } catch {
        process.stdout.write(JSON.stringify({ decision: "allow" }));
        return;
      }
      let settings = { mode: "log" };
      try {
        const sp = join(dir, "settings.json");
        if (existsSync(sp)) settings = JSON.parse(readFileSync(sp, "utf8"));
      } catch {}

      let lastAssistantMessage = String(ev.lastAssistantMessage ?? "");
      if (!lastAssistantMessage && ev.transcriptPath && existsSync(ev.transcriptPath)) {
        try {
          const lines = readFileSync(ev.transcriptPath, "utf8").trim().split(/\r?\n/);
          for (let i = lines.length - 1; i >= 0; i--) {
            const step = JSON.parse(lines[i]);
            if (String(step.type ?? "").toUpperCase() === "PLANNER_RESPONSE" && step.content) {
              lastAssistantMessage = String(step.content);
              break;
            }
          }
        } catch {}
      }

      const result = evaluateStopShape(
        { ...ev, lastAssistantMessage },
        { mode: settings.mode || "log", minChars: settings.minChars },
      );

      if (result.logRecord && dir) {
        try {
          mkdirSync(dir, { recursive: true });
          appendFileSync(join(dir, "verdicts.jsonl"), JSON.stringify(result.logRecord) + "\n", "utf8");
        } catch {}
      }
      process.stdout.write(JSON.stringify(result.output));
    }).catch(() => {
      process.stdout.write(JSON.stringify({ decision: "allow" }));
    });
  ' STATE_DIR="$state_dir" 2>/dev/null || printf '{"decision":"allow"}'
else
	printf '{"decision":"allow"}'
fi
exit 0
