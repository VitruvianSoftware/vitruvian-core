# Image Bump Changelog

## Overview
Component package providing `//tools/ci:image_bump_changelog` (`tools/ci/src/image_bump_changelog`). Resolves OCI image `org.opencontainers.image.revision` labels across multi-arch indexes and platform manifests for two digests and formats a Markdown changelog for automated digest-bump pull requests.

## Interface
- `[main.rs:main]`
- `[lib.rs:run]`
- `[lib.rs:parse_image_ref]`
- `[lib.rs:normalize_digest]`
- `[lib.rs:extract_digest_from_manifest_text]`
- `[lib.rs:select_platform_manifest]`
- `[lib.rs:render_markdown]`

## Side Effects
- Executes `curl` against OCI registry `/token`, `/v2/.../manifests/...`, `/v2/.../blobs/...` endpoints (and `api.github.com/repos/.../compare/...` in `--upstream` mode).
- Executes read-only `git show` and `git log --no-merges` in local repository mode.

## Verification
- Run: `bazel test //tools/ci:image_bump_changelog_lib_test //tools/ci:image_bump_changelog_test //tools/ci:build_ci_tool_test`
