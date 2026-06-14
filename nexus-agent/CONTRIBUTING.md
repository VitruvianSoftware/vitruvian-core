# Contributing to NexusAgent

## ⚠️ This is a read-only mirror — how contributions work

`nexus-agent` is developed in the **[VitruvianSoftware/vitruvian-core](https://github.com/VitruvianSoftware/vitruvian-core)** monorepo (the single source of truth). **This repository is a read-only mirror** kept in sync by [Copybara](https://github.com/google/copybara) — you cannot merge directly here.

You contribute by opening a PR against this mirror; it is **imported back into the monorepo** for review:

1. **Open a PR** against `VitruvianSoftware/nexus-agent`.
2. **Sign the CLA** (first PR only): post this exact comment on your PR — `I have read the CLA Document and I hereby sign the CLA` (see [CLA.md](./CLA.md)). The CLA check must be green.
3. **A maintainer applies the `import-to-monorepo` label.** Only labelled, CLA-signed PRs are imported.
4. **The monorepo imports your PR automatically** (within ~15 min — a scheduled job), opening a PR in `vitruvian-core` under `nexus-agent/` **with you as the author**, where the full monorepo CI + review run.
5. **A maintainer merges the monorepo PR;** your mirror PR is then auto-commented and **auto-closed**, and your change reflects back here on the next export.

So: *open PR → sign CLA → maintainer labels → auto-import → review/merge in the monorepo → mirror PR auto-closes.* You never push to the monorepo directly. Keep changes scoped to this repo's content; merges happen in the monorepo now, not in this mirror.


First off, thank you for considering contributing to NexusAgent! It's people like you that make NexusAgent such a great tool.

## Code of Conduct

By participating in this project, you agree to abide by our Code of Conduct. Please be respectful and constructive in all communication.

## How Can I Contribute?

### Reporting Bugs
This section guides you through submitting a bug report. Following these guidelines helps maintainers and the community understand your report, reproduce the behavior, and find related reports.

- Use the GitHub issue search — check if the issue has already been reported.
- Check if the issue has been fixed — try to reproduce it using the latest `main` branch.
- Include a clear title and description.
- Include steps to reproduce, what you expected to see, and what actually happened.
- Include the version of NexusAgent and any other relevant environment details (e.g., Node.js version, OS).

### Suggesting Enhancements
This section guides you through submitting an enhancement suggestion, including completely new features and minor improvements to existing functionality.

- Use the GitHub issue search — check if the enhancement has already been suggested.
- Provide a clear and detailed explanation of the feature.
- Explain why this enhancement would be useful to most users.
- Provide examples or mockups to demonstrate how the enhancement would work.

### Pull Requests
The process described here has several goals:
- Maintain NexusAgent's quality
- Fix problems that are important to users
- Engage the community in working toward a better platform
- Enable a sustainable system for NexusAgent's maintainers to review contributions

Please follow these steps to have your contribution considered by the maintainers:
1. Follow the style guide and ensure your code is clean and well-documented.
2. Write tests for new features and bug fixes if applicable.
3. Ensure all tests pass.
4. Update the README.md and/or documentation with details of changes to the interface.
5. Provide a clear and descriptive PR title and description.

## Styleguides

### Git Commit Messages
- Use the present tense ("Add feature" not "Added feature")
- Use the imperative mood ("Move cursor to..." not "Moves cursor to...")
- Limit the first line to 72 characters or less
- Reference issues and pull requests liberally after the first line

### JavaScript Styleguide
- We use standard ES module syntax.
- Prefer `const` and `let` over `var`.
- Use descriptive variable and function names.
- Keep functions small and focused on a single task.

## License
By contributing to NexusAgent, you agree that your contributions will be licensed under the Apache 2.0 License.
