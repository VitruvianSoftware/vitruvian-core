# Vitruvian Core Clean Test Repo

## Interface
- `[affected-targets.sh:script entrypoint]`
- `[stream_hook.py:process_stream]`
- Subdirectory: [cmd](./cmd/README.md)
- Subdirectory: [macos](./macos/README.md)
- Subdirectory: [pkg](./pkg/README.md)
- Subdirectory: [web](./web/README.md)

## Invariants
- None

## Side Effects
- None

## Verification
- Run: `bazel test //tools/lint-naming/testdata/clean_repo/...`
