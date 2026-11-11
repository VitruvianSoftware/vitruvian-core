# Src

## Overview
Component package providing implementation for `tools/git/src`.

## Interface
- `[lib.rs:init_process]`
- `[lib.rs:strcoll_cmp]`
- `[lib.rs:locale_sort_unique_bytes]`
- `[lib.rs:sorted_intersection_bytes]`
- `[lib.rs:usage_text]`
- `[lib.rs:parse_repo_mapping]`
- `[lib.rs:lookup_in_manifest]`
- `[lib.rs:is_conventional_commit]`
- `[lib.rs:is_revert_title]`
- `[lib.rs:is_valid_commit_subject]`
- `[lib.rs:extract_subject_from_file_content]`
- `[lib.rs:extract_subject_from_message]`
- `[lib.rs:is_agent_bot_name_bytes]`
- `[lib.rs:is_agent_bot_name]`
- `[lib.rs:has_conflict_marker]`
- `[lib.rs:find_conflict_markers]`
- `[lib.rs:sorted_intersection]`
- `[lib.rs:parse_export_line_bytes]`
- `[lib.rs:parse_export_line]`
- `[lib.rs:is_git_identity_export_line_bytes]`

## Invariants
- None

## Side Effects
- [lib.rs:61]: `#   bazel run //tools/git:sync                    # fetch, then rebase this b...`
- [lib.rs:319]: `.spawn()`

## Verification
- Run: `bazel test //tools/git/src/...`
