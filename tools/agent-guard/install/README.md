# Install

## Overview
Component package providing implementation for `tools/agent-guard/install`.

## Interface
- `[argparse.rs:PROG]`
- `[argparse.rs:DESCRIPTION]`
- `[argparse.rs:Args]`
- `[argparse.rs:Parsed]`
- `[argparse.rs:parse]`
- `[difflib.rs:unified_diff]`
- `[installer.rs:CLAUDE_COMMAND]`
- `[installer.rs:AGY_COMMAND]`
- `[installer.rs:CLAUDE_SETTINGS_REL]`
- `[installer.rs:AGY_HOOKS_REL]`
- `[installer.rs:LAUNCHER_REL]`
- `[installer.rs:COMMAND_MATCHER]`
- `[installer.rs:FILE_MATCHER]`
- `[installer.rs:AGY_HOOK_NAME]`
- `[installer.rs:AGY_MATCHER]`
- `[installer.rs:HOOK_TIMEOUT]`
- `[installer.rs:AGENT_MARKERS]`
- `[installer.rs:claude_entries]`
- `[installer.rs:agy_entry]`
- `[installer.rs:install_dir]`

## Invariants
- [testlib.rs:59]: `runfile_opt(rel).unwrap_or_else(|| panic!("runfile {} not found", rel))`
- [testlib.rs:74]: `fs::read_to_string(path).unwrap_or_else(|e| panic!("read {}: {}", path, e))`
- [testlib.rs:81]: `fs::write(path, text).unwrap_or_else(|e| panic!("write {}: {}", path, e));`

## Side Effects
- [sys.rs:214]: `/// subprocess.TimeoutExpired`
- [sys.rs:220]: `/// `subprocess.run(argv, input=input, stdout=PIPE, stderr=PIPE, cwd=cwd, env...`
- [sys.rs:234]: `let mut child = match cmd.spawn() {`

## Verification
- Run: `bazel test //tools/agent-guard/install/...`
