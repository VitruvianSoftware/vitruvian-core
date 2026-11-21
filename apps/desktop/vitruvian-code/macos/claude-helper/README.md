# Vitruvian Code Claude Helper

Node/TypeScript (ESM) helper process that runs Anthropic's `@anthropic-ai/claude-agent-sdk` and speaks the Agent Client Protocol (ACP v1) over newline-delimited JSON-RPC 2.0 on `stdin`/`stdout`.

- **Protocol transport:** `stdout` carries ACP JSON-RPC messages only; all diagnostic logging goes to `stderr` and never includes secret values.
- **How Vitruvian Code starts it:**
  ```sh
  Contents/Helpers/node Contents/Resources/claude-helper/claude-helper.mjs --claude-path /absolute/path/to/claude
  ```
- **Checked-in ESM bundle & Node lock:**
  - `bundle/claude-helper.mjs` — self-contained ESM bundle built with `esbuild` (`platform=node`, `target=node22`, excluding `@anthropic-ai/claude-agent-sdk-*` optional platform binaries).
  - `bundle/packages.json` — manifest of npm packages bundled into `claude-helper.mjs`, verified against `../../THIRD_PARTY_NOTICES.md`.
  - `node.lock` — pinned Node.js version (matching `//.nvmrc`) and official Darwin arm64/x64 tarball SHA-256 sums used by standalone releases.
  - Regenerate the checked-in bundle and manifest:
    ```sh
    bazel run //apps/desktop/vitruvian-code/macos/claude-helper:update_bundle
    ```
- **Protocol contract:** [`protocol/schema.json`](protocol/schema.json) and [`protocol/examples/`](protocol/examples/) define and verify the ACP messages and `_vitruvian/*` extensions shared with the Swift ACP client.
- **Build and test (Bazel):**
  ```sh
  bazel build //apps/desktop/vitruvian-code/macos/claude-helper/...
  bazel test //apps/desktop/vitruvian-code/macos/claude-helper/...
  ```
  Covers `helper_test`, `bundle_isolated_load_test`, `node_lock_test`, `third_party_notices_test`, and `update_bundle_0_test` / `update_bundle_1_test`.
