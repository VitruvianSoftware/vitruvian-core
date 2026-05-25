# TODO: Gemini CLI Hooks — Live Streaming

**Tag for search:** `TODO_GEMINI_HOOKS`

```
git grep TODO_GEMINI_HOOKS
```

## Background

We implemented a hooks-based live streaming feature to show real-time output
(token chunks, tool activity) while Gemini is processing a prompt in the Quick
Prompt chat view. The full implementation is in place, but it requires Gemini
CLI hooks support which is **not yet available** in any published release.

- **Implemented as of:** gemini v0.35.1
- **Hooks available in:** upstream `main` branch only (not published to npm)

## What We Built

| File | Role |
|------|------|
| `hooks/stream-hook.py` | Hook script — writes JSONL events to `GEMINI_STREAM_FILE` |
| `~/.gemini/settings.json` | Hook registration for `AfterModel`, `BeforeTool`, `AfterTool`, `AfterAgent` |
| `~/.gemini/hooks/stream-hook.py` | Installed copy of the hook script |
| `macos/Sources/NexusAgent/QuickPromptWindow.swift` | `StreamFileWatcher` class + streaming `sendToCLI()` |

## How It Works (When Hooks Are Available)

1. `sendToCLI()` creates `/tmp/gemini-stream-{uuid}.jsonl` and sets `GEMINI_STREAM_FILE` in the CLI's environment
2. `StreamFileWatcher` monitors the file via `DispatchSource.makeFileSystemObjectSource(.write)`
3. Gemini CLI fires hooks during execution:
   - `AfterModel` → hook writes `{"type":"chunk","text":"..."}` per streaming token
   - `BeforeTool` → hook writes `{"type":"tool_start","tool":"...","summary":"..."}`
   - `AfterTool` → hook writes `{"type":"tool_done","tool":"..."}`
   - `AfterAgent` → hook writes `{"type":"done","response":"..."}`
4. Swift app reads new JSONL lines and updates the chat view in real-time

## Verification Steps (Once New Release Is Out)

1. **Upgrade gemini:** `brew upgrade gemini` and confirm `gemini --version` shows a version later than `0.35.1`

2. **Check hooks are supported:**
   ```bash
   gemini hooks --help
   # Should list more than just "migrate"
   ```

3. **Test hook fires in headless mode:**
   ```bash
   GEMINI_STREAM_FILE=/tmp/test.jsonl gemini -p "say hello" --output-format json
   cat /tmp/test.jsonl
   # Should contain: {"type": "chunk", "text": "Hello!"} etc.
   ```

4. **Check `~/.gemini/settings.json` hooks are loaded:**
   - Ensure the `hooks` key with `AfterModel`, `BeforeTool`, `AfterTool`, `AfterAgent` entries is present
   - Run test above and verify the stream file is populated

5. **Test in the app:**
   - Open Quick Prompt (⌘⇧G) and send a prompt
   - Tokens should appear progressively instead of all at once
   - Status indicator should change: "Thinking…" → "Running shell command…" → "Generating…"

6. **Sync the installed hook:**
   ```bash
   cp hooks/stream-hook.py ~/.gemini/hooks/stream-hook.py
   chmod +x ~/.gemini/hooks/stream-hook.py
   ```

## Known Issues / Edge Cases to Verify

- `AfterModel` fires per-chunk — the `llm_response.candidates[0].content.parts` structure should be validated against the actual hook payload
- `thought` parts (reasoning tokens) may or may not appear; currently written as `{"type":"thinking","text":"..."}`
- If hooks don't fire, `sendToCLI()` falls back to full JSON output via `readDataToEndOfFile` — this fallback path should still work

---

# TODO: Gemini CLI Git Worktrees — Quick Prompt Integration

**Tag for search:** `TODO_GEMINI_WORKTREES`

```
git grep TODO_GEMINI_WORKTREES
```

## Background

Gemini CLI supports git worktrees as an experimental feature (`--worktree` flag,
`experimental.worktrees: true` in settings). This allows Gemini to work in an
isolated worktree + branch, keeping the main working tree clean.

We want to add a feature to the macOS Quick Prompt so that when the working
directory is a git repo, the user can optionally start a worktree session for
the current prompt — useful for agentic tasks that touch files.

- **Available in:** upstream `main` branch only — **not in gemini v0.35.1**
- **Setting:** `{"experimental": {"worktrees": true}}` in `settings.json`
- **Flag:** `gemini --worktree <name>` or `gemini -w`

## Planned Feature: Quick Prompt Worktree Support

When a user opens the Quick Prompt in a git repo directory, offer a "Use
worktree" toggle that passes `--worktree <name>` to the CLI. This ensures
agentic file edits happen on an isolated branch.

### Planned UX
- Detect if the working directory is a git repo (`git rev-parse --git-dir`)
- Show a branch/worktree icon toggle in the Quick Prompt header
- When enabled, pass `--worktree <auto-name>` to `gemini -p`
- Show the worktree branch name as a status badge during generation

### Files to Modify
- `macos/Sources/NexusAgent/QuickPromptWindow.swift` — add git repo detection,
  worktree toggle UI, and `--worktree` arg in `sendToCLI()`

## Verification Steps (Once New Release Is Out)

1. **Upgrade gemini:** `brew upgrade gemini` → confirm version > `0.35.1`

2. **Check `--worktree` flag is available:**
   ```bash
   gemini --help | grep worktree
   ```

3. **Enable via settings:**
   ```json
   { "experimental": { "worktrees": true } }
   ```

4. **Test manually:**
   ```bash
   cd /some/git/repo
   gemini --worktree test-branch -p "list files" --output-format json --approval-mode yolo
   # Should create .gemini/worktrees/test-branch/ and a branch worktree-test-branch
   git worktree list
   ```

5. **Implement Quick Prompt integration** using `TODO_GEMINI_WORKTREES` tag as a
   breadcrumb to find the right place to add `--worktree` arg in `sendToCLI()`.
