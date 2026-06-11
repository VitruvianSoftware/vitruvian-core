# Release Process

Tabula uses [release-please](https://github.com/googleapis/release-please) from Google to automate
versioning and releases across multiple components in the monorepo.

## How It Works

### Automated Release PR Creation

1. When commits are pushed to `main`, release-please analyzes commits using
   [Conventional Commits](https://www.conventionalcommits.org/)
2. It automatically creates or updates a Release PR with:
   - Updated version numbers in `package.json` files
   - Generated `CHANGELOG.md` files for each component
   - Release notes based on commit messages

### Component Releases

Tabula has multiple releasable components:

- **Extension** (`@tabula/extension`) - Browser extension
- **API** (`@tabula/api`) - Backend service
- **CLI** (`@tabula/cli`) - Command-line tool
- **Web** (`@tabula/web`) - Web dashboard

Each component is versioned independently and can be released separately.

### Release Workflow

1. **Commit with Conventional Commits format:**

   ```bash
   git commit -m "feat(extension): add tab suspension feature"
   git commit -m "fix(api): resolve authentication bug"
   git commit -m "docs: update README"
   ```

2. **Release-please creates/updates PR:**
   - Analyzes commits since last release
   - Updates version numbers (following semver)
   - Generates changelogs
   - Creates a Release PR

3. **Review and merge:**
   - Review the Release PR
   - Merge to `main` when ready

4. **Automatic actions on merge:**
   - GitHub release is created
   - Git tags are created (e.g., `extension-v0.2.0`)
   - For extension releases:
     - Extension is built
     - Two packages are created:
       - Full package with source maps
       - Chrome Web Store ready package (without source maps)
     - Packages are uploaded to GitHub release
     - Artifacts are stored for 90 days

## Conventional Commits

Use these commit types to trigger appropriate version bumps:

### Breaking Changes (Major)

```bash
git commit -m "feat(extension)!: redesign workspace API"
# or
git commit -m "feat(extension): change API

BREAKING CHANGE: Workspace API now requires authentication"
```

### Features (Minor)

```bash
git commit -m "feat(extension): add Firefox support"
git commit -m "feat(api): add workspace search endpoint"
```

### Fixes (Patch)

```bash
git commit -m "fix(extension): resolve tab suspension issue"
git commit -m "fix(api): fix database connection timeout"
```

### Other Types (No version bump)

```bash
git commit -m "docs: update installation guide"
git commit -m "chore: update dependencies"
git commit -m "ci: improve build workflow"
git commit -m "test: add unit tests for workspace service"
git commit -m "refactor(extension): simplify storage service"
git commit -m "style: format code with prettier"
git commit -m "perf(api): optimize database queries"
```

## Component Scopes

Use these scopes to target specific components:

- `extension` - Browser extension
- `api` - Backend API
- `cli` - Command-line tool
- `web` - Web dashboard

Example:

```bash
git commit -m "feat(extension): add dark mode"
git commit -m "fix(api): resolve CORS issue"
```

## Extension Packaging

When an extension release is created, the workflow automatically:

1. **Builds the extension:**

   ```bash
   npm ci
   npm run build --workspace=extension
   ```

2. **Creates two packages:**

   **Full Package** (`tabula-extension-vX.Y.Z.zip`)
   - Contains all built files
   - Includes source maps for debugging
   - Includes TypeScript definitions

   **Chrome Web Store Package** (`tabula-extension-chrome-vX.Y.Z.zip`)
   - Production-ready
   - Excludes source maps (\*.map)
   - Excludes TypeScript definitions (_.d.ts, _.d.ts.map)
   - Optimized for Chrome Web Store submission

3. **Uploads to GitHub release:**
   - Both packages attached to the release
   - Available for download
   - Artifacts stored for 90 days

## Manual Release Trigger

If you need to manually trigger a release:

1. **Create a release commit:**

   ```bash
   git commit -m "chore: release extension v0.2.0" --allow-empty
   git push origin main
   ```

2. **Or manually create the Release PR:**

   ```bash
   # Install release-please CLI
   npm install -g release-please

   # Create release PR
   release-please release-pr \
     --repo-url=BlueCentre/tabula \
     --token=$GITHUB_TOKEN
   ```

## Versioning Strategy

Tabula follows [Semantic Versioning](https://semver.org/):

- **Major (X.0.0)**: Breaking changes
- **Minor (0.X.0)**: New features (backward compatible)
- **Patch (0.0.X)**: Bug fixes (backward compatible)

### Pre-1.0 Versions

Before 1.0.0, the project uses these rules:

- Breaking changes bump MINOR version (e.g., 0.1.0 → 0.2.0)
- Features bump PATCH version (e.g., 0.1.0 → 0.1.1)
- Fixes bump PATCH version (e.g., 0.1.0 → 0.1.1)

This is configured with:

```json
{
  "bump-minor-pre-major": true,
  "bump-patch-for-minor-pre-major": true
}
```

## Configuration Files

### `.release-please-manifest.json`

Tracks current versions of each component:

```json
{
  ".": "0.1.0",
  "api": "0.1.0",
  "extension": "0.1.0",
  "cli": "0.1.0",
  "web": "0.1.0"
}
```

### `release-please-config.json`

Configuration for release-please behavior:

- Release types for each component
- Package names
- Changelog paths
- Component names for tags

## Troubleshooting

### Release PR not created

1. **Check commit messages**: Ensure they follow Conventional Commits format
2. **Check workflow runs**: View GitHub Actions logs
3. **Verify configuration**: Ensure config files are valid JSON

### Package not uploaded to release

1. **Check workflow logs**: Look for build errors
2. **Verify extension builds**: Run `npm run build --workspace=extension` locally
3. **Check permissions**: Ensure GitHub Actions has write permissions

### Wrong version bumped

1. **Check commit types**: Use correct types (feat, fix, etc.)
2. **Use correct scopes**: Target the right component
3. **Breaking changes**: Use `!` or `BREAKING CHANGE:` for major bumps

## Best Practices

1. **Write clear commit messages**: Follow Conventional Commits strictly
2. **Scope your commits**: Always include component scope
3. **Review Release PRs**: Check generated changelogs before merging
4. **Test before release**: Ensure all tests pass before merging Release PR
5. **Document breaking changes**: Provide migration guides in commit bodies

## Chrome Web Store Submission

After an extension release:

1. **Download the Chrome package:**

   ```bash
   # From GitHub release page
   wget https://github.com/BlueCentre/tabula/releases/download/extension-vX.Y.Z/tabula-extension-chrome-vX.Y.Z.zip
   ```

2. **Upload to Chrome Web Store:**
   - Go to [Chrome Web Store Developer Dashboard](https://chrome.google.com/webstore/devconsole)
   - Upload the `tabula-extension-chrome-vX.Y.Z.zip`
   - Fill in store listing information
   - Submit for review

3. **Update release notes:**
   - Copy changelog from GitHub release
   - Add to Chrome Web Store listing

## Future Enhancements

- Automatic Chrome Web Store publishing (requires API credentials)
- Firefox Add-ons automatic publishing
- Edge Add-ons automatic publishing
- Slack/Discord notifications for releases
- Automated testing before release creation

## References

- [release-please documentation](https://github.com/googleapis/release-please)
- [Conventional Commits specification](https://www.conventionalcommits.org/)
- [Semantic Versioning](https://semver.org/)
- [Chrome Web Store Developer Documentation](https://developer.chrome.com/docs/webstore/)
