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
| `macos/Sources/GeminiBotBar/QuickPromptWindow.swift` | `StreamFileWatcher` class + streaming `sendToCLI()` |

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
