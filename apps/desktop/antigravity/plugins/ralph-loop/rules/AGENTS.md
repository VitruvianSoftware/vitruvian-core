# ralph-loop: iterative completion-promise loops

When a Ralph Loop is active for your conversation (stored in
`~/.gemini/antigravity/ralph-loop-state/<conversationId>.json`), the `Stop`
hook automatically continues your turn until the task is genuinely complete.

- **Completion promise**: Only emit `<promise>YOUR_PROMISE</promise>` when the
  task and all verification steps are completely finished and verified. Never
  emit the `<promise>...</promise>` tag prematurely or quote it in full before
  completion, because the `Stop` hook checks for that exact tag in your last
  assistant response.
- **Bounded iterations**: Each continuation increments `iteration` up to
  `maxIterations`. Use each iteration to inspect test output, fix remaining
  issues, and verify progress.
