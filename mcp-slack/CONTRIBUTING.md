# Contributing to Vitruvian Slack MCP

We'd love for you to contribute to our source code and to make it even better than it is today!

## Development Workflow

1. Fork the repo and create your branch from `main`.
2. If you've added code that should be tested, add tests.
3. If you've changed APIs, update the documentation.
4. Ensure the test suite passes (`npm run build`).
5. Make sure your code respects the `addlicense` checks. We use Apache 2.0.
   ```bash
   go install github.com/google/addlicense@latest
   ~/go/bin/addlicense -c "Vitruvian Software" -l apache -ignore "node_modules/**" -ignore "dist/**" .
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
