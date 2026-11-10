# TODO

## Resolved: live streaming (was `TODO_GEMINI_HOOKS`)

The Quick Prompt chat view used to wait on Gemini CLI lifecycle hooks
(`AfterModel`, `AfterTool`, `AfterAgent`) to stream tokens and tool activity.
Google retired Gemini CLI for individual accounts; the bot and the macOS app now
drive the Antigravity CLI (`agy`), whose `--output-format stream-json` emits
`agent_response` text deltas and `tool` step updates directly on stdout. No hook
script, no `GEMINI_STREAM_FILE`, no `~/.gemini/settings.json` registration.

Removed in the migration: `hooks/stream_hook.py`, `StreamFileWatcher`.
