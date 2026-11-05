---
name: ralph-loop
description: Start, inspect, or cancel self-referential iterative development loops (Ralph Loops) in Antigravity conversations. Use when a task should iterate autonomously across turns until a completion promise (<promise>...</promise>) is satisfied or maxIterations is reached.
---

# ralph-loop

Use this skill to configure or interact with the `ralph-loop` Antigravity
desktop plugin.

## How a Ralph Loop works

1. **State file**: Each conversation's loop state lives at
   `~/.gemini/antigravity/ralph-loop-state/<conversationId>.json` with fields:
   - `conversationId`: owning conversation UUID
   - `active`: boolean (`true` while looping)
   - `status`: `"running" | "completed" | "cancelled" | "max_iterations"`
   - `prompt`: task description and verification criteria
   - `completionPromise`: token to wrap inside `<promise>...</promise>` (default `"DONE"`)
   - `iteration`: current iteration counter (`0..maxIterations`)
   - `maxIterations`: upper bound on automatic continuations (default `10`)
2. **Stop hook (`hooks/ralph-stop.sh`)**: On every turn end, if `active` is
   `true`, `iteration < maxIterations`, and the last assistant message does not
   contain `<promise>${completionPromise}</promise>`, the hook increments
   `iteration` and returns `{"decision": "continue", "reason": "..."}`.
3. **Finishing the loop**: Once all tests and requirements pass, output
   `<promise>${completionPromise}</promise>` in your final response to mark the
   loop `completed`.
