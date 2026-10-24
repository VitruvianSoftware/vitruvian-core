---
name: hookify
description: Author, test, and manage declarative Hookify rules (.agents/hookify.*.md and ~/.gemini/antigravity/hookify-rules.json) for PreToolUse permission gating, argument rewriting, and Stop assertions.
---

# Hookify Rule Authoring Skill

Use this skill when the user asks to create, edit, debug, or inspect Hookify
guardrail rules that intercept `PreToolUse` or `Stop` events in Antigravity.

## Rule Locations

1. **Repository-scoped Markdown rules:** `.agents/hookify.<slug>.md`
   - Committed or stored in the workspace `.agents/` directory.
   - Best for repo-specific conventions (e.g., use `bazel test` instead of raw
     `go test`, forbid editing generated files).
2. **User-global JSON rules:** `~/.gemini/antigravity/hookify-rules.json`
   - Managed from the Hookify sidecar panel or edited directly as `{ "rules": [...] }`.

## Markdown Rule Schema

Each `.agents/hookify.<slug>.md` file has YAML frontmatter followed by the
Markdown message shown when the rule triggers:

```markdown
---
name: prefer-bazel-test
enabled: true
event: bash
tool: run_command
action: block
conditions:
  - field: CommandLine
    operator: regex_match
    pattern: "^\\s*(go|cargo|pnpm)\\s+test\\b"
---
Use `bazel test //...` instead of invoking language test runners directly.
```

### Frontmatter Fields

- `name` (string, required): Unique identifier for the rule.
- `enabled` (boolean, default `true`): Whether the rule is active.
- `event` (string, default `"all"`):
  - `"PreToolUse"` or `"all"`: Runs before any matching tool call.
  - `"bash"`: Shorthand for `PreToolUse` on `run_command` / `Bash`.
  - `"file"`: Shorthand for `PreToolUse` on `write_file` / `edit_file` / `Write` / `Edit`.
  - `"Stop"`: Runs when the agent attempts to conclude its turn.
- `tool` / `matcher` (string, optional): Regex or pipe-separated tool names
  (e.g. `"run_command"`, `"edit_file|write_file"`, `"*"`).
- `action` (string, default `"warn"`):
  - `"allow"`: Explicitly allow the tool call.
  - `"warn"` / `"ask"`: Ask the user for confirmation with the Markdown message.
  - `"force_ask"`: Force user confirmation even in auto-approve modes.
  - `"block"` / `"deny"`: Reject the tool call (or prevent stopping on `Stop`).
  - `"overwrite"`: Rewrite tool input fields via `overwrite` rules before execution.
- `pattern` (string, optional): Shorthand regex matched against the primary
  field (`CommandLine` for bash, `Content`/`Replacement` for file edits).
- `conditions` (array, optional): All listed conditions must match (logical AND):
  - `field`: `"CommandLine"`, `"Path"`, `"Content"`, `"Replacement"`, `"Target"`,
    `"reason"`, or any key inside `toolCall.args`.
  - `operator`: `"regex_match"`, `"contains"`, `"not_contains"`, `"equals"`,
    `"starts_with"`, or `"ends_with"`.
  - `pattern`: String or regular expression pattern to compare against.
- `overwrite` (object, optional, used when `action: overwrite`):
  - Map of field replacements or `{ field, find, replace }` to rewrite tool arguments.
