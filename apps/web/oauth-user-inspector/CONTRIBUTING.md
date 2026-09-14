# Contributing

This repository includes a small pre-commit safety script that prevents accidentally committing local environment files (like `.env`) and build outputs (`dist`, `dist-server`).

To enable it locally run the included npm helper which installs the hook:

```bash
npm run setup-dev
```

Alternatively, you can install the hook manually (equivalent):

```bash
# Make the repo hooks directory if needed
mkdir -p .git/hooks
# Link the provided script to pre-commit
ln -sf ../../scripts/check-sensitive.sh .git/hooks/pre-commit
# Ensure executable
chmod +x .git/hooks/pre-commit
```

If you intentionally need to commit a built artifact, update `.gitignore` or ask a maintainer for guidance.
