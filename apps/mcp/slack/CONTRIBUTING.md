# Contributing to Vitruvian Slack MCP

## ⚠️ This is a read-only mirror — how contributions work

`mcp-slack` is developed in the **[VitruvianSoftware/vitruvian-core](https://github.com/VitruvianSoftware/vitruvian-core)** monorepo (the single source of truth). **This repository is a read-only mirror** kept in sync by [Copybara](https://github.com/google/copybara) — you cannot merge directly here.

You contribute by opening a PR against this mirror; it is **imported back into the monorepo** for review:

1. **Open a PR** against `VitruvianSoftware/mcp-slack`.
2. **Sign the CLA** (first PR only): post this exact comment on your PR — `I have read the CLA Document and I hereby sign the CLA` (see [CLA.md](./CLA.md)). The CLA check must be green.
3. **A maintainer applies the `import-to-monorepo` label.** Only labelled, CLA-signed PRs are imported.
4. **The monorepo imports your PR automatically** (within ~15 min — a scheduled job), opening a PR in `vitruvian-core` under `mcp-slack/` **with you as the author**, where the full monorepo CI + review run.
5. **A maintainer merges the monorepo PR;** your mirror PR is then auto-commented and **auto-closed**, and your change reflects back here on the next export.

So: *open PR → sign CLA → maintainer labels → auto-import → review/merge in the monorepo → mirror PR auto-closes.* You never push to the monorepo directly. Keep changes scoped to this repo's content; merges happen in the monorepo now, not in this mirror.


We'd love for you to contribute to our source code and to make it even better than it is today!

## Development Workflow

1. Fork the repo and create your branch from `main`.
2. If you've added code that should be tested, add tests.
3. If you've changed APIs, update the documentation.
4. Ensure the test suite passes (`npm run build`).
5. Make sure your code respects the `addlicense` checks. We use Apache 2.0.
   ```bash
   go install github.com/google/addlicense@latest
   ~/go/bin/addlicense -c "Vitruvian Software" -l apache -ignore "node_modules/**" -ignore "dist/**" -ignore ".github/**" .
   ```

## Commit Guidelines

We use [Conventional Commits](https://www.conventionalcommits.org/). 
Please ensure your commit messages are formatted appropriately so `release-please` can automatically generate the changelog.

Examples:
- `feat: add new mcp tool for slack huddles`
- `fix: resolve crash on missing canvas permissions`
- `docs: update readme with new token scopes`

## License

By contributing, you agree that your contributions will be licensed under its Apache 2.0 License.
