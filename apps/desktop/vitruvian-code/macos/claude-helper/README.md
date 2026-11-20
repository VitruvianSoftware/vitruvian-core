# Vitruvian Code Claude Helper

Node/TypeScript (ESM) helper process that runs Anthropic's `@anthropic-ai/claude-agent-sdk` and speaks the Agent Client Protocol (ACP v1) over newline-delimited JSON-RPC 2.0 on `stdin`/`stdout`.

- **Protocol transport:** `stdout` carries ACP JSON-RPC messages only; all diagnostic logging goes to `stderr` and never includes secret values.
- **How Vitruvian Code starts it:**
  ```sh
  node dist/main.js --claude-path /absolute/path/to/claude
  ```
- **Protocol contract:** [`protocol/schema.json`](protocol/schema.json) and [`protocol/examples/`](protocol/examples/) define and verify the ACP messages and `_vitruvian/*` extensions shared with the Swift ACP client.
- **Build and test (Bazel):**
  ```sh
  bazel build //apps/desktop/vitruvian-code/macos/claude-helper/...
  bazel test //apps/desktop/vitruvian-code/macos/claude-helper/...
  ```
