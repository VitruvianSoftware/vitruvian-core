#!/bin/sh
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# PreInvocation hook: reads the cached Git/GitHub snapshot and response contract
# from ~/.gemini/antigravity/live-context-state and outputs an Antigravity
# PreInvocation payload: {"injectSteps":[{"ephemeralMessage":"..."}]}.
#
# Always exits 0 and emits valid JSON so a missing cache or tool never breaks
# the user's prompt.

payload=$(cat)
state_dir="${ANTIGRAVITY_APP_DATA_DIR:-$HOME/.gemini/antigravity}/live-context-state"

if command -v node >/dev/null 2>&1; then
	printf '%s' "$payload" | node -e '
    import("node:fs").then(async ({ existsSync, readFileSync }) => {
      const { join } = await import("node:path");
      const { buildEphemeralContextPayload } = await import("./sidecars/panel/lib/core.mjs");
      const dir = process.env.STATE_DIR || "";
      const readJson = (name, fallback) => {
        try {
          const p = join(dir, name);
          return existsSync(p) ? JSON.parse(readFileSync(p, "utf8")) : fallback;
        } catch {
          return fallback;
        }
      };
      const settings = readJson("settings.json", {});
      const snapshot = readJson("snapshot.json", {});
      const out = buildEphemeralContextPayload({
        git: snapshot.git,
        github: snapshot.github,
        settings,
      });
      process.stdout.write(JSON.stringify(out));
    }).catch(() => {
      process.stdout.write("{}");
    });
  ' STATE_DIR="$state_dir" 2>/dev/null || printf '{}'
else
	printf '{}'
fi
exit 0
